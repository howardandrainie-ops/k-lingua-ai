# 安裝指南：把 K-LINGUA 裝到你的 iPhone

這個 App 沒有上架 App Store，要用 Xcode 自己安裝。**一定需要一台 Mac**；Windows 不能安裝 iOS App。

> 沒有 Mac？改用**網頁版**：用 Safari 打開 https://howardandrainie-ops.github.io/k-lingua-ai/ 加入主畫面即可，不需要簽章、不會過期。見 [WEB_APP.md](WEB_APP.md)。

## 需要準備

| 項目 | 需求 |
|---|---|
| Mac | macOS 14.5 以上（Xcode 16 的需求） |
| Xcode | 16 以上，從 Mac App Store 免費下載（約 10 GB 以上空間） |
| iPhone | iOS 17 以上 |
| Apple ID | 免費帳號即可；付費開發者帳號（每年 US$99）可以免去每 7 天重裝 |
| 傳輸線 | 第一次安裝建議用 USB 線連接 |

## 第一步：取得程式碼

任選一種：

- **用 Git**（Mac 終端機）：
  ```
  git clone https://github.com/howardandrainie-ops/k-lingua-ai.git
  ```
- **下載 ZIP**：在 GitHub 網頁按 **Code › Download ZIP**，解壓縮。

## 第二步：開啟專案並設定簽章

1. 雙擊 `KLingua.xcodeproj`。第一次開啟時 Xcode 會解析本地套件 `KLinguaCore`，等上方進度條跑完。
2. Xcode 選單 **Settings › Accounts**，按 **+** 登入你的 Apple ID。
3. 左側點最上面的 **KLingua** 專案 → 中間 TARGETS 選 **KLingua** → **Signing & Capabilities** 分頁：
   - 勾選 **Automatically manage signing**。
   - **Team**：選你的 Apple ID（顯示為「你的名字 (Personal Team)」）。
   - **Bundle Identifier**：把 `com.personal.klingua` 改成獨一無二的值，例如 `com.yourname.klingua`。免費帳號不能使用別人用過的 ID。
4. 兩個測試 target（KLinguaTests、KLinguaUITests）只有要在 Mac 上跑測試時才需要設定，安裝到手機不需要。

## 第三步：安裝到 iPhone

1. 用 USB 線連接 iPhone，iPhone 上選「信任這部電腦」。
2. iPhone：**設定 › 隱私權與安全性 › 開發者模式** → 開啟，依提示重新開機。（要先連過 Xcode，這個選項才會出現。）
3. Xcode 上方的裝置選單選你的 iPhone，按 **⌘R**（或左上角 ▶︎）。
4. 第一次會出現「無法驗證開發者」：iPhone 到 **設定 › 一般 › VPN 與裝置管理**，點你的 Apple ID → **信任**。
5. 再按一次 ⌘R，或直接點手機上的 K-LINGUA 圖示。

## 第四步：第一次開啟要做的事

1. **能力診斷**：33 題，約 10 分鐘。全部不會也沒關係，會從第 1 單元開始。
2. **麥克風與語音辨識權限**：第一次按錄音時 iOS 會詢問，請選「允許」。拒絕之後只能到 iPhone 的 **設定 › K-LINGUA** 重新開啟；App 內也有按鈕直接前往。
3. **下載高品質韓文語音**（強烈建議）：iPhone **設定 › 輔助使用 › 朗讀內容 › 聲音 › 韓文**，下載「加強版」或「高品質」語音。內建的精簡語音聽起來比較生硬。
4. **系統自檢**：App 的 **設定 › 系統自檢** 會列出已安裝的韓文語音、韓語辨識器是否可用、是否支援裝置端辨識（不支援時錄音需要連網）。
5. **每日提醒**（選用）：App 的 **設定 › 每日提醒** 開啟早上或晚上提醒，第一次開啟時 iOS 會詢問通知權限，請選「允許」。
6. **AI 對話**（選用）：見 [API_SETUP.md](API_SETUP.md)。

## 資料會不會不見？

- 學習紀錄存在 iPhone 本機的資料庫（SwiftData）。用 Xcode **重新安裝或更新 App 不會清除資料**。
- **刪除 App 會清除所有學習紀錄**。目前沒有 iCloud 同步或匯出功能。
- 免費 Apple ID 安裝的 App 7 天後會無法開啟；接上 Mac 再按一次 ⌘R 重新簽署即可，資料還在。

## 常見問題

| 狀況 | 解決方式 |
|---|---|
| Xcode 說專案檔損毀或無法開啟 | `project.pbxproj` 是手寫的（雖然 CI 上的 Xcode 16.4 能正常開啟與編譯）。備援方式：`brew install xcodegen`，在專案資料夾執行 `xcodegen generate`，會依 `project.yml` 重新產生專案檔 |
| 「Failed to register bundle identifier」 | Bundle Identifier 已被別人使用，換一個 |
| 「Untrusted Developer」 | 見第三步第 4 點 |
| 找不到「開發者模式」 | 先用 USB 連上 Xcode 並選取這支 iPhone，選項才會出現 |
| 「Could not launch… device is locked」 | 解鎖 iPhone 再試一次 |
| 7 天後打不開 | 免費帳號的限制，重新用 Xcode 安裝 |
| 錄音按鈕沒有反應或顯示權限錯誤 | iPhone **設定 › K-LINGUA** 開啟麥克風與語音辨識 |
| 示範發音很機械 | 下載高品質韓文語音（第四步第 3 點） |

## 在 Mac 上跑測試（選用）

```
cd Packages/KLinguaCore && swift test
xcodebuild test -project KLingua.xcodeproj -scheme KLingua -destination 'platform=iOS Simulator,name=iPhone 16'
```

模擬器名稱依你安裝的 Xcode 而定，可用 `xcrun simctl list devices available` 查看。
