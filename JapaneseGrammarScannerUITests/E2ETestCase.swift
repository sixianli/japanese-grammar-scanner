import XCTest

/// 端到端测试的公共基类：启动 App（固定数据、简体中文），以及查找元素、等待、返回等工具方法。
class E2ETestCase: XCTestCase {
    var app: XCUIApplication!

    /// 额外的启动参数（例如 -e2eFresh 表示全新安装状态）
    var extraLaunchArguments: [String] { [] }
    /// 启动后是否等首页出现
    var waitsForHome: Bool { true }

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-e2e", "-demoUnlocked", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
            + extraLaunchArguments
        app.launch()
        if waitsForHome {
            XCTAssertTrue(id("home.search").waitForExistence(timeout: 25), "启动后应停在首页")
        }
    }

    // MARK: 查找

    func id(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func ids(_ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    func tab(_ title: String) -> XCUIElement {
        app.tabBars.buttons[title].firstMatch
    }

    func button(startingWith label: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let b = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 8), "找不到按钮「\(label)」", file: file, line: line)
        return b
    }

    func text(containing s: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    func navBar(_ title: String) -> XCUIElement { app.navigationBars[title] }

    // MARK: 操作

    func wait(_ element: XCUIElement, _ message: String, timeout: TimeInterval = 15,
              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message, file: file, line: line)
    }

    func waitGone(_ element: XCUIElement, _ message: String, timeout: TimeInterval = 10,
                  file: StaticString = #filePath, line: UInt = #line) {
        let p = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter().wait(for: [p], timeout: timeout), .completed, message, file: file, line: line)
    }

    func back(file: StaticString = #filePath, line: UInt = #line) {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(button.waitForExistence(timeout: 5), "找不到返回按钮", file: file, line: line)
        button.tap()
    }

    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 15) {
        var n = 0
        while !(element.exists && element.isHittable) && n < maxSwipes {
            app.swipeUp()
            n += 1
        }
    }

    func waitForFocus(_ element: XCUIElement, timeout: TimeInterval = 6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (element.value(forKey: "hasKeyboardFocus") as? Bool) == true { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    /// 识别结果页出现，并且识别完成（列表里出现语法点）
    func waitForScanResult(file: StaticString = #filePath, line: UInt = #line) {
        wait(navBar("识别结果"), "应进入识别结果页", file: file, line: line)
        wait(id("result.grammarRow"), "识别结果页应列出语法点", timeout: 45, file: file, line: line)
    }

    func openSampleFromHome() {
        scrollToTop()
        id("home.sample").tap()
        waitForScanResult()
    }

    func scrollToTop() {
        for _ in 0..<4 { app.swipeDown() }
    }

    /// 打开某个语法点的讲解页（通过搜索标签）
    func openDetailBySearch(_ query: String) {
        tab("搜索").tap()
        let field = app.searchFields.firstMatch
        wait(field, "搜索页应有搜索框")
        _ = waitForFocus(field)
        field.typeText(query)
        wait(id("search.result"), "搜索「\(query)」应有结果")
        id("search.result").tap()
        wait(id("screen.grammarDetail"), "点搜索结果应进入讲解页")
    }

    /// 从系统照片选择器里选第一张（CI 会先用 simctl addmedia 放入示例照片）
    func pickFirstPhoto(file: StaticString = #filePath, line: UInt = #line) {
        let image = app.scrollViews.otherElements.images.firstMatch
        if image.waitForExistence(timeout: 15) {
            image.tap()
        } else {
            let cell = app.cells.firstMatch
            XCTAssertTrue(cell.waitForExistence(timeout: 10), "照片选择器里没有照片", file: file, line: line)
            cell.tap()
        }
    }
}
