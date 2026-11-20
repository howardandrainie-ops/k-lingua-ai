# K-LINGUA AI — 個人化韓語特訓系統（iOS）

原生 iOS App（Swift 6 / SwiftUI / SwiftData），以 FSI Pattern Drill、五格 SRS、Minimal Pairs 與 AI 情境對話為核心。

> **目前進度：第一階段（架構與環境）完成。** 尚未在 Xcode 編譯過，見下方「驗證狀態」。

## 目錄結構

```
k-lingua-ai/
├── KLingua.xcodeproj/          Xcode 16 專案（資料夾同步格式，新增檔案不需改 pbxproj）
├── project.yml                 XcodeGen 備援規格
├── KLingua/                    App target（SwiftUI、Apple 框架相關程式）
│   ├── App/                    @main 進入點、RootView
│   ├── Features/               各頁面：Dashboard、DailyTraining、Diagnostic、Courses、
│   │                           Vocabulary、SRS、Pronunciation、Listening、Conversation、
│   │                           Scenarios、Reports、Settings、SystemCheck
│   ├── Services/               Persistence(SwiftData)、Speech(TTS/STT/錄音)、AI、
│   │                           Notifications、Security(Keychain)
│   ├── DesignSystem/           色彩、字級、共用元件
│   └── Resources/              Assets.xcassets
├── Packages/KLinguaCore/       純邏輯 Swift Package（只依賴 Foundation，可獨立 swift test）
│   ├── Sources/KLinguaCore/    Domain、SRS、Curriculum、Drill、Assessment、Analytics、Content
│   └── Tests/KLinguaCoreTests/
├── Tools/validate_project.py   不需 Xcode 的結構檢查
└── Docs/                       階段報告與架構說明
```

## 在 Mac 上建置與安裝到 iPhone

需求：macOS 14.5 以上、Xcode 16 以上、iPhone 執行 iOS 17 以上、一個 Apple ID（免費帳號即可安裝到自己的手機，7 天需重新簽署）。

1. 將整個 `k-lingua-ai` 資料夾複製到 Mac。
2. 雙擊 `KLingua.xcodeproj` 開啟。
3. 左側點選專案 **KLingua** → Target **KLingua** → **Signing & Capabilities**：
   - Team：選擇你的 Apple ID。
   - Bundle Identifier：改成獨一無二的值，例如 `com.你的名字.klingua`。
4. 用 USB 連接 iPhone，在 iPhone 上開啟「設定 › 隱私權與安全性 › 開發者模式」。
5. Xcode 上方選擇你的 iPhone，按 ⌘R 執行。
6. 第一次安裝後，iPhone「設定 › 一般 › VPN 與裝置管理」信任你的開發者憑證。

### 若 Xcode 無法開啟專案檔

`project.pbxproj` 是在 Windows 上手寫的。若 Xcode 回報專案損毀：

```
brew install xcodegen
cd k-lingua-ai
xcodegen generate
```

### 單獨測試核心邏輯

```
cd Packages/KLinguaCore
swift test
```

## 驗證狀態

每次推送都會由 GitHub Actions（macOS 15、Xcode 16.4）自動編譯與測試，見 `.github/workflows/ios-build.yml`。

| 項目 | 狀態 |
|---|---|
| 專案結構 / pbxproj 引用完整性 / JSON | ✅ `Tools/validate_project.py` |
| KLinguaCore 單元測試（42 項） | ✅ CI 上 `swift test` |
| iOS App 編譯（模擬器 + 實機，未簽章） | ✅ CI 上 `xcodebuild` |
| App 實際操作 / iPhone 實機 | ⏳ 未測試（需要 Mac 或實機） |

## API 設定

第四階段實作。API Key 只會存在 iOS Keychain，不會寫入原始碼或檔案。沒有 API Key 時，課程、單字卡、SRS、預建練習仍可使用。
