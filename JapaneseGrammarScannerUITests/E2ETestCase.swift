import XCTest

class E2ETestCase: XCTestCase {
    var app: XCUIApplication!

    var extraLaunchArguments: [String] { [] }
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
        let icon = ["首页": "house", "扫描": "text.viewfinder", "语法库": "books.vertical", "收藏": "Kinchaku", "搜索": "magnifyingglass",
                    "Home": "house", "Scan": "text.viewfinder", "Grammar": "books.vertical", "Favorites": "Kinchaku", "Search": "magnifyingglass"][title] ?? ""
        let candidates = app.buttons
            .matching(NSPredicate(format: "label == %@ AND (identifier BEGINSWITH %@ OR identifier == '')", title, icon))
        if icon == "Kinchaku" { return candidates.firstMatch }
        return candidates
            .containing(NSPredicate(format: "identifier BEGINSWITH %@", icon))
            .firstMatch
    }

    var detailScreen: XCUIElement { id("detail.favorite") }

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

    func waitGone(_ element: XCUIElement, _ message: String, timeout: TimeInterval = 15,
                  file: StaticString = #filePath, line: UInt = #line) {
        let p = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter().wait(for: [p], timeout: timeout), .completed, message, file: file, line: line)
    }

    func assertStays(_ element: XCUIElement, for seconds: TimeInterval = 1.5, _ message: String,
                     file: StaticString = #filePath, line: UInt = #line) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            XCTAssertTrue(element.exists, message, file: file, line: line)
            if !element.exists { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    func back(file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons["BackButton"].firstMatch
        if button.waitForExistence(timeout: 5) {
            button.tap()
            return
        }
        let fallback = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(fallback.waitForExistence(timeout: 3), "找不到返回按钮", file: file, line: line)
        fallback.tap()
    }

    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 15) {
        var n = 0
        while !(element.exists && element.isHittable) && n < maxSwipes {
            app.swipeUp()
            n += 1
        }
    }

    func waitForFocus(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        app.keyboards.firstMatch.waitForExistence(timeout: timeout)
    }

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

    func scrollClearOfTopBar(_ element: XCUIElement, maxSwipes: Int = 15) {
        scrollTo(element, maxSwipes: maxSwipes)
        let window = app.windows.firstMatch.frame
        var n = 0
        while element.exists && element.frame.minY < window.minY + window.height * 0.25 && n < 5 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)))
            n += 1
        }
        XCTAssertTrue(element.isHittable, "要点的元素应完整露在顶部导航栏下面")
    }

    func detailTitle(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'detail.title' AND label == %@", title)).firstMatch
    }

    func openSimilarGrammar(_ similar: XCUIElement, file: StaticString = #filePath, line: UInt = #line) -> (from: String, to: String) {
        wait(id("detail.title"), "讲解页应有标题", file: file, line: line)
        let from = id("detail.title").label
        scrollClearOfTopBar(similar, maxSwipes: 25)
        similar.tap()
        let other = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'detail.title' AND label != %@", from)).firstMatch
        wait(other, "点相近语法应打开另一个语法的讲解页，而不是停在「\(from)」", file: file, line: line)
        return (from, other.label)
    }

    func openDetailBySearch(_ query: String) {
        tab("搜索").tap()
        let field = app.searchFields.firstMatch
        wait(field, "搜索页应有搜索框")
        if !waitForFocus(field) {
            field.tap()
            _ = waitForFocus(field, timeout: 5)
        }
        field.typeText(query)
        wait(id("search.result"), "搜索「\(query)」应有结果")
        id("search.result").tap()
        wait(detailScreen, "点搜索结果应进入讲解页")
    }

    func pickFirstPhoto(file: StaticString = #filePath, line: UInt = #line) {
        if app.buttons["进一步了解…"].waitForExistence(timeout: 3) {
            app.buttons.matching(NSPredicate(format: "label == '关闭'")).firstMatch.tap()
        }
        let image = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 45), "照片选择器里没有照片", file: file, line: line)
        image.tap()
    }
}
