# AI 服務設定指南

AI 只用在「AI 情境對話」。**不設定也能使用 App 的其他所有功能**：課程、Pattern Drill、單字卡、SRS、發音、聽力、離線情境練習、報告。沒有 API Key 時，每日課表會自動把 AI 對話的時間改排成離線情境練習。

## 選哪一家？

三家都可以，App 內隨時能切換。選你已經有帳號的那一家即可。

| 服務 | App 內預設模型 | 取得金鑰 | 金鑰開頭 |
|---|---|---|---|
| Claude（Anthropic） | `claude-opus-5-5` | https://platform.claude.com/settings/keys | `sk-ant-` |
| OpenAI | `gpt-5-mini` | https://platform.openai.com/api-keys | `sk-` |
| Gemini（Google） | `gemini-2.5-flash` | https://aistudio.google.com/apikey | `AIza` |

三家都是**依用量付費**，費用由你的帳戶支付，App 不經過任何中間伺服器。請在服務商的後台設定每月用量上限。

## 設定步驟

1. 到上表的網址登入並建立 API Key。多數服務需要先綁定付款方式或儲值。
2. 複製金鑰。金鑰通常只顯示一次，請自己妥善保存。
3. iPhone 開啟 K-LINGUA → **設定 › AI 服務**。
4. **服務**：選 Claude、OpenAI 或 Gemini。
5. **模型**：通常不用改；要恢復時按「使用預設」。
6. **API Key**：貼上金鑰。
7. 按 **儲存並測試連線**。App 會送出一個很短的測試請求，成功或失敗都會顯示結果。
8. 回首頁 → **練習中心 › AI 情境對話**，從 15 個場景選一個開始。

## 測試連線失敗時

App 會用中文說明原因：

| 訊息類型 | 可能原因 | 處理方式 |
|---|---|---|
| 金鑰無效 | 複製不完整、金鑰已刪除、選錯服務 | 重新複製；確認服務選項和金鑰對應 |
| 找不到模型 | 服務商已更名或下架這個模型 | 到服務商文件查目前的模型名稱，填入「模型」欄位 |
| 額度不足／超過速率 | 帳戶沒有餘額，或短時間內請求太多 | 到後台儲值或稍後再試 |
| 網路錯誤 | iPhone 沒有網路 | 檢查網路 |
| 服務暫時無法使用 | 服務商端故障 | 稍後再試 |

> **注意**：OpenAI 與 Gemini 的預設模型名稱是開發時設定的，目前**尚未用真實金鑰測試過**。如果出現「找不到模型」，請改成服務商目前提供的模型。

## 安全性

- 金鑰只存在**這台 iPhone 的鑰匙圈（Keychain）**，設定為「裝置解鎖時才能讀取、不同步到其他裝置」。
- 金鑰**不會**寫入 App 的資料庫、檔案、iCloud 或原始碼。整合測試會檢查資料庫裡沒有金鑰；推送到 GitHub 前，結構檢查工具也會掃描原始碼，看有沒有誤放的金鑰。
- 設定頁只顯示金鑰的最後 4 碼（例如 `••••9xQ2`）。按 **刪除這個金鑰** 會從鑰匙圈移除。
- 刪除 App 時，iOS 不一定會清除鑰匙圈資料。如果要確實移除，請先在 App 內刪除金鑰，或到服務商後台撤銷金鑰。

## 會傳送哪些內容給 AI

只會傳送：

- 情境設定，例如「咖啡廳點餐，禮貌語體」。
- 你在對話中說的或輸入的韓語句子，以及這次的對話紀錄。
- 你學過的單字清單，用來控制 AI 用字的難度。

不會傳送姓名、帳號、錄音檔或其他個人資料。語音是先在 iPhone 上轉成文字，只傳送文字。

## AI 回覆的內容

每次回覆包含：

- 韓語回應與中文翻譯。
- 你上一句的修正（沒有錯就不顯示）：原句、修正後句子、中文說明。
- 需要時附上中文提示，例如語體提醒、你用中文問「這個怎麼說」時的教學、任務完成時的總評。

修正會自動加入**錯誤本**，並計入「口說反應」能力，來源標示為「AI 對話」。只差在空格的修正會被忽略。

AI 可能會出錯，畫面上有提醒。文法有疑問時，以課程內容為準。

## 技術細節（給開發者）

| 服務 | 端點 | 認證 | 備註 |
|---|---|---|---|
| Claude | `POST https://api.anthropic.com/v1/messages` | `x-api-key` 標頭、`anthropic-version: 2026-10-21` | `output_config.effort: "low"`；`anthropic-beta: server-side-fallback-2026-07-01` 搭配 `fallbacks: "default"`，伺服器端誤拒時自動改用備援模型；處理 `stop_reason: "refusal"` |
| OpenAI | `POST https://api.openai.com/v1/chat/completions` | `Authorization: Bearer` | `max_completion_tokens`、`response_format: json_object` |
| Gemini | `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent` | `x-goog-api-key` 標頭（不放在網址） | `responseMimeType: application/json` |

- 程式碼：`Packages/KLinguaCore/Sources/KLinguaCore/AI/`。`AIService.swift` 負責請求格式與錯誤分類；`Coach.swift` 是情境、系統提示和回覆解析。
- 要新增服務商：在 `AIProvider` 加一個 case，在 `ProviderAPI` 實作 `makeRequest` 與 `parseResponse`，再補上單元測試。
- 請求格式與回應解析有單元測試，用攔截網路的 `StubURLProtocol`，不會真的連線。
