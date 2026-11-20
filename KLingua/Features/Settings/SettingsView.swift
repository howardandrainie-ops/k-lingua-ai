import SwiftUI
import KLinguaCore

struct SettingsView: View {
    @Environment(StudyStore.self) private var store
    @State private var confirmRetake = false

    private let minuteOptions = [10, 15, 20, 30, 45, 60, 90]

    private var permissionText: String {
        switch SpeechInput.shared.permission {
        case .granted: "已允許"
        case .denied: "已拒絕"
        case .notDetermined: "尚未詢問"
        case .unavailable: "裝置不支援"
        }
    }

    var body: some View {
        let _ = store.revision
        let profile = store.profile()
        Form {
            Section {
                Picker("每日練習時間", selection: Binding(get: { profile.dailyMinutes }, set: { store.setDailyMinutes($0) })) {
                    ForEach(minuteOptions, id: \.self) { Text("\($0) 分鐘").tag($0) }
                }
                Toggle("顯示羅馬拼音", isOn: Binding(get: { profile.showRomanization }, set: { store.setShowRomanization($0) }))
            } header: {
                Text("學習")
            } footer: {
                Text("每日課表依這個時間自動調整；時間短時優先保留 SRS 複習、句型練習與新單字。羅馬拼音只建議初期使用。")
            }

            Section {
                Toggle("口說題預設用語音作答", isOn: Binding(get: { profile.preferSpeechInput }, set: { store.setPreferSpeechInput($0) }))
                LabeledContent("麥克風與語音辨識權限", value: permissionText)
                if SpeechInput.shared.permission == .denied {
                    Button("到「設定」開啟權限") { openAppSettings() }
                } else if SpeechInput.shared.permission == .notDetermined {
                    Button("允許使用麥克風與語音辨識") { Task { await SpeechInput.shared.requestPermissions() } }
                }
                LabeledContent("辨識方式", value: SpeechInput.shared.supportsOnDevice ? "裝置端（不上傳）" : "Apple 伺服器（需網路）")
            } header: {
                Text("語音")
            } footer: {
                Text("發音回饋是「語音辨識比對」：只能知道辨識器把你的聲音聽成什麼字，不是發音評分。錄音只存在這台裝置，最多保留最近 200 個。")
            }

            Section("能力診斷") {
                if let date = profile.diagnosticCompletedAt {
                    LabeledContent("上次診斷", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                Button("重新做診斷測驗") { confirmRetake = true }
            }

            Section("紀錄") {
                NavigationLink("錯誤本") { MistakesView() }
            }

            Section {
                LabeledContent("AI 服務", value: "未設定")
                Text("AI 對話、作文批改與 API Key 設定在第四階段加入。API Key 只會存在 iOS 鑰匙圈（Keychain），不會寫進程式碼或檔案。沒有 API Key 時，課程、單字卡、SRS 與離線練習都能正常使用。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("AI 與 API")
            }

            Section("裝置") {
                NavigationLink("系統自檢（語音與語音辨識）") { SystemCheckView() }
            }

            Section("關於") {
                LabeledContent("核心版本", value: KLinguaCoreInfo.version)
                LabeledContent("已開放單元", value: "\(store.library.units.filter(\.available).count) / \(store.library.units.count)")
                LabeledContent("課程／單字", value: "\(store.availableLessons.count) 課／\(store.availableLessons.flatMap(\.vocabulary).count) 個")
            }
        }
        .navigationTitle("設定")
        .confirmationDialog("重新做診斷測驗？", isPresented: $confirmRetake, titleVisibility: .visible) {
            Button("開始") { store.restartDiagnostic() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("目前的學習紀錄都會保留，測驗結果會重新決定目前課程。")
        }
    }
}
