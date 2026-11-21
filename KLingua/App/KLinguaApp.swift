import SwiftUI
import KLinguaCore

@main
struct KLinguaApp: App {
    @State private var store: StudyStore?
    @State private var startupError: String?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let launch = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        do {
            let container = try PersistenceSchema.makeContainer(inMemory: launch.uiTesting)
            let library = try ContentLibrary.loadBundled()
            let store = StudyStore(container: container, library: library)
            launch.apply(to: store)
            _store = State(initialValue: store)
        } catch {
            _startupError = State(initialValue: String(describing: error))
        }
    }

    var body: some Scene {
        WindowGroup {
            if let store {
                RootView()
                    .environment(store)
                    // 離開 App 時依最新的學習狀態重排每日提醒（今天練過就不再催促、到期卡數更新）
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .background {
                            Task { await ReminderScheduler.shared.reschedule(using: store) }
                        }
                    }
                    .task { await ReminderScheduler.shared.reschedule(using: store) }
            } else {
                ContentUnavailableView {
                    Label("無法啟動", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(startupError ?? "未知錯誤")
                }
            }
        }
    }
}

/// UI 測試專用的啟動參數。只有測試程式會傳入，正常使用時完全不影響。
struct LaunchOptions {
    /// 使用記憶體資料庫（每次啟動都是全新狀態）、口說題預設用鍵盤（模擬器沒有麥克風）
    var uiTesting: Bool
    /// 直接套用「完全零基礎」的診斷結果，略過診斷畫面，用來測試其他流程
    var placedAsBeginner: Bool

    init(arguments: [String]) {
        uiTesting = arguments.contains("-uiTesting")
        placedAsBeginner = uiTesting && arguments.contains("-uiTestingPlaced")
    }

    @MainActor
    func apply(to store: StudyStore) {
        guard uiTesting else { return }
        ReminderScheduler.shared.disabled = true
        store.setPreferSpeechInput(false)
        if placedAsBeginner {
            let scores = QuizScoring.sectionScores(store.library.diagnostic, correctIDs: [])
            store.applyPlacement(PlacementEngine.place(scores), sectionScores: scores)
        }
    }
}
