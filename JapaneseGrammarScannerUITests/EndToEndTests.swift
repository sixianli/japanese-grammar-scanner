import XCTest

/// 端到端测试：在模拟器上像用户一样点击、跳转、返回，覆盖 App 的主要使用路径。
/// 每次提交都在 CI（iOS Build & Test → e2e）里运行。启动参数 -e2e 会清空本地数据并放入固定的扫描记录和浏览记录。
final class EndToEndTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-e2e", "-demoUnlocked", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(id("home.search").waitForExistence(timeout: 20), "启动后应停在首页")
    }

    // MARK: - 工具

    private func id(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func ids(_ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    private func button(startingWith label: String) -> XCUIElement {
        let b = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 5), "找不到按钮「\(label)」")
        return b
    }

    private func tab(_ title: String) -> XCUIElement {
        app.tabBars.buttons[title].firstMatch
    }

    private func wait(_ element: XCUIElement, _ message: String, timeout: TimeInterval = 15,
                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message, file: file, line: line)
    }

    private func back(file: StaticString = #filePath, line: UInt = #line) {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(button.waitForExistence(timeout: 5), "找不到返回按钮", file: file, line: line)
        button.tap()
    }

    /// 识别结果页出现，并且识别完成（列表里出现语法点）
    private func waitForScanResult(file: StaticString = #filePath, line: UInt = #line) {
        wait(app.navigationBars["识别结果"], "应进入识别结果页", file: file, line: line)
        wait(id("result.grammarRow"), "识别结果页应列出语法点", timeout: 40, file: file, line: line)
    }

    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 12) {
        var n = 0
        while !element.isHittable && n < maxSwipes {
            app.swipeUp()
            n += 1
        }
    }

    // MARK: - 首页

    /// build 12 的 bug：在「全部扫描记录」点一条记录，没有进入识别结果，而是在列表里原地打转
    func testAllScansOpensEveryRecord() {
        id("seeAll.scans").tap()
        wait(app.navigationBars["全部扫描记录"], "应进入全部扫描记录")
        let records = ids("scanRecord")
        wait(records.firstMatch, "应列出扫描记录")
        XCTAssertGreaterThanOrEqual(records.count, 4)

        for index in [0, 1, 3] {
            records.element(boundBy: index).tap()
            waitForScanResult()
            XCTAssertFalse(app.navigationBars["全部扫描记录"].exists, "点了记录后不应停留在全部扫描记录")
            back()
            wait(app.navigationBars["全部扫描记录"], "从识别结果返回应回到全部扫描记录")
        }
        back()
        wait(id("home.search"), "应回到首页")
    }

    func testContinueScanThenGrammarThenHomeTab() {
        id("home.continueScan").tap()
        waitForScanResult()
        id("result.grammarRow").tap()
        wait(id("screen.grammarDetail"), "点识别结果里的语法点应进入讲解页")
        tab("首页").tap()
        wait(id("home.search"), "再次点「首页」应回到首页顶部")
    }

    func testSeeAllRecentAndForgetting() {
        scrollTo(id("seeAll.recent"))
        id("seeAll.recent").tap()
        wait(app.navigationBars["最近查看"], "应进入最近查看")
        id("grammarRow").tap()
        wait(id("screen.grammarDetail"), "最近查看里点语法点应进入讲解页")
        back()
        wait(app.navigationBars["最近查看"], "返回应回到最近查看")
        back()
        wait(id("home.search"), "应回到首页")

        let forgetting = id("seeAll.forgetting")
        if forgetting.waitForExistence(timeout: 3) {
            scrollTo(forgetting)
            forgetting.tap()
            wait(app.navigationBars["快要忘了"], "应进入快要忘了")
            id("grammarRow").tap()
            wait(id("screen.grammarDetail"), "快要忘了里点语法点应进入讲解页")
            back()
            wait(app.navigationBars["快要忘了"], "返回应回到快要忘了")
        }
    }

    func testHomeGrammarRowOpensDetailAndFavorite() {
        scrollTo(id("grammarRow"))
        id("grammarRow").tap()
        wait(id("screen.grammarDetail"), "首页列表点语法点应进入讲解页")
        id("detail.favorite").tap()
        tab("收藏").tap()
        wait(id("favorites.row"), "收藏后应出现在收藏页")
        id("favorites.row").tap()
        wait(id("screen.grammarDetail"), "收藏页点语法点应进入讲解页")
    }

    // MARK: - 扫描

    func testSampleScanResultZoomAndTabs() {
        tab("扫描").tap()
        wait(id("scan.trySample"), "扫描页应有「试试示例」")
        id("scan.trySample").tap()
        waitForScanResult()

        // 放大查看：点图片进入全屏，点关闭回来
        id("result.image").tap()
        wait(id("zoom.close"), "点图片应进入全屏查看")
        id("zoom.close").tap()
        XCTAssertTrue(app.navigationBars["识别结果"].waitForExistence(timeout: 5), "关闭全屏后应回到识别结果")

        id("result.grammarRow").tap()
        wait(id("screen.grammarDetail"), "应进入讲解页")

        // 切到别的标签再切回来，各标签停在各自的位置
        tab("首页").tap()
        wait(id("home.search"), "切到首页标签应显示首页")
        tab("扫描").tap()
        wait(id("screen.grammarDetail"), "切回扫描标签应仍停在讲解页")
        tab("扫描").tap()
        wait(id("scan.trySample"), "再点一次扫描标签应回到扫描首页")
    }

    // MARK: - 搜索

    func testSearchTabFocusesFieldEveryTime() {
        tab("搜索").tap()
        let field = app.searchFields.firstMatch
        wait(field, "搜索页应有搜索框")
        XCTAssertTrue(waitForFocus(field), "点搜索标签后搜索框应获得输入焦点")
        field.typeText("ように")
        wait(id("search.result"), "输入后应有搜索结果")
        id("search.result").tap()
        wait(id("screen.grammarDetail"), "点搜索结果应进入讲解页")

        // 从详情页切走，再点搜索标签：应回到搜索框并获得焦点
        tab("收藏").tap()
        tab("搜索").tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5), "回到搜索标签应显示搜索框")
        XCTAssertTrue(waitForFocus(field), "回到搜索标签后搜索框应获得输入焦点")
        XCTAssertFalse(id("screen.grammarDetail").exists, "回到搜索标签不应停在之前的讲解页")
    }

    func testHomeSearchEntryOpensSearchTab() {
        id("home.search").tap()
        let field = app.searchFields.firstMatch
        wait(field, "首页搜索入口应打开搜索标签")
        XCTAssertTrue(waitForFocus(field), "搜索框应获得输入焦点")
    }

    private func waitForFocus(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (element.value(forKey: "hasKeyboardFocus") as? Bool) == true { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    // MARK: - 语法库

    func testLibraryOpensDetail() {
        tab("语法库").tap()
        wait(id("library.row"), "语法库应列出语法点")
        id("library.row").tap()
        wait(id("screen.grammarDetail"), "语法库点语法点应进入讲解页")
        back()
        wait(id("library.row"), "返回应回到语法库")
    }

    // MARK: - 设置

    func testSettingsSheetAndLanguageSwitch() {
        id("home.settings").tap()
        wait(app.navigationBars["设置"], "应打开设置")
        button(startingWith: "语言").tap()
        wait(app.navigationBars["语言"], "应进入语言页")
        button(startingWith: "English").tap()
        wait(app.navigationBars["Language"], "切换到 English 后界面应立即变成英文")
        button(startingWith: "简体中文").tap()
        wait(app.navigationBars["语言"], "切回简体中文")
        back()
        wait(app.navigationBars["设置"], "应回到设置")
        app.navigationBars["设置"].buttons["完成"].tap()
        wait(id("home.search"), "关闭设置应回到首页")
    }
}
