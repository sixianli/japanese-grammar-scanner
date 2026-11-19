import XCTest

/// 设置：外观、全部语言、三种反馈（含截图、发送）、使用引导、隐私政策、使用条款、开源许可、版本
final class SettingsTests: E2ETestCase {
    private func openSettings() {
        scrollToTop()
        id("home.settings").tap()
        wait(navBar("设置"), "应打开设置")
    }

    private func closeSettings() {
        navBar("设置").buttons["完成"].tap()
        wait(id("home.search"), "关闭设置应回到首页")
    }

    func testAppearanceAllSwatches() {
        openSettings()
        button(startingWith: "主题色与背景色").tap()
        wait(navBar("外观"), "应进入外观")
        let swatches = ids("swatch")
        wait(swatches.firstMatch, "应有颜色选项")
        let n = swatches.count
        XCTAssertGreaterThanOrEqual(n, 10)
        for i in 0..<n {
            let s = swatches.element(boundBy: i)
            scrollTo(s)
            s.tap()
        }
        swatches.element(boundBy: 0).tap()
        back()
        wait(navBar("设置"), "返回设置")
        closeSettings()
    }

    func testEveryLanguage() {
        openSettings()
        button(startingWith: "语言").tap()
        let expected: [(String, String)] = [
            ("English", "Language"), ("한국어", "언어"), ("Español", "Idioma"), ("Tiếng Việt", "Ngôn ngữ"),
            ("မြန်မာဘာသာ", "ဘာသာစကား"), ("繁體中文", "語言"), ("简体中文", "语言"),
        ]
        for (name, title) in expected {
            button(startingWith: name).tap()
            wait(navBar(title), "切换到 \(name) 后页面标题应变成「\(title)」")
        }
        button(startingWith: "跟随系统").tap()
        back()
        closeSettings()
    }

    func testLanguageAppliesToContent() {
        openSettings()
        button(startingWith: "语言").tap()
        button(startingWith: "English").tap()
        wait(navBar("Language"), "英文")
        back()
        navBar("Settings").buttons["Done"].tap()
        tab("Grammar").tap()
        wait(id("library.row"), "语法库")
        id("library.row").tap()
        wait(detailScreen, "讲解页")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'the'")).firstMatch.waitForExistence(timeout: 8),
                      "切换到英文后讲解内容也应是英文")
    }

    func testFeedbackAllKindsSendOpensShareSheet() {
        for kind in ["内容：讲解有误或看不懂", "功能：bug 或用不了", "体验与建议"] {
            openSettings()
            button(startingWith: kind).tap()
            wait(navBar("反馈"), "「\(kind)」应打开反馈页")
            let editor = app.textViews.firstMatch
            wait(editor, "应有描述输入框")
            editor.tap()
            editor.typeText("自动化测试：\(kind)")
            navBar("反馈").buttons["发送"].tap()
            // App 内提交未开通时，弹出系统分享面板
            let share = app.descendants(matching: .any)["ActivityListView"]
            wait(share, "点发送后应弹出分享面板（或提交成功提示）", timeout: 10)
            app.swipeDown(velocity: .fast)
            if share.exists { app.buttons.matching(NSPredicate(format: "label == '关闭' OR label == 'Close'")).firstMatch.tap() }
            navBar("反馈").buttons["取消"].tap()
            waitGone(navBar("反馈"), "取消后关闭反馈页")
            closeSettings()
        }
    }

    func testFeedbackAddScreenshot() {
        openSettings()
        button(startingWith: "功能：bug 或用不了").tap()
        wait(navBar("反馈"), "反馈页")
        button(startingWith: "添加截图").tap()
        pickFirstPhoto()
        let add = app.buttons.matching(NSPredicate(format: "label == '添加' OR label == 'Add'")).firstMatch
        if add.waitForExistence(timeout: 5) { add.tap() }
        wait(app.buttons["删除截图"], "选好的截图应显示在反馈页", timeout: 15)
        app.buttons["删除截图"].tap()
        navBar("反馈").buttons["取消"].tap()
    }

    func testOnboardingFromSettings() {
        openSettings()
        button(startingWith: "使用引导").tap()
        wait(app.buttons["跳过"], "应打开使用引导", timeout: 10)
        app.buttons["跳过"].tap()
        button(startingWith: "开始使用").tap()
        wait(id("home.search"), "引导结束回到首页")
    }

    func testAboutPages() {
        openSettings()
        button(startingWith: "隐私政策").tap()
        wait(text(containing: "一句话说明"), "隐私政策页应显示内容")
        back()
        button(startingWith: "使用条款").tap()
        wait(app.links.firstMatch, "使用条款页应有 Apple 许可协议链接")
        back()
        button(startingWith: "开源许可").tap()
        wait(text(containing: "SudachiPy"), "开源许可页应显示内容")
        back()
        wait(text(containing: "版本"), "设置应显示版本")
        closeSettings()
    }
}
