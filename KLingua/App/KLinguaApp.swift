import SwiftUI
import KLinguaCore

@main
struct KLinguaApp: App {
    @State private var store: StudyStore?
    @State private var startupError: String?

    init() {
        do {
            let container = try PersistenceSchema.makeContainer()
            let library = try ContentLibrary.loadBundled()
            _store = State(initialValue: StudyStore(container: container, library: library))
        } catch {
            _startupError = State(initialValue: String(describing: error))
        }
    }

    var body: some Scene {
        WindowGroup {
            if let store {
                RootView().environment(store)
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
