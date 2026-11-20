import AVFoundation
import Speech
import SwiftUI
import KLinguaCore

/// 實機環境自檢：列出裝置上可用的 ko-KR 語音與語音辨識狀態。
/// 這是真實查詢系統 API 的結果，不是假資料。
struct SystemCheckView: View {
    @State private var report = SystemCheckReport.empty
    // 用 @State 保存，避免 View 重建時合成器被釋放而中斷播放。
    @State private var synthesizer = AVSpeechSynthesizer()

    var body: some View {
        List {
            Section("專案") {
                LabeledContent("核心版本", value: KLinguaCoreInfo.version)
                LabeledContent("開發階段", value: "第 \(KLinguaCoreInfo.developmentStage) 階段：架構與環境")
            }

            Section {
                if report.koreanVoices.isEmpty {
                    Text("找不到 ko-KR 語音。請到「設定 › 輔助使用 › 朗讀內容 › 聲音 › 韓文」下載。")
                        .foregroundStyle(.orange)
                } else {
                    ForEach(report.koreanVoices) { voice in
                        LabeledContent(voice.name, value: voice.quality)
                    }
                }
                Button("播放測試：저는 커피를 마셔요.") {
                    speakSample()
                }
            } header: {
                Text("韓語語音合成（TTS）")
            } footer: {
                Text("建議下載「加強版」或「高品質」韓文語音，發音示範會更自然。")
            }

            Section("韓語語音辨識") {
                LabeledContent("ko-KR 辨識器", value: report.recognizerAvailable ? "可用" : "不可用")
                LabeledContent("裝置端辨識", value: report.onDeviceRecognition ? "支援" : "不支援（需連網）")
                LabeledContent("授權狀態", value: report.speechAuthorization)
            }

            Section("課程八階段") {
                ForEach(CurriculumStage.allCases) { stage in
                    LabeledContent("第 \(stage.rawValue) 階段", value: stage.title)
                }
            }
        }
        .navigationTitle("系統自檢")
        .task {
            report = SystemCheckReport.collect()
        }
    }

    private func speakSample() {
        let utterance = AVSpeechUtterance(string: "저는 커피를 마셔요.")
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }
}

struct SystemCheckReport {
    struct Voice: Identifiable {
        let id: String
        let name: String
        let quality: String
    }

    var koreanVoices: [Voice]
    var recognizerAvailable: Bool
    var onDeviceRecognition: Bool
    var speechAuthorization: String

    static let empty = SystemCheckReport(
        koreanVoices: [],
        recognizerAvailable: false,
        onDeviceRecognition: false,
        speechAuthorization: "檢查中…"
    )

    @MainActor
    static func collect() -> SystemCheckReport {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "ko-KR" }
            .map { Voice(id: $0.identifier, name: $0.name, quality: qualityLabel($0.quality)) }

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))

        return SystemCheckReport(
            koreanVoices: voices,
            recognizerAvailable: recognizer?.isAvailable ?? false,
            onDeviceRecognition: recognizer?.supportsOnDeviceRecognition ?? false,
            speechAuthorization: authorizationLabel(SFSpeechRecognizer.authorizationStatus())
        )
    }

    private static func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .default: "標準"
        case .enhanced: "加強版"
        case .premium: "高品質"
        @unknown default: "未知"
        }
    }

    private static func authorizationLabel(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "尚未詢問"
        case .denied: "已拒絕"
        case .restricted: "受限制"
        case .authorized: "已授權"
        @unknown default: "未知"
        }
    }
}

#Preview {
    NavigationStack {
        SystemCheckView()
    }
}
