# 第一階段報告：架構與環境確認

日期：2026-11-20

## 1. 開發環境檢查結果

| 項目 | 結果 |
|---|---|
| 作業系統 | Windows 11 Home（10.0.26200），Intel i5-14400F，16 GB RAM |
| Xcode / xcodebuild | ❌ 無（Windows 無法安裝） |
| Swift 工具鏈 | ❌ 未安裝 |
| WSL | 有 wsl.exe，但未安裝任何 Linux 發行版 |
| XcodeGen | ❌ 無 |
| Python / Node / Git | ✅ 可用 |

**結論：此環境無法編譯 iOS App，也無法執行 iOS 模擬器。** 我不會宣稱任何 Swift 程式碼已編譯通過。

## 2. 建置方式決策

| 決策 | 選擇 | 理由 |
|---|---|---|
| 專案格式 | 手寫 Xcode 16 `objectVersion 77` 專案，使用資料夾同步群組 | 檔案自動納入，pbxproj 只有 18 個物件，手寫風險最低 |
| 備援 | `project.yml`（XcodeGen） | 若手寫專案檔被 Xcode 拒絕，一行指令重新產生 |
| 最低 iOS 版本 | **iOS 17.0** | SwiftData、`@Observable` 需要 iOS 17；涵蓋 iPhone XS / XR 以後機型 |
| 語言模式 | Swift 6（嚴格並行檢查） | 依規格要求 |
| 架構 | App target（UI + Apple 框架）＋ 本機 Swift Package `KLinguaCore`（純邏輯） | SRS、課程引擎、Drill 評分、能力評估不依賴 iOS，可在任何平台跑單元測試 |
| 第三方依賴 | **無** | 全部使用 Apple 原生框架；AI 以 URLSession 直接呼叫 REST API |
| 資料儲存 | SwiftData（本機），預留 CloudKit 同步 | iOS 17 原生、ModelContainer 可日後開啟 CloudKit |
| Info.plist | 由建置設定產生 | 已設定麥克風、語音辨識權限說明（繁體中文） |

## 3. 必要框架

SwiftUI、SwiftData、AVFoundation（TTS、錄音、播放）、Speech（ko-KR 語音辨識）、Security（Keychain）、UserNotifications、URLSession、Charts（雷達圖／趨勢圖）。

## 4. 已建立的檔案

- `KLingua.xcodeproj/project.pbxproj`、`project.xcworkspace`
- `project.yml`
- `KLingua/App/KLinguaApp.swift`、`RootView.swift`
- `KLingua/Features/SystemCheck/SystemCheckView.swift` — **實機環境自檢頁**：列出裝置上的 ko-KR 語音與品質、播放測試句、ko-KR 語音辨識器是否可用、是否支援裝置端辨識、授權狀態。用途是在第三階段前確認你的 iPhone 語音能力。
- `KLingua/Resources/Assets.xcassets`（AppIcon 尚無圖片，建置會有警告但不影響執行）
- `Packages/KLinguaCore`：
  - `LeitnerBox`：五格與預設間隔 1/3/7/30/90 天
  - `SkillDimension`：8 個能力維度（診斷、雷達圖、課程生成共用）
  - `CardFacet`：每張卡追蹤 中文理解／韓文辨識／聽力辨識／口語輸出
  - `VocabularyTier`：S/A/B/C 頻率分級
  - `SpeechLevel`：합쇼체／해요체／반말
  - `CurriculumStage`：八階段課程
  - `DomainTests`：上述型別的單元測試（swift-testing）
- `Tools/validate_project.py`：結構檢查（已通過）
- 其餘 `Features/*`、`Services/*`、`KLinguaCore/Sources/KLinguaCore/*` 子資料夾目前為空，依階段填入。

## 5. 已知限制（誠實標示）

1. **未編譯。** 程式碼依 Swift 6 / iOS 17 SDK 撰寫並人工審閱，但第一次在 Xcode 建置可能出現小錯誤，需要你回報錯誤訊息讓我修正。
2. **發音評分精度。** Apple Speech 框架只做語音轉文字，可得到辨識文字與信心值，**不能**可靠評估子音送氣（가/카）、緊音（달/딸）等細節。第三階段會設計 `PronunciationAssessor` 可替換介面，內建實作只提供「辨識文字比對 + 信心值」並明確標示不確定；高精度評分需接外部服務（如 Azure Pronunciation Assessment，支援 ko-KR）。
3. **TTS 品質** 取決於 iPhone 上下載的韓文語音，自檢頁會顯示。

## 6. 下一階段（第二階段：核心系統）的依賴與計畫

- SwiftData 模型：UserProfile、LearningProgress、Course、Lesson、Vocabulary、Grammar、ExampleSentence、Flashcard、ReviewSchedule、MistakeRecord、DailyLearningRecord 等
- KLinguaCore：SRS 排程器（正確率＋反應時間＋錯誤類型）、課程引擎、每日 60/20 分鐘排程演算法，全部附單元測試
- 內建教材：單元 01（韓文字母及拼讀）、02（發音及收音）完整內容，以 JSON 形式放在套件內
- UI：TabView、首頁 Dashboard、今日訓練、單字卡、SRS 管理

**建議**：在 Windows 安裝 Swift 工具鏈（`winget install Swift.Toolchain`，需 Visual Studio Build Tools），我就能在第二階段實際編譯並執行 KLinguaCore 的單元測試，讓 SRS 與課程引擎的邏輯有真正的測試佐證。UI 部分仍須在 Mac 上驗證。
