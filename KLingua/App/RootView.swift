import SwiftUI

/// 第一階段的根畫面只有「系統自檢」，用於在實機上確認韓語 TTS 與語音辨識是否可用。
/// 第二階段起改為 TabView（首頁 / 今日訓練 / 課程 / 單字庫 / 設定）。
struct RootView: View {
    var body: some View {
        NavigationStack {
            SystemCheckView()
        }
    }
}

#Preview {
    RootView()
}
