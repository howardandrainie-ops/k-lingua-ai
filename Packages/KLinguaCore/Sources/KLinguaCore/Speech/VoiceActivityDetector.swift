import Foundation

/// 偵測「開始說話」與「說完」的時間點（以音量為準，不依賴辨識結果）。
/// - 開始說話：用來量測思考時間（FSI 反應速度）
/// - 說完：連續靜音超過 `silenceToEnd` 秒就自動停止錄音
public struct VoiceActivityDetector: Sendable {
    /// 開頭用來估計環境噪音的音框數
    public var calibrationFrames = 5
    /// 高於噪音多少 dB 視為說話
    public var marginDB: Float = 12
    /// 說話門檻的下限
    public var minimumThresholdDB: Float = -50
    /// 噪音估計的上限（避免一開口就被當成噪音）
    public var maximumNoiseDB: Float = -35
    /// 連續幾個音框高於門檻才確認開始說話
    public var framesToConfirm = 3
    /// 說話後連續靜音多久視為說完（秒）
    public var silenceToEnd: Double = 1.2

    public private(set) var onset: Double?
    public private(set) var endOfSpeech: Double?

    private var calibration: [Float] = []
    private var voicedRunStart: Double?
    private var voicedRunLength = 0
    private var lastVoiced: Double?

    public init() {}

    public var threshold: Float {
        let noise = calibration.isEmpty ? minimumThresholdDB : calibration.reduce(0, +) / Float(calibration.count)
        return max(minimumThresholdDB, min(noise, maximumNoiseDB) + marginDB)
    }

    /// 餵入一個音框的音量（dBFS）與它的時間（從開始錄音算起的秒數）
    public mutating func feed(levelDB: Float, at time: Double) {
        guard endOfSpeech == nil else { return }
        if calibration.count < calibrationFrames {
            calibration.append(levelDB)
            return
        }
        let voiced = levelDB >= threshold
        if voiced {
            lastVoiced = time
            if onset == nil {
                if voicedRunStart == nil { voicedRunStart = time }
                voicedRunLength += 1
                if voicedRunLength >= framesToConfirm { onset = voicedRunStart }
            }
        } else {
            if onset == nil {
                voicedRunStart = nil
                voicedRunLength = 0
            } else if let last = lastVoiced, time - last >= silenceToEnd {
                endOfSpeech = time
            }
        }
    }

    /// 均方根音量（dBFS），靜音時回傳 -160
    public static func rmsDB<C: Collection>(_ samples: C) -> Float where C.Element == Float {
        guard !samples.isEmpty else { return -160 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = (sum / Float(samples.count)).squareRoot()
        return rms > 0 ? max(-160, 20 * log10(rms)) : -160
    }
}
