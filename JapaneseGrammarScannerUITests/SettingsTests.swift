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
        // 页面标题和页脚（普通文字）都要换成所选语言
        let footers = ["English": "switch together", "한국어": "함께 바뀝니다", "Español": "cambian juntos", "Tiếng Việt": "cùng lúc",
                       "မြန်မာဘာသာ": "ပူးတွဲ", "繁體中文": "一起切換", "简体中文": "一起切换"]
        for (name, title) in expected {
            button(startingWith: name).tap()
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
            let close = app.buttons.matching(NSPredicate(format: "label == '关闭' OR label == 'Close'")).firstMatch
            if share.exists && close.exists { close.tap() }
            // 下滑关分享面板时，反馈页有时也一起关了
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
        // 多选的照片选择器要再点确认（iOS 26 是右侧的 ✓ 按钮，旧系统是「添加」）
        // 多选的照片选择器要再点确认（iOS 26 是右上角的 ✓）。同名的「完成」按钮设置页里也有（被盖住），只点看得见的那个
        let candidates = app.buttons.matching(NSPredicate(format: "label IN {'添加', 'Add', '完成', 'Done', '确定', 'OK', '选取', 'Choose'} OR identifier IN {'Done', 'Add', 'DoneButton'}"))
        let deadline = Date().addingTimeInterval(8)
        var tapped = false
        while !tapped && Date() < deadline {
            if let b = candidates.allElementsBoundByIndex.last(where: { $0.exists && $0.isHittable }) {
                b.tap()
                tapped = true
            } else {
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        if !tapped {
            print("PICKER BUTTONS:", app.buttons.allElementsBoundByIndex.prefix(40).map { "\($0.identifier)|\($0.label)|\($0.isHittable)" })
        }
        wait(app.buttons["删除截图"], "选好的截图应显示在反馈页", timeout: 15)
        app.buttons["删除截图"].tap()
        navBar("反馈").buttons["取消"].tap()
    }

    func testOnboardingFromSettings() {
        openSettings()
        scrollTo(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "使用引导")).firstMatch)
        button(startingWith: "使用引导").tap()
        wait(app.buttons["跳过"], "应打开使用引导", timeout: 10)
        app.buttons["跳过"].tap()
        button(startingWith: "开始使用").tap()
        wait(id("home.search"), "引导结束回到首页")
    }

    func testAboutPages() {
        openSettings()
        scrollTo(app.buttons["开源许可"].firstMatch)
        button(startingWith: "隐私政策").tap()
        wait(text(containing: "一句话说明"), "隐私政策页应显示内容")
        back()
        scrollTo(app.buttons["开源许可"].firstMatch)
        button(startingWith: "使用条款").tap()
        wait(app.links.firstMatch, "使用条款页应有 Apple 许可协议链接")
        back()
        scrollTo(app.buttons["开源许可"].firstMatch)
        button(startingWith: "开源许可").tap()
        wait(text(containing: "SudachiPy"), "开源许可页应显示内容")
        back()
        scrollTo(text(containing: "版本"))
        wait(text(containing: "版本"), "设置应显示版本")
        closeSettings()
    }

    /// 匿名使用统计开关：默认打开，关掉后重新打开设置仍是关闭
    func testUsageStatsToggle() {
        openSettings()
        let toggle = id("settings.usageStats")
        scrollTo(toggle)
        wait(toggle, "设置里应有匿名使用统计开关")
        XCTAssertEqual(toggle.value as? String, "1", "默认应打开")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        closeSettings()
        openSettings()
        scrollTo(id("settings.usageStats"))
        XCTAssertEqual(id("settings.usageStats").value as? String, "0", "关闭状态应保存下来")
        let again = id("settings.usageStats")
        again.switches.firstMatch.exists ? again.switches.firstMatch.tap() : again.tap()
        XCTAssertEqual(again.value as? String, "1")
        closeSettings()
    }

    /// 反馈描述输入后，点键盘上方的「完成」收起键盘，文字保留
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

    /// 诊断：切换到英文前后，各种查找翻译的方式实际得到什么（只打印，不判失败）
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
