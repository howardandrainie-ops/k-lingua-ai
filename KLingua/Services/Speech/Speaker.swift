import AVFoundation

/// 韓語語音合成（TTS）。全 App 共用一個合成器，避免播放途中被釋放。
/// 這是 iOS 內建的合成語音，不是真人錄音；畫面上會註明。
@MainActor
final class Speaker {
    static let shared = Speaker()

    private let synthesizer = AVSpeechSynthesizer()
    private var sessionConfigured = false

    /// 裝置上品質最好的 ko-KR 語音；沒有下載任何韓語語音時為 nil
    let voice: AVSpeechSynthesisVoice?

    private init() {
        let korean = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "ko-KR" }
        voice = korean.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "ko-KR")
    }

    var hasKoreanVoice: Bool { voice != nil }

    func speak(_ text: String, slow: Bool = false) {
        let spoken = Self.speakablePart(of: text)
        guard !spoken.isEmpty else { return }
        configureSessionIfNeeded()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (slow ? 0.6 : 0.9)
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// 教材提示常寫成「이거 뭐예요?（提示：牛奶）」，只唸全形括號前的韓文
    static func speakablePart(of text: String) -> String {
        let cut = text.split(separator: "（", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? text
        return cut.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        // 靜音模式下仍能播放示範音
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
