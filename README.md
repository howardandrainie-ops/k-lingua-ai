# K-LINGUA AI — 個人化韓語特訓系統（iOS）

原生 iOS App（Swift 6 / SwiftUI / SwiftData），以 FSI Pattern Drill、五格 SRS、Minimal Pairs 與 AI 情境對話為核心。

> **目前進度：第五階段（整合測試）完成。** App 已在 iOS 模擬器上由自動化 UI 測試實際操作通過；語音、麥克風與 AI 真實連線仍需在 iPhone 上用你的 API Key 測試。詳見 [Docs/STAGE5_TEST_REPORT.md](Docs/STAGE5_TEST_REPORT.md)。

## 第二階段已完成的畫面

| 畫面 | 內容 |
|---|---|
| 能力診斷（首次啟動） | 7 部分 33 題、計時、依結果決定起始課程並跳過已會單元 |
| 首頁 | 今日進度、目前課程、到期複習、錯誤數、8 項能力分數（少於 5 題顯示「資料不足」） |
| 今日訓練 | 依可用時間、到期量、錯誤數與弱項自動生成；完成項目打勾 |
| 課程 | 12 單元（第 1 單元已開放，其餘標示「尚未開放」）；每課含目標、單字、發音、文法、例句、聽力、Pattern Drill、離線情境對話、單字測驗、課後測驗與完成條件 |
| Pattern Drill | 替換／轉換／問答／自由造句；思考時間隨流暢度從 5–8 秒縮短到 3 秒；助詞與拼字錯誤分類說明 |
| SRS 複習 | 單字四面向分開出題（中文理解、韓文辨識、聽力辨識、口語輸出）；五格分布 |
| 單字庫 | 搜尋、頻率分級篩選、每個面向的記憶狀態 |
| 聽音辨識 | 最小對立音、聽音選字（只用 iOS 合成語音） |
| 當日測驗、錯誤本、設定 | 每日時間、羅馬拼音、重新診斷、系統自檢 |

## 第三階段：語音

| 功能 | 內容 |
|---|---|
| 語音作答 | Pattern Drill、診斷與課後測驗的口說題、SRS 口語輸出面向；隨時可改用鍵盤 |
| 思考時間 | 以音量偵測「開始說話」的時間點（不依賴辨識結果），說完 1.2 秒靜音自動停止 |
| 發音練習 | 示範音、最小對立音、句子跟讀；錄音後顯示辨識結果、逐音節差異與具體提示（平音／激音／緊音、收音、ㅓ/ㅗ…），可重播自己的錄音對照 |
| 快速反應 | 看中文，3 秒內開口說出韓語 |
| 隱私 | 裝置支援時強制使用裝置端辨識；錄音只存在本機，保留最近 200 個 |

**發音回饋的限制**：這是「語音辨識比對」，不是發音評分。iOS 只告訴我們辨識器把聲音聽成什麼字，無法量測語調、音長、送氣強度；辨識器也會自動修正成常用詞，發音不準仍可能被辨識正確。App 不顯示任何「發音分數」，只顯示「語音辨識吻合度」並附上這段說明。ㅐ／ㅔ 在現代首爾口語幾乎同音，這類差異會註明不一定是使用者的錯。

**已知限制（誠實標示）**
- 自由造句離線只能比對參考答案，不相符時不計分。
- 雷達圖、週報、AI 設定頁屬於後續階段。

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
├── KLinguaTests/               App 整合測試（swift-testing）
├── KLinguaUITests/             模擬器 UI 測試（XCUITest）
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
| KLinguaCore 單元測試（88 項） | ✅ CI 上 `swift test` |
| App 整合測試（15 項，SwiftData + 教材 + 鑰匙圈） | ✅ CI 上模擬器 `xcodebuild test` |
| UI 端對端測試（4 個流程，含截圖） | ✅ CI 上模擬器 XCUITest |
| iOS App 編譯（模擬器 + 實機，未簽章） | ✅ CI 上 `xcodebuild` |
| iPhone 實機操作 | ⏳ 未測試（模擬器已通過；實機需要 Mac 與 Apple ID 安裝） |
| 麥克風、語音辨識、錄音 | ⏳ 未測試（模擬器沒有真實麥克風，必須在 iPhone 上測） |
| AI 實際連線（Claude / OpenAI / Gemini） | ⏳ 未測試（請求格式與回應解析有單元測試；真實連線需要你的 API Key，用設定頁的「測試連線」確認） |

## API 設定（第四階段）

AI 為選用功能。沒有 API Key 時，課程、單字卡、SRS、發音、聽力與離線情境對話都能正常使用；每日課表會自動把「AI 對話」時間改成離線情境練習。

1. App →「設定」→「AI 服務」。
2. 選擇 Claude、OpenAI 或 Gemini，按「取得 API Key」到服務商網站建立金鑰。
3. 貼上金鑰，按「儲存並測試連線」。
4. 首頁「練習中心」→「AI 情境對話」，從 15 個場景中選一個開始。

| 服務 | 預設模型 | 端點 |
|---|---|---|
| Claude | `claude-opus-5-5`（effort `low`，伺服器端誤拒備援） | Messages API，`anthropic-version: 2026-10-21` |
| OpenAI | `gpt-5-mini` | Chat Completions，JSON 模式 |
| Gemini | `gemini-2.5-flash` | generateContent，金鑰放在標頭、不放網址 |

OpenAI 與 Gemini 的預設模型名稱可能已更新，若測試連線顯示找不到模型，請在設定頁改成服務商目前的模型名稱。

**安全與隱私**
- API Key 只存在這台 iPhone 的鑰匙圈（`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`），不同步 iCloud，不寫入資料庫、檔案或原始碼。
- 傳送給 AI 的只有：情境設定、你在對話中的韓語句子、對話紀錄、你學過的單字清單。
- AI 的修正會加入錯誤本，並計入「口說反應」能力（來源標示為 AI 對話）；畫面上註明 AI 可能出錯。

**15 個情境**：正式語體（初次見面、飯店入住、工作面試）、日常禮貌語體（咖啡廳、便利商店、問路、計程車、餐廳、市場、藥局、電話訂位、同事午餐、地鐵站）、半語（和朋友聊週末、語言交換）。
