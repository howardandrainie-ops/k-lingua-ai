import SwiftUI

/// 首次啟動先做診斷測驗；完成後進入主畫面。
struct RootView: View {
    @Environment(StudyStore.self) private var store

    var body: some View {
        let _ = store.revision
        if store.needsDiagnostic {
            NavigationStack { DiagnosticIntroView() }
        } else {
            MainTabView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("首頁", systemImage: "house") }
            NavigationStack { TodayView() }
                .tabItem { Label("今日訓練", systemImage: "checklist") }
            NavigationStack { CoursesView() }
                .tabItem { Label("課程", systemImage: "book") }
            NavigationStack { VocabularyLibraryView() }
                .tabItem { Label("單字庫", systemImage: "character.book.closed") }
            NavigationStack { SettingsView() }
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}
