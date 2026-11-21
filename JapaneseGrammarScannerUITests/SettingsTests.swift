import XCTest

/// 设置：外观、全部语言、三种反馈（含截图、发送）、使用引导、隐私政策、使用条款、开源许可、版本
final class SettingsTests: E2ETestCase {
    private func openSettings() {
        scrollToTop()
        id("home.settings").tap()
        wait(navBar("设置"), "应打开设置")
    }

    /// 关闭设置面板。「完成」（settings.done）只在设置首页的导航栏上；停在二级页（隐私、使用指南、指南条目…）时
    /// 那里只有返回按钮，先逐级返回到设置首页再点「完成」。
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
        // 页面标题和页脚（普通文字）都要换成所选语言
        let footers = ["English": "switch together", "한국어": "함께 바뀝니다", "Español": "cambian juntos", "Tiếng Việt": "cùng lúc",
                       "မြန်မာဘာသာ": "ပူးတွဲ", "繁體中文": "一起切換", "简体中文": "一起切换"]
        for (name, title) in expected {
            let row = button(startingWith: name)
            row.tap()
            // 切换语言时不能关掉设置面板、跳回首页再弹回来：语言列表要一直在屏幕上
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
        // 返回设置页：设置页本身也已经是英文（就地刷新，不需要重新打开）
        wait(navBar("Settings"), "返回后设置页标题应是英文")
        navBar("Settings").buttons["Done"].tap()
        // 关掉设置后仍在首页（切换语言不改变当前标签）
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
            // App 内提交未开通时，弹出系统分享面板
            let share = app.descendants(matching: .any)["ActivityListView"]
            wait(share, "点发送后应弹出分享面板（或提交成功提示）", timeout: 10)
            // iOS 26 的分享面板有时下滑一次关不掉：最多试三次，有「关闭」按钮就点它
            for _ in 0..<3 where share.exists {
                let close = app.buttons.matching(NSPredicate(format: "label == '关闭' OR label == 'Close'")).firstMatch
                if close.exists && close.isHittable { close.tap() } else { app.swipeDown(velocity: .fast) }
                _ = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: share)], timeout: 3)
            }
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
        // 多选的照片选择器要再点确认（iOS 26 是右上角的 ✓，名字也叫「完成」）。
        // 设置页（被盖住）和键盘上的「完成」有自己的标识，排除掉，剩下的就是照片选择器的
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

    /// 入门引导现在从「设置 → 使用指南 → 再看一遍入门引导」打开
    func testOnboardingFromSettings() {
        openSettings()
        scrollTo(id("settings.guide"))
        id("settings.guide").tap()
        wait(navBar("使用指南"), "应打开使用指南")
        scrollTo(id("guide.onboarding"))
        id("guide.onboarding").tap()
        wait(app.buttons["跳过"], "应打开入门引导", timeout: 10)
        app.buttons["跳过"].tap()
        button(startingWith: "开始使用").tap()
        wait(id("home.search"), "引导结束回到首页")
    }

    /// 使用指南覆盖每个主要功能：逐个点开都有分步说明，并能返回
    func testGuideCoversEveryFeature() {
        openSettings()
        scrollTo(id("settings.guide"))
        id("settings.guide").tap()
        wait(navBar("使用指南"), "应打开使用指南")
        let features = ["scan", "scanResult", "detail", "contrast", "review", "library", "search", "history", "appearance", "feedback"]
        for f in features {
            let row = id("guide.topic.\(f)")
            scrollTo(row)
            wait(row, "使用指南应有「\(f)」")
            row.tap()
            wait(id("guide.step"), "「\(f)」应有分步说明")
            XCTAssertGreaterThanOrEqual(ids("guide.step").count, 2, "「\(f)」至少两步")
            back()
            wait(navBar("使用指南"), "应回到使用指南")
        }
        closeSettings()
    }

    func testAboutPages() {
        openSettings()
        scrollTo(id("settings.privacy"))
        id("settings.privacy").tap()
        wait(id("legal.summary"), "隐私页应显示隐私政策")
        XCTAssertTrue(id("legal.camera").exists, "隐私政策应有「相机与照片」")
        // 「联系我们」是政策的最后一节，在屏幕下方；列表只把屏幕上的行放进界面层级，要滑到它出现
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

    /// Build 16 反馈：隐私那一块不要放在设置首页（吓退用户）。现在在「关于 → 隐私」二级页里。
    func testPrivacyMovedIntoSubpage() {
        openSettings()
        XCTAssertFalse(id("settings.usageStats").exists, "设置首页不应直接出现匿名统计开关")
        XCTAssertFalse(text(containing: "帮助我们了解有多少人在用").exists, "设置首页不应出现统计说明")
        scrollTo(id("settings.privacy"))
        id("settings.privacy").tap()
        wait(id("legal.summary"), "隐私页应显示隐私政策")
        // 说的和做的一致：有统计开关的版本，政策里一定写了匿名使用统计；没有开关的版本，政策里也不写
        let hasToggle = id("settings.usageStats").waitForExistence(timeout: 2)
        XCTAssertEqual(hasToggle, id("legal.usage-stats").exists, "统计开关和政策里的「匿名使用统计」必须同时有或同时没有")
        XCTAssertNotEqual(id("legal.feedback").exists, id("legal.feedback-offline").exists, "反馈说明只能出现与当前版本相符的一种")
        closeSettings()
    }

    /// 匿名使用统计开关（只在会上报的版本里有）：默认打开，关掉后重新打开设置仍是关闭
    func testUsageStatsToggle() {
        openSettings()
        scrollTo(id("settings.privacy"))
        id("settings.privacy").tap()
        let toggle = id("settings.usageStats")
        guard toggle.waitForExistence(timeout: 3) else {
            // 没有开通 iCloud 上报的版本：不显示开关，政策里也不能写「匿名使用统计」
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
