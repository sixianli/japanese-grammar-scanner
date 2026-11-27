import XCTest

final class SettingsTests: E2ETestCase {
    private func openSettings() {
        scrollToTop()
        id("home.settings").tap()
        wait(navBar("设置"), "应打开设置")
    }

    private func closeSettings(file: StaticString = #filePath, line: UInt = #line) {
        let done = id("settings.done")
        var levels = 0
        while !done.waitForExistence(timeout: 2) && levels < 3 {
            back(file: file, line: line)
            levels += 1
        }
        wait(done, "返回到设置首页后应有「完成」", timeout: 5, file: file, line: line)
        done.tap()
        waitGone(done, "点「完成」应关闭设置面板", file: file, line: line)
        wait(id("home.search"), "关闭设置应回到首页", file: file, line: line)
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
        let footers = ["English": "switch together", "한국어": "함께 바뀝니다", "Español": "cambian juntos", "Tiếng Việt": "cùng lúc",
                       "မြန်မာဘာသာ": "ပူးတွဲ", "繁體中文": "一起切換", "简体中文": "一起切换"]
        for (name, title) in expected {
            let row = button(startingWith: name)
            row.tap()
            assertStays(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch,
                        "切换到 \(name) 时语言页不应消失（不应先跳回首页再弹回）")
            wait(navBar(title), "切换到 \(name) 后页面标题应变成「\(title)」")
            if let f = footers[name], !f.isEmpty {
                wait(text(containing: f), "切换到 \(name) 后页面上的普通文字也应换成该语言")
            }
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
        wait(navBar("Settings"), "返回后设置页标题应是英文")
        navBar("Settings").buttons["Done"].tap()
        wait(id("home.search"), "关闭设置后应仍在首页")
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
            let share = app.descendants(matching: .any)["ActivityListView"]
            wait(share, "点发送后应弹出分享面板（或提交成功提示）", timeout: 10)
            for _ in 0..<3 where share.exists {
                let close = app.buttons.matching(NSPredicate(format: "label == '关闭' OR label == 'Close'")).firstMatch
                if close.exists && close.isHittable { close.tap() } else { app.swipeDown(velocity: .fast) }
                _ = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: share)], timeout: 3)
            }
            if navBar("反馈").exists {
                navBar("反馈").buttons["取消"].tap()
                waitGone(navBar("反馈"), "取消后关闭反馈页")
            }
            closeSettings()
        }
    }

    func testFeedbackAddScreenshot() {
        openSettings()
        button(startingWith: "功能：bug 或用不了").tap()
        wait(navBar("反馈"), "反馈页")
        button(startingWith: "添加截图").tap()
        pickFirstPhoto()
        let confirm = app.buttons.matching(NSPredicate(format: "(label IN {'添加', 'Add', '完成', 'Done', '确定', 'OK'}) AND NOT (identifier IN {'settings.done', 'keyboard.done'})")).firstMatch
        if confirm.waitForExistence(timeout: 8) {
            confirm.tap()
        } else {
            print("PICKER BUTTONS:", app.buttons.allElementsBoundByIndex.prefix(40).map { "\($0.identifier)|\($0.label)" })
        }
        wait(app.buttons["删除截图"], "选好的截图应显示在反馈页", timeout: 15)
        app.buttons["删除截图"].tap()
        navBar("反馈").buttons["取消"].tap()
    }

    func testGuideIsOnePageOfCoreCards() {
        openSettings()
        scrollTo(id("settings.guide"))
        id("settings.guide").tap()
        wait(navBar("使用指南"), "应打开使用指南")
        wait(id("guide.card"), "使用指南应显示图文卡片")
        for title in ["扫描日语", "点橙色框", "看语法讲解", "相近语法", "到时间就复习"] {
            let card = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'guide.card' AND label CONTAINS %@", title)).firstMatch
            scrollTo(card)
            XCTAssertTrue(card.exists, "使用指南应有「\(title)」卡片")
        }
        XCTAssertEqual(ids("guide.card").count, 5, "只讲 5 个核心功能")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'guide.topic.'")).firstMatch.exists, "不再有分功能的二级入口")
        XCTAssertFalse(id("guide.onboarding").exists, "不再有「再看一遍入门引导」")
        back()
        closeSettings()
    }

    func testAboutPages() {
        openSettings()
        scrollTo(id("settings.privacy"))
        id("settings.privacy").tap()
        wait(id("legal.summary"), "隐私页应显示隐私政策")
        XCTAssertTrue(id("legal.camera").exists, "隐私政策应有「相机与照片」")
        scrollTo(id("legal.contact"))
        XCTAssertTrue(id("legal.contact").exists, "隐私政策最后应有「联系我们」")
        back()
        scrollTo(app.buttons["开源许可"].firstMatch)
        button(startingWith: "使用条款").tap()
        wait(id("legal.eula"), "使用条款页应显示内容")
        XCTAssertTrue(app.links.firstMatch.exists, "使用条款页应有 Apple 许可协议链接")
        back()
        scrollTo(app.buttons["开源许可"].firstMatch)
        button(startingWith: "开源许可").tap()
        wait(text(containing: "SudachiPy"), "开源许可页应显示内容")
        XCTAssertGreaterThanOrEqual(ids("licenses.item").count, 4)
        back()
        scrollTo(text(containing: "版本"))
        wait(text(containing: "版本"), "设置应显示版本")
        closeSettings()
    }

    func testPrivacyMovedIntoSubpage() {
        openSettings()
        XCTAssertFalse(id("settings.usageStats").exists, "设置首页不应直接出现匿名统计开关")
        XCTAssertFalse(text(containing: "帮助我们了解有多少人在用").exists, "设置首页不应出现统计说明")
        scrollTo(id("settings.privacy"))
        id("settings.privacy").tap()
        wait(id("legal.summary"), "隐私页应显示隐私政策")
        let hasToggle = id("settings.usageStats").waitForExistence(timeout: 2)
        XCTAssertEqual(hasToggle, id("legal.usage-stats").exists, "统计开关和政策里的「匿名使用统计」必须同时有或同时没有")
        let feedback = id("legal.feedback")
        let offlineFeedback = id("legal.feedback-offline")
        var swipes = 0
        while !feedback.exists && !offlineFeedback.exists && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertNotEqual(feedback.exists, offlineFeedback.exists, "反馈说明只能出现与当前版本相符的一种")
        closeSettings()
    }

    func testUsageStatsToggle() {
        openSettings()
        scrollTo(id("settings.privacy"))
        id("settings.privacy").tap()
        let toggle = id("settings.usageStats")
        guard toggle.waitForExistence(timeout: 3) else {
            XCTAssertFalse(id("legal.usage-stats").exists, "不上报的版本，隐私政策里不应写匿名使用统计")
            closeSettings()
            return
        }
        XCTAssertEqual(toggle.value as? String, "1", "默认应打开")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        closeSettings()
        openSettings()
        scrollTo(id("settings.privacy"))
        id("settings.privacy").tap()
        wait(id("settings.usageStats"), "隐私页应有统计开关")
        XCTAssertEqual(id("settings.usageStats").value as? String, "0", "关闭状态应保存下来")
        let again = id("settings.usageStats")
        again.switches.firstMatch.exists ? again.switches.firstMatch.tap() : again.tap()
        XCTAssertEqual(again.value as? String, "1")
        closeSettings()
    }

    func testFeedbackKeyboardDone() {
        openSettings()
        button(startingWith: "体验与建议").tap()
        wait(navBar("反馈"), "应打开反馈页")
        let editor = app.textViews.firstMatch
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "点输入框应弹出键盘")
        editor.typeText("键盘测试")
        id("keyboard.done").tap()
        waitGone(app.keyboards.firstMatch, "点「完成」应收起键盘")
        XCTAssertTrue((editor.value as? String ?? "").contains("键盘测试"), "收起键盘后文字应保留")
        navBar("反馈").buttons["取消"].tap()
        waitGone(navBar("反馈"), "取消后关闭反馈页")
        closeSettings()
    }

    func testLanguageDiagnostics() {
        func dump(_ tag: String) {
            let info = id("lang.debug")
            let text = id("lang.debug.text")
            print("LANGDIAG \(tag): \(info.exists ? info.label : "-") || Text=\(text.exists ? text.label : "-") || settingsBar=\(navBar("设置").exists)/\(navBar("Settings").exists) langBar=\(navBar("语言").exists)/\(navBar("Language").exists)")
        }
        dump("before")
        openSettings()
        button(startingWith: "语言").tap()
        wait(navBar("语言"), "应进入语言页")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'English'")).firstMatch.tap()
        for t in [1, 2, 4] {
            sleep(UInt32(t))
            dump("after+\(t)")
        }
    }
}
