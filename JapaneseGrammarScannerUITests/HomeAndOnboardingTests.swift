import XCTest

/// 首页各入口：相机、相册、示例、反馈、清除记录
final class HomeTests: E2ETestCase {
    func testCameraButtonOpensScanTab() {
        scrollToTop()
        id("home.camera").tap()
        // 模拟器没有相机：显示「试试示例书页」；真机显示快门
        let sample = id("scan.trySample"), shutter = id("scan.shutter")
        XCTAssertTrue(sample.waitForExistence(timeout: 10) || shutter.exists, "相机扫描按钮应切到扫描页")
    }

    func testSampleButtonOpensResult() {
        openSampleFromHome()
        back()
        wait(id("home.search"), "返回应回到首页")
    }

    func testPhotoPickerOpensResult() {
        scrollToTop()
        id("home.photos").tap()
        pickFirstPhoto()
        wait(navBar("识别结果"), "从相册选图后应进入识别结果页", timeout: 30)
        back()
        wait(id("home.search"), "返回应回到首页")
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

/// 全新安装：引导页、新用户首页、空状态
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
        // 新用户首页：入门语法列表
        scrollTo(id("grammarRow"))
        id("grammarRow").tap()
        wait(detailScreen, "新用户首页的语法点应能打开讲解")
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
