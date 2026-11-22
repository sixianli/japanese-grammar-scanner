import XCTest

final class HomeTests: E2ETestCase {
    func testCameraButtonOpensScanTab() {
        scrollToTop()
        id("home.camera").tap()
        let sample = id("scan.trySample"), shutter = id("scan.shutter")
        XCTAssertTrue(sample.waitForExistence(timeout: 10) || shutter.exists, "相机扫描按钮应切到扫描页")
    }

    func testHomeHasNoHeadlineAndHidesSampleLinkAfterScanning() {
        scrollToTop()
        wait(id("home.camera"), "首页应有相机扫描按钮")
        XCTAssertTrue(id("home.camera").label.contains("对准书页，标出句子里的语法"), "相机按钮里应有一行说明：\(id("home.camera").label)")
        XCTAssertFalse(text(containing: "扫描日文，找出语法").exists, "首页不再有大标题")
        XCTAssertFalse(id("home.sample").exists, "扫描过以后首页不再显示「试试示例」")
        XCTAssertTrue(id("home.photos").exists, "首页仍有「从相册识别」")
    }

    func testPhotoPickerOpensResult() {
        scrollToTop()
        id("home.photos").tap()
        pickFirstPhoto()
        wait(navBar("识别结果"), "从相册选图后应进入识别结果页", timeout: 30)
        back()
        wait(id("home.search"), "返回应回到首页")
    }

    func testSearchBarStaysPinnedWhenScrolling() {
        let search = id("home.search"), settings = id("home.settings")
        wait(search, "首页顶部应有搜索框")
        let pinnedY = search.frame.minY
        scrollTo(id("home.feedback"))
        XCTAssertTrue(id("home.feedback").isHittable, "应已滑到页面底部")
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(search.frame.minY, pinnedY, accuracy: 1, "滑到底部后搜索框应仍固定在顶部")
        XCTAssertTrue(window.contains(search.frame), "滑到底部后搜索框仍应完整可见")
        XCTAssertTrue(window.contains(settings.frame), "滑到底部后设置按钮仍应完整可见")
        settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        wait(id("settings.done"), "滑到底部后点顶部的设置按钮应打开设置")
        id("settings.done").tap()
        waitGone(id("settings.done"), "点「完成」应关闭设置")
        let atBottom = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: id("home.feedback"))
        XCTAssertEqual(XCTWaiter().wait(for: [atBottom], timeout: 5), .completed, "关闭设置后首页应仍停在底部")
        search.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        wait(app.searchFields.firstMatch, "滑到底部后点顶部的搜索框应进入搜索")
    }

    func testFeedbackLinkOpensFeedback() {
        scrollTo(id("home.feedback"))
        id("home.feedback").tap()
        wait(navBar("反馈"), "应打开反馈页")
        navBar("反馈").buttons["取消"].tap()
        waitGone(navBar("反馈"), "取消后应关闭反馈页")
    }

    func testClearRecentViewed() {
        scrollTo(id("seeAll.recent"))
        id("seeAll.recent").tap()
        wait(navBar("最近查看"), "应进入最近查看")
        navBar("最近查看").buttons["清除"].tap()
        app.buttons.matching(NSPredicate(format: "label == '清除'")).element(boundBy: 1).tap()
        waitGone(id("grammarRow"), "清除后列表应为空")
        back()
        wait(id("home.search"), "应回到首页")
        XCTAssertFalse(id("seeAll.recent").exists, "清除后首页不应再有「最近查看」的查看全部")
    }

    func testClearAllScans() {
        id("seeAll.scans").tap()
        wait(navBar("全部扫描记录"), "应进入全部扫描记录")
        navBar("全部扫描记录").buttons["清除"].tap()
        app.buttons.matching(NSPredicate(format: "label == '清除'")).element(boundBy: 1).tap()
        waitGone(id("scanRecord"), "清除后不应再有扫描记录")
        back()
        wait(id("home.search"), "应回到首页")
        XCTAssertFalse(id("home.continueScan").exists, "清除后首页不应再有「继续上次」")
    }
}

final class FreshInstallTests: E2ETestCase {
    override var extraLaunchArguments: [String] { ["-e2eFresh"] }
    override var waitsForHome: Bool { false }

    func testOnboardingNextThroughThenStart() {
        let next = app.buttons["下一步"]
        wait(next, "首次启动应显示引导页", timeout: 25)
        var pages = 0
        while next.exists && pages < 10 {
            next.tap()
            pages += 1
        }
        button(startingWith: "开始使用").tap()
        wait(id("home.search"), "引导结束应进入首页")
        scrollTo(id("grammarRow"))
        id("grammarRow").tap()
        wait(detailScreen, "新用户首页的语法点应能打开讲解")
    }

    func testNewUserHomeShowsSmallSampleLink() {
        wait(app.buttons["跳过"], "引导页", timeout: 25)
        app.buttons["跳过"].tap()
        button(startingWith: "开始使用").tap()
        wait(id("home.search"), "应进入首页")
        let link = id("home.sample")
        wait(link, "还没扫描过时首页应有「试试示例」小链接")
        XCTAssertTrue(link.label.contains("试试示例"), "链接文字应包含「试试示例」：\(link.label)")
        XCTAssertLessThan(link.frame.height, id("home.photos").frame.height, "「试试示例」应是一行小链接，比按钮矮")
        link.tap()
        waitForScanResult()
    }

    func testOnboardingSkipThenTrySample() {
        let skip = app.buttons["跳过"]
        wait(skip, "引导页应有「跳过」", timeout: 25)
        skip.tap()
        button(startingWith: "先用示例书页试试").tap()
        waitForScanResult()
    }

    func testEmptyStates() {
        wait(app.buttons["跳过"], "引导页", timeout: 25)
        app.buttons["跳过"].tap()
        button(startingWith: "开始使用").tap()
        wait(id("home.search"), "应进入首页")
        tab("收藏").tap()
        wait(text(containing: "还没有收藏"), "没有收藏时应显示空状态")
        tab("搜索").tap()
        wait(text(containing: "输入语法、读音或意思"), "没有浏览记录时搜索页应显示提示")
    }
}
