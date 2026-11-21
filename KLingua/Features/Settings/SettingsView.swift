import SwiftUI
import KLinguaCore

struct SettingsView: View {
    @Environment(StudyStore.self) private var store
    @State private var confirmRetake = false
    @State private var permissionAlert = false
    private var reminders: ReminderScheduler { ReminderScheduler.shared }

    private static func date(for time: ReminderTime) -> Date {
        Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
    }

    private func reschedule() {
        Task { await reminders.reschedule(using: store) }
    }

    /// 開啟提醒時才詢問通知權限；被拒絕就不開啟，並提示到系統設定。
    private func setReminder(_ slot: ReminderSlot, on: Bool) {
        guard on else {
            store.setReminder(slot, time: nil)
            reschedule()
            return
        }
        Task {
            if reminders.permission != .granted {
                let granted = await reminders.requestPermission()
                guard granted else {
                    permissionAlert = true
                    return
                }
            }
            store.setReminder(slot, time: slot == .morning ? .defaultMorning : .defaultEvening)
            await reminders.reschedule(using: store)
        }
    }

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

            Section {
                ForEach(ReminderSlot.allCases, id: \.self) { slot in
                    Toggle(slot.title, isOn: Binding(get: { store.reminderTime(slot) != nil },
                                                    set: { on in setReminder(slot, on: on) }))
                    if let time = store.reminderTime(slot) {
                        DatePicker("時間", selection: Binding(get: { Self.date(for: time) },
                                                             set: { store.setReminder(slot, time: ReminderTime($0)); reschedule() }),
                                   displayedComponents: .hourAndMinute)
                    }
                }
                if reminders.permission == .denied {
                    Text("通知權限已關閉，提醒不會出現。").foregroundStyle(.secondary)
                    Button("到「設定」開啟通知") { openAppSettings() }
                } else if reminders.scheduledCount > 0 {
                    LabeledContent("已排定", value: "未來 7 天共 \(reminders.scheduledCount) 則")
                }
            } header: {
                Text("每日提醒")
            } footer: {
                Text("早上提醒今天的課程與到期的單字卡；晚上若今天還沒練習、或還有到期的卡片才會提醒。今天已經練習過就不會再催你。通知只在這台 iPhone 上排程，不經過網路。")
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
                NavigationLink {
                    AISettingsView()
                } label: {
                    LabeledContent("AI 服務", value: store.aiAvailable ? "\(store.aiProvider?.title ?? "")" : "未設定")
                }
            } header: {
                Text("AI 與 API")
            } footer: {
                Text("API Key 只存在這台 iPhone 的鑰匙圈（Keychain）。沒有設定時，課程、單字卡、SRS、發音與離線練習都能正常使用。")
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
        .task { await reminders.refreshPermission() }
        .alert("無法開啟提醒", isPresented: $permissionAlert) {
            Button("到「設定」開啟") { openAppSettings() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("需要允許 K-LINGUA 傳送通知，才能收到每日提醒。")
        }
        .confirmationDialog("重新做診斷測驗？", isPresented: $confirmRetake, titleVisibility: .visible) {
            Button("開始") { store.restartDiagnostic() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("目前的學習紀錄都會保留，測驗結果會重新決定目前課程。")
        }
    }
}
