import AVFoundation
import Observation
import Speech
import UIKit
import KLinguaCore

/// 一次錄音＋辨識的結果
struct SpeechCapture: Sendable {
    /// 辨識候選，最可能的在前；沒聽到時為空
    var transcripts: [String]
    /// 開始說話的時間（以音量偵測，不是辨識結果）
    var onsetDate: Date?
    var stoppedAt: Date
    var audioURL: URL?
    var onDevice: Bool
    /// 辨識器回報的平均信心（0–1，僅供紀錄，不作為發音分數）
    var confidence: Double?
    var errorMessage: String?

    var best: String { transcripts.first ?? "" }
}

enum SpeechInputError: LocalizedError {
    case notAuthorized
    case recognizerUnavailable
    case noMicrophone
    case audio(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: "沒有麥克風或語音辨識權限。"
        case .recognizerUnavailable: "韓語語音辨識目前無法使用（可能需要網路，或裝置不支援）。"
        case .noMicrophone: "找不到可用的麥克風。"
        case .audio(let m): "錄音失敗：\(m)"
        }
    }
}

/// 錄音與辨識的底層處理。音訊回呼在背景執行緒，所以這個類別不屬於 MainActor，
/// 內部狀態一律用鎖保護。
final class CaptureEngine: @unchecked Sendable {
    private let lock = NSLock()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var file: AVAudioFile?
    private var detector = VoiceActivityDetector()
    private var framesSeen: Double = 0
    private var sampleRate: Double = 44_100
    private var transcripts: [String] = []
    private var confidence: Double?
    private var errorMessage: String?
    private var finished = false
    private var finalContinuation: CheckedContinuation<Void, Never>?
    private var running = false

    // 以下回呼可能在任何執行緒被呼叫
    var onLevel: (@Sendable (Float) -> Void)?
    var onPartial: (@Sendable (String) -> Void)?
    var onOnset: (@Sendable (Double) -> Void)?
    var onEndOfSpeech: (@Sendable () -> Void)?

    /// 開始錄音與辨識，回傳是否為裝置端辨識
    func start(recognizer: SFSpeechRecognizer, fileURL: URL?) throws -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechInputError.audio(error.localizedDescription)
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        let onDevice = recognizer.supportsOnDeviceRecognition
        if onDevice { request.requiresOnDeviceRecognition = true }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechInputError.noMicrophone }

        lock.lock()
        self.request = request
        detector = VoiceActivityDetector()
        framesSeen = 0
        sampleRate = format.sampleRate
        transcripts = []
        confidence = nil
        errorMessage = nil
        finished = false
        file = fileURL.flatMap { try? AVAudioFile(forWriting: $0, settings: format.settings) }
        lock.unlock()

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw SpeechInputError.audio(error.localizedDescription)
        }
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handle(result: result, error: error)
        }
        lock.lock()
        self.task = task
        running = true
        lock.unlock()
        return onDevice
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        var level: Float = -160
        if let channels = buffer.floatChannelData, frames > 0 {
            level = VoiceActivityDetector.rmsDB(UnsafeBufferPointer(start: channels[0], count: frames))
        }
        lock.lock()
        request?.append(buffer)
        try? file?.write(from: buffer)
        let t = framesSeen / sampleRate
        framesSeen += Double(frames)
        let hadOnset = detector.onset != nil
        let hadEnd = detector.endOfSpeech != nil
        detector.feed(levelDB: level, at: t)
        let newOnset = hadOnset ? nil : detector.onset
        let ended = !hadEnd && detector.endOfSpeech != nil
        let onLevel = onLevel, onOnset = onOnset, onEnd = onEndOfSpeech
        lock.unlock()

        onLevel?(level)
        if let newOnset { onOnset?(newOnset) }
        if ended { onEnd?() }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        lock.lock()
        var partial: String?
        if let result {
            let best = result.bestTranscription.formattedString
            var all = [best]
            for t in result.transcriptions.map(\.formattedString) where !all.contains(t) { all.append(t) }
            transcripts = all.filter { !$0.isEmpty }
            let segments = result.bestTranscription.segments
            if result.isFinal, !segments.isEmpty {
                confidence = Double(segments.map(\.confidence).reduce(0, +)) / Double(segments.count)
            }
            partial = best
        }
        if let error {
            let ns = error as NSError
            // 1110 = 沒有偵測到語音；216/301 = 被取消。這些不是真正的錯誤。
            if !(ns.domain == "kAFAssistantErrorDomain" && [1110, 216, 301].contains(ns.code)) {
                errorMessage = error.localizedDescription
            }
        }
        var continuation: CheckedContinuation<Void, Never>?
        if result?.isFinal == true || error != nil {
            finished = true
            continuation = finalContinuation
            finalContinuation = nil
        }
        let onPartial = onPartial
        lock.unlock()

        if let partial { onPartial?(partial) }
        continuation?.resume()
    }

    private func resumeFinal() {
        lock.lock()
        finished = true
        let c = finalContinuation
        finalContinuation = nil
        lock.unlock()
        c?.resume()
    }

    private func stopAudio() {
        lock.lock()
        let wasRunning = running
        running = false
        lock.unlock()
        guard wasRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        lock.lock()
        request?.endAudio()
        file = nil // 釋放即寫入完成
        lock.unlock()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    /// 停止錄音並等待最終辨識結果（最多 3 秒）
    func stop() async -> (transcripts: [String], onset: Double?, confidence: Double?, error: String?) {
        stopAudio()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if finished {
                lock.unlock()
                c.resume()
                return
            }
            finalContinuation = c
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { self.resumeFinal() }
        }
        lock.lock()
        task?.cancel()
        task = nil
        request = nil
        let out = (transcripts, detector.onset, confidence, errorMessage)
        lock.unlock()
        return out
    }

    func cancel() {
        stopAudio()
        lock.lock()
        task?.cancel()
        task = nil
        request = nil
        lock.unlock()
        resumeFinal()
    }
}

/// 畫面使用的語音輸入狀態（全 App 共用一個）
@MainActor
@Observable
final class SpeechInput {
    static let shared = SpeechInput()

    enum Phase: Equatable { case idle, listening, processing }
    enum Permission: Equatable { case notDetermined, denied, granted, unavailable }

    private(set) var phase: Phase = .idle
    private(set) var partial = ""
    private(set) var level: Float = -160
    private(set) var onsetDate: Date?
    private(set) var lastError: String?
    private var permissionRevision = 0

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    @ObservationIgnored private let engine = CaptureEngine()
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var onDevice = false
    @ObservationIgnored private var audioURL: URL?
    @ObservationIgnored private var autoStop: (@MainActor () -> Void)?
    @ObservationIgnored private var session = 0

    /// 最長錄音秒數
    let maxSeconds: Double = 12

    private init() {}

    var permission: Permission {
        _ = permissionRevision
        guard recognizer != nil else { return .unavailable }
        let speech = SFSpeechRecognizer.authorizationStatus()
        let mic = AVAudioApplication.shared.recordPermission
        if speech == .denied || speech == .restricted || mic == .denied { return .denied }
        if speech == .authorized && mic == .granted { return .granted }
        return .notDetermined
    }

    var supportsOnDevice: Bool { recognizer?.supportsOnDeviceRecognition ?? false }
    var recognizerAvailable: Bool { recognizer?.isAvailable ?? false }

    @discardableResult
    func requestPermissions() async -> Bool {
        let mic = await AVAudioApplication.requestRecordPermission()
        let speech = await Self.requestSpeechAuthorization()
        permissionRevision += 1
        return mic && speech == .authorized
    }

    nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
    }

    /// 開始錄音。偵測到說完（或超過最長秒數）時呼叫 onAutoStop。
    func start(onAutoStop: @escaping @MainActor () -> Void) throws {
        guard phase == .idle else { return }
        guard permission == .granted else { throw SpeechInputError.notAuthorized }
        guard let recognizer, recognizer.isAvailable else { throw SpeechInputError.recognizerUnavailable }
        Speaker.shared.stop()
        partial = ""
        level = -160
        onsetDate = nil
        lastError = nil
        autoStop = onAutoStop
        session += 1
        let current = session
        let started = Date()
        startedAt = started

        engine.onLevel = { [weak self] value in
            Task { @MainActor in self?.level = value }
        }
        engine.onPartial = { [weak self] text in
            Task { @MainActor in self?.partial = text }
        }
        engine.onOnset = { [weak self] seconds in
            Task { @MainActor in self?.onsetDate = started.addingTimeInterval(seconds) }
        }
        engine.onEndOfSpeech = { [weak self] in
            Task { @MainActor in self?.fireAutoStop(session: current) }
        }

        let url = RecordingStore.newURL()
        do {
            onDevice = try engine.start(recognizer: recognizer, fileURL: url)
            audioURL = url
        } catch {
            lastError = error.localizedDescription
            throw error
        }
        phase = .listening
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(self?.maxSeconds ?? 12))
            self?.fireAutoStop(session: current)
        }
    }

    private func fireAutoStop(session s: Int) {
        guard s == session, phase == .listening else { return }
        autoStop?()
    }

    func stop() async -> SpeechCapture {
        guard phase == .listening else {
            return SpeechCapture(transcripts: [], onsetDate: nil, stoppedAt: Date(), audioURL: nil, onDevice: onDevice,
                                 confidence: nil, errorMessage: nil)
        }
        let stoppedAt = Date()
        phase = .processing
        let r = await engine.stop()
        phase = .idle
        autoStop = nil
        lastError = r.error
        let onset = r.onset.map { startedAt.addingTimeInterval($0) }
        return SpeechCapture(transcripts: r.transcripts, onsetDate: onset, stoppedAt: stoppedAt, audioURL: audioURL,
                             onDevice: onDevice, confidence: r.confidence, errorMessage: r.error)
    }

    func cancel() {
        guard phase != .idle else { return }
        engine.cancel()
        phase = .idle
        autoStop = nil
    }
}

/// 使用者錄音檔：存在 App 的 Documents/Recordings，只保留最近 200 個
enum RecordingStore {
    static var directory: URL {
        let dir = URL.documentsDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func newURL() -> URL {
        prune(keep: 200)
        return directory.appending(path: "rec-\(UUID().uuidString).caf")
    }

    static func url(named name: String) -> URL { directory.appending(path: name) }

    static func prune(keep: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]),
              files.count > keep else { return }
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a < b
        }
        for url in sorted.prefix(files.count - keep) { try? fm.removeItem(at: url) }
    }
}

/// 播放自己的錄音
@MainActor
final class RecordingPlayer {
    static let shared = RecordingPlayer()
    private var player: AVAudioPlayer?

    func play(_ url: URL) {
        Speaker.shared.stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}

/// 開啟系統設定（讓使用者自行開啟權限）
@MainActor
func openAppSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }
}
