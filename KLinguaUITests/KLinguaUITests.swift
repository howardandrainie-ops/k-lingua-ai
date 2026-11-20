import XCTest

/// 在 iOS 模擬器上實際操作 App 的端對端測試。
/// 啟動參數 -uiTesting：記憶體資料庫（每次全新）、口說題用鍵盤（模擬器沒有麥克風）。
@MainActor
final class KLinguaUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + extra
        app.launch()
        return app
    }

    private func find(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// 在清單中往下捲動直到找到含有文字的元素
    @discardableResult
    private func scrollTo(_ app: XCUIApplication, _ text: String, maxSwipes: Int = 8) -> XCUIElement {
        let e = find(app, text)
        var swipes = 0
        while !e.exists && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return e
    }

    private func tapText(_ app: XCUIApplication, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let e = scrollTo(app, text)
        XCTAssertTrue(e.waitForExistence(timeout: 10), "找不到「\(text)」", file: file, line: line)
        e.tap()
    }

    private func screenshot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    // MARK: - 診斷測驗

    func testDiagnosticFlowPlacesBeginnerAtUnitOne() {
        let app = launch()
        XCTAssertTrue(find(app, "開始診斷測驗").waitForExistence(timeout: 15))
        screenshot("01-診斷說明")
        tapText(app, "開始診斷測驗")

        let dontKnow = app.buttons["不知道"]
        for i in 1...33 {
            XCTAssertTrue(dontKnow.waitForExistence(timeout: 10), "第 \(i) 題找不到「不知道」")
            if i == 1 || i == 31 { screenshot(String(format: "02-診斷第%02d題", i)) }
            dontKnow.tap()
        }

        XCTAssertTrue(find(app, "第 1 單元").waitForExistence(timeout: 10))
        screenshot("03-診斷結果")
        tapText(app, "依這個結果開始學習")
        XCTAssertTrue(app.tabBars.buttons["首頁"].waitForExistence(timeout: 10))
        XCTAssertTrue(find(app, "基本母音").waitForExistence(timeout: 5), "首頁應顯示第一課")
        screenshot("04-首頁")
    }

    // MARK: - 課程與 Pattern Drill

    func testDrillWithKeyboardAnswerIsGradedAndSaved() {
        let app = launch(["-uiTestingPlaced"])
        app.tabBars.buttons["課程"].tap()
        screenshot("05-課程列表")
        tapText(app, "基本母音")
        screenshot("06-課程頁")
        tapText(app, "句型練習 Pattern Drill")
        tapText(app, "替換練習")

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        screenshot("07-Drill題目")
        field.tap()
        field.typeText("우유예요.")
        app.buttons["送出"].tap()
        XCTAssertTrue(find(app, "正確").waitForExistence(timeout: 5), "正確答案應判為正確")
        screenshot("08-Drill回饋")
        app.buttons["下一題"].tap()

        // 其餘 4 題按「不會」
        for i in 2...5 {
            let giveUp = app.buttons["不會"]
            XCTAssertTrue(giveUp.waitForExistence(timeout: 5), "第 \(i) 題找不到「不會」")
            giveUp.tap()
            let next = app.buttons[i < 5 ? "下一題" : "完成"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }
        XCTAssertTrue(find(app, "答對 1 / 5").waitForExistence(timeout: 5))
        screenshot("09-Drill結果")
        app.buttons["返回"].tap()
        XCTAssertTrue(find(app, "本課句型練習正確率").waitForExistence(timeout: 5), "作答應寫入課程進度")
        XCTAssertTrue(find(app, "20%").exists)
    }

    // MARK: - 單字測驗 → 單字卡 → SRS

    func testVocabularyQuizCreatesCardsForReview() {
        let app = launch(["-uiTestingPlaced"])
        app.tabBars.buttons["課程"].tap()
        tapText(app, "基本母音")
        tapText(app, "單字記憶測驗")
        for i in 1...6 {
            let dontKnow = app.buttons["不知道"]
            XCTAssertTrue(dontKnow.waitForExistence(timeout: 10), "第 \(i) 題找不到「不知道」")
            if i == 1 { screenshot("10-單字測驗") }
            dontKnow.tap()
            let next = app.buttons[i < 6 ? "下一題" : "完成"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }
        XCTAssertTrue(find(app, "已把本課 6 個新單字加入單字卡").waitForExistence(timeout: 5))

        app.tabBars.buttons["單字庫"].tap()
        XCTAssertTrue(find(app, "已加入單字卡 6 個").waitForExistence(timeout: 5))
        screenshot("11-單字庫")
        tapText(app, "SRS 複習中心")
        tapText(app, "開始複習（24 個到期）")
        XCTAssertTrue(app.navigationBars["複習 1 / 24"].waitForExistence(timeout: 5))
        screenshot("12-SRS複習")
    }

    // MARK: - 各分頁與沒有 AI 時的行為

    func testTabsReportsAndOfflineAI() {
        let app = launch(["-uiTestingPlaced"])

        app.tabBars.buttons["今日訓練"].tap()
        XCTAssertTrue(find(app, "已完成").waitForExistence(timeout: 5))
        XCTAssertTrue(scrollTo(app, "情境角色扮演").exists, "沒有 AI 時應排入離線情境練習")
        XCTAssertFalse(find(app, "AI 口語對話").exists, "沒有 API Key 時不應排入 AI 對話")
        screenshot("13-今日訓練")

        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(scrollTo(app, "未設定").exists)
        screenshot("14-設定")

        app.tabBars.buttons["首頁"].tap()
        tapText(app, "能力報告")
        XCTAssertTrue(find(app, "能力雷達圖").waitForExistence(timeout: 5))
        screenshot("15-能力報告")
        app.navigationBars.buttons.firstMatch.tap()

        tapText(app, "AI 情境對話")
        XCTAssertTrue(find(app, "尚未設定 AI 服務").waitForExistence(timeout: 5))
        screenshot("16-情境列表")
    }
}
