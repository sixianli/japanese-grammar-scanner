import XCTest

final class DetailTests: E2ETestCase {
    func testSenseRowsJumpWithinPage() {
        openDetailBySearch("ように")
        let rows = ids("detail.senseRow")
        wait(rows.firstMatch, "讲解页应列出义项")
        rows.element(boundBy: min(1, rows.count - 1)).tap()
        XCTAssertTrue(detailScreen.exists, "点义项应在本页内跳转，不离开讲解页")
    }

    func testSimilarGrammarPushesAndBackReturns() {
        openDetailBySearch("だけに")
        let pages = openSimilarGrammar(id("detail.similar"))
        back()
        wait(detailTitle(pages.from), "返回应回到原来的讲解页「\(pages.from)」")
        waitGone(detailTitle(pages.to), "返回后不应还停在「\(pages.to)」")
        back()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 8), "再返回应回到搜索页")
    }

    func testContrastSectionExpandCollapseAndNavigate() {
        openDetailBySearch("ようになる")
        let toggle = id("detail.contrast.toggle")
        scrollTo(toggle)
        wait(toggle, "相近语法应有「看例句对比」按钮")
        XCTAssertFalse(text(containing: "怎么分辨").exists, "默认收起，不显示讲解")
        toggle.tap()
        wait(text(containing: "怎么分辨"), "展开后应显示「怎么分辨」讲解")
        XCTAssertTrue(button(startingWith: "收起").exists, "展开后按钮变成「收起」")
        button(startingWith: "收起").tap()
        waitGone(text(containing: "怎么分辨"), "收起后讲解应隐藏")

        let pages = openSimilarGrammar(id("detail.similar"))
        back()
        wait(detailTitle(pages.from), "返回后应回到原来的讲解页「\(pages.from)」")
        waitGone(detailTitle(pages.to), "返回后不应还停在「\(pages.to)」")
    }

    func testMeaningGroupSplitsBySenseOnTameNi() {
        openDetailBySearch("ために")
        let headers = ids("detail.contrast.senseHeader")
        let purpose = headers.matching(NSPredicate(format: "label CONTAINS %@", "为了")).firstMatch
        scrollTo(purpose, maxSwipes: 25)
        wait(purpose, "ために 的「意思差不多的」应有「为了」小节")
        XCTAssertTrue(purpose.label.contains("本页第 1 个意思"), "「为了」小节应写明对应本页第 1 个意思：\(purpose.label)")
        let cause = headers.matching(NSPredicate(format: "label CONTAINS %@", "因为")).firstMatch
        scrollTo(cause, maxSwipes: 10)
        wait(cause, "ために 的「意思差不多的」应有「因为」小节")
        XCTAssertTrue(cause.label.contains("本页第 2 个意思"), "「因为」小节应写明对应本页第 2 个意思：\(cause.label)")
        XCTAssertEqual(headers.count, 2, "两个意思各一个小节")
    }

    func testSingleMeaningPageHasNoSenseSubsections() {
        openDetailBySearch("ようになる")
        let toggle = id("detail.contrast.toggle")
        scrollTo(toggle)
        wait(toggle, "相近语法应有对比卡片")
        XCTAssertEqual(ids("detail.contrast.senseHeader").count, 0, "只有一个意思的语法点不按意思分小节")
    }

    func testMustKnowTagOnlyOnHighFrequencyGrammar() {
        openDetailBySearch("について")
        wait(id("detail.level"), "标题下方应有等级标签")
        XCTAssertTrue(id("tag.mustKnow").waitForExistence(timeout: 5), "について 是必考语法，应显示「必考」")
    }

    func testTappingMustKnowTagInRowOpensDetail() {
        tab("搜索").tap()
        let field = app.searchFields.firstMatch
        wait(field, "搜索页应有搜索框")
        field.tap()
        field.typeText("ようになる")
        let row = id("search.result")
        wait(row, "应有搜索结果")
        let tag = row.descendants(matching: .any).matching(identifier: "tag.mustKnow").firstMatch
        wait(tag, "〜ようになる 的结果行应有「必考」")
        tag.tap()
        wait(detailScreen, "点结果行里的「必考」也应进入讲解页")
    }

    func testNoMustKnowTagOnLowFrequencyGrammar() {
        openDetailBySearch("たち")
        wait(id("detail.level"), "标题下方应有等级标签")
        XCTAssertFalse(id("tag.mustKnow").exists, "〜たち 不是必考语法，不应显示「必考」")
    }

    func testTitleFollowsScrollIntoCenteredBar() {
        openDetailBySearch("ようになる")
        let pageTitle = id("detail.title")
        wait(pageTitle, "讲解页顶部应有标题")
        let title = pageTitle.label
        let barTitle = id("detail.barTitle")
        wait(barTitle, "页面顶部应显示语法标题")
        XCTAssertEqual(barTitle.label, title, "显示的应是本页语法的完整标题")
        let restFrame = barTitle.frame
        assertTitleFitsOneLineBetweenButtons(title, barTitle, state: "展开", pinned: false)
        assertNoHorizontalOverflow(state: "展开")
        let level = id("detail.level")
        wait(level, "标题下方应有等级标签")
        XCTAssertEqual(ids("detail.level").count, 1, "页面上只有一组标签")
        XCTAssertGreaterThan(level.frame.minY, barTitle.frame.maxY - 3, "没滚动时标签在大标题下面")
        let restLevel = level.frame

        app.swipeUp()
        app.swipeUp()
        XCTAssertEqual(ids("detail.level").count, 1, "滑动后仍只有一组标签，不会另出一组叠在一起")
        XCTAssertLessThan(level.frame.height, restLevel.height, "标签跟着标题一起缩小")
        XCTAssertLessThanOrEqual(level.frame.maxY, id("detail.titleBar").frame.maxY, "缩小后的标签在顶栏里")
        XCTAssertEqual(barTitle.frame.midX, restFrame.midX, accuracy: 2, "标题只往上移，水平位置不变")
        assertTitleFitsOneLineBetweenButtons(title, barTitle, state: "收起", pinned: true)
        assertNoHorizontalOverflow(state: "收起")
        XCTAssertLessThan(barTitle.frame.minY, restFrame.minY - 20, "标题应跟着往上移到顶栏")
        XCTAssertLessThan(barTitle.frame.maxY, 200, "标题应停在屏幕顶部的顶栏里")
        XCTAssertLessThan(barTitle.frame.height, restFrame.height, "收进顶栏的标题应比页面大标题小")
        XCTAssertTrue(level.label.hasPrefix("JLPT N"), "等级应写成「JLPT N…」")
        XCTAssertGreaterThan(level.frame.minY, barTitle.frame.minY, "等级应在标题下方")
        let mustKnow = id("tag.mustKnow")
        XCTAssertTrue(mustKnow.exists, "ようになる 是必考语法，顶栏里的标签行也应有「必考」")
        XCTAssertEqual(ids("tag.mustKnow").count, 1, "「必考」只有一个")
        XCTAssertEqual(mustKnow.frame.midY, level.frame.midY, accuracy: 2, "等级和必考在顶栏里排成一行")
        XCTAssertGreaterThan(mustKnow.frame.minX, level.frame.maxX, "必考跟在等级右边")
        XCTAssertFalse(id("detail.favorited").exists, "没收藏的语法，顶栏里不应有「已收藏」")
        let row = level.frame.union(mustKnow.frame)
        XCTAssertEqual(row.midX, barTitle.frame.midX, accuracy: 2, "标签行应在标题正下方居中")

        scrollToTop()
        XCTAssertEqual(level.frame.height, restLevel.height, accuracy: 1, "回到顶部后标签恢复原来的大小")
        XCTAssertEqual(level.frame.minY, restLevel.minY, accuracy: 2, "回到顶部后标签回到大标题下面")
        XCTAssertEqual(barTitle.frame.minY, restFrame.minY, accuracy: 2, "回到顶部后标题应回到原来的位置")
        XCTAssertEqual(barTitle.frame.height, restFrame.height, accuracy: 2, "回到顶部后标题恢复原来的大小")
    }

    private func openDetailBySearch(_ query: String, titleContains title: String) {
        tab("搜索").tap()
        let field = app.searchFields.firstMatch
        wait(field, "搜索页应有搜索框")
        field.tap()
        field.typeText(query)
        let hasTitle = NSPredicate(format: "label CONTAINS %@", title)
        let direct = ids("search.result").matching(hasTitle).firstMatch
        let result = direct.waitForExistence(timeout: 8) ? direct : ids("search.result").containing(hasTitle).firstMatch
        wait(result, "搜索「\(query)」应找到「\(title)」")
        result.tap()
        wait(detailScreen, "点搜索结果应进入讲解页")
    }

    private func assertTitleFitsOneLineBetweenButtons(_ title: String, _ element: XCUIElement, state: String, pinned: Bool,
                                                     file: StaticString = #filePath, line: UInt = #line) {
        let column = id("detail.titleColumn")
        XCTAssertTrue(column.exists, "应能找到标题所在的页面内容列", file: file, line: line)
        let c = column.frame
        let frame = element.frame
        let inset = pinned ? CGFloat(48) : CGFloat(0)
        XCTAssertEqual(frame.midX, c.midX, accuracy: 3, "\(state)：标题「\(title)」应在内容列正中，不偏左右：标题 \(frame)，内容列 \(c)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minX, c.minX + inset - 1, "\(state)：标题不能超出内容列左边：标题 \(frame)，内容列 \(c)", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, c.maxX - inset + 1, "\(state)：标题不能超出内容列右边：标题 \(frame)，内容列 \(c)", file: file, line: line)
    }

    private func assertNoHorizontalOverflow(state: String, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        for text in app.staticTexts.allElementsBoundByIndex where text.exists && text.frame.height > 0 && text.frame.minY < window.maxY && text.frame.maxY > window.minY {
            let f = text.frame
            XCTAssertGreaterThanOrEqual(f.minX, window.minX - 1, "\(state)：页面内容不能超出屏幕左边：「\(text.label)」\(f)", file: file, line: line)
            XCTAssertLessThanOrEqual(f.maxX, window.maxX + 1, "\(state)：页面内容不能超出屏幕右边：「\(text.label)」\(f)", file: file, line: line)
        }
    }

    private func checkLongTitleInBothStates(query: String, title: String) {
        openDetailBySearch(query, titleContains: title)
        let barTitle = id("detail.barTitle")
        wait(barTitle, "页面顶部应有标题")
        XCTAssertEqual(barTitle.label, title, "显示的应是本页语法的完整标题")

        let oneLine = barTitle.frame.height
        XCTAssertLessThan(oneLine, 70, "展开时「\(title)」只占一行，不折成两三行：\(barTitle.frame)")
        assertTitleFitsOneLineBetweenButtons(title, barTitle, state: "展开", pinned: false)
        let expandedMidY = barTitle.frame.midY

        app.swipeUp()
        app.swipeUp()
        XCTAssertLessThan(barTitle.frame.height, oneLine, "收进顶栏后标题比展开时小：\(barTitle.frame)")
        XCTAssertLessThan(barTitle.frame.maxY, 200, "标题和标签行都在顶栏里，顶栏不变高：\(barTitle.frame)")
        XCTAssertLessThan(barTitle.frame.midY, expandedMidY, "标题应往上移进顶栏")
        assertTitleFitsOneLineBetweenButtons(title, barTitle, state: "收起", pinned: true)
        XCTAssertGreaterThan(id("detail.level").frame.minY, barTitle.frame.maxY - 3, "标签行在一行标题下面")
        XCTAssertEqual(ids("detail.level").count, 1, "只有一组标签")
    }

    func testLongTitleMamaniStaysOneLineCenteredInBothStates() {
        checkLongTitleInBothStates(query: "ままに", title: "〜ままに・〜られるままに・〜がままに")
    }

    func testLongTitleIkanDeWaStaysOneLineCenteredInBothStates() {
        checkLongTitleInBothStates(query: "いかんで", title: "〜いかんで（は）／〜いかんによっては")
    }

    func testLongTitleNdesuStaysOneLineCenteredInBothStates() {
        checkLongTitleInBothStates(query: "のです", title: "〜んです・〜のです・〜んだ")
    }

    func testFavoritedTagJoinsBarRow() {
        openDetailBySearch("にもかかわらず")
        id("detail.favorite").tap()
        wait(id("detail.favorited"), "收藏后标题下方应出现「已收藏」")
        app.swipeUp()
        app.swipeUp()
        let level = id("detail.level")
        let favorited = id("detail.favorited")
        wait(favorited, "收藏过的语法，往上滑后顶栏标签行里应有「已收藏」")
        XCTAssertEqual(ids("detail.favorited").count, 1, "「已收藏」只有一个")
        XCTAssertEqual(favorited.frame.midY, level.frame.midY, accuracy: 2, "已收藏和等级排在同一行")
        XCTAssertGreaterThan(favorited.frame.minX, level.frame.maxX, "已收藏排在等级后面")
        scrollToTop()
        id("detail.favorited").tap()
        app.buttons["取消收藏"].firstMatch.tap()
        wait(id("detail.favorite"), "取消收藏后右上角的收藏按钮回来")
    }

    func testDetailFeedbackLink() {
        openDetailBySearch("ように")
        let link = id("detail.feedback")
        scrollTo(link, maxSwipes: 40)
        XCTAssertTrue(id("detail.favorite").isHittable, "滑到页面底部后，右上角的收藏按钮仍应可点")
        link.tap()
        wait(navBar("反馈"), "讲解页底部的反馈入口应打开反馈页")
        navBar("反馈").buttons["取消"].tap()
        waitGone(navBar("反馈"), "取消后关闭")
        wait(detailScreen, "关闭反馈后仍在讲解页")
    }

    func testFavoriteHidesButtonAndUnfavoriteBySwipeInList() {
        openDetailBySearch("にもかかわらず")
        XCTAssertEqual(id("detail.favorite").label, "收藏", "没收藏时右上角是线条樱花，读作「收藏」")
        XCTAssertFalse(id("detail.favorited").exists, "没收藏时标题下不应有「已收藏」")
        id("detail.favorite").tap()
        waitGone(id("detail.favorite"), "收藏后右上角的收藏按钮应消失")
        wait(id("detail.favorited"), "收藏后标题下方应出现「已收藏」")
        XCTAssertFalse(id("favorite.toast").exists, "讲解页收藏时樱花飘进标签栏的「收藏」，不弹文字提示")
        tab("收藏").tap()
        let row = id("favorites.row")
        wait(row, "收藏后应出现在收藏页")
        row.swipeLeft()
        let unfavorite = app.buttons["取消收藏"].firstMatch
        wait(unfavorite, "在收藏页左滑一行应出现「取消收藏」")
        unfavorite.tap()
        wait(text(containing: "还没有收藏"), "左滑取消收藏后应为空")
        tab("搜索").tap()
        let field = app.searchFields.firstMatch
        wait(field, "搜索页应有搜索框")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "にもかかわらず")
        wait(id("search.result"), "搜索应有结果")
        id("search.result").tap()
        wait(id("detail.favorite"), "取消收藏后再打开讲解页，右上角的收藏按钮应重新出现")
        XCTAssertFalse(id("detail.favorited").exists, "取消收藏后「已收藏」应消失")
    }

    func testUnfavoriteFromFavoritedTagOnDetail() {
        openDetailBySearch("にもかかわらず")
        id("detail.favorite").tap()
        let tag = id("detail.favorited")
        wait(tag, "收藏后标题下方应出现「已收藏」")
        tag.tap()
        let confirm = app.buttons["取消收藏"].firstMatch
        wait(confirm, "点「已收藏」应弹出「取消收藏」")
        confirm.tap()
        waitGone(tag, "取消收藏后「已收藏」应消失")
        wait(id("detail.favorite"), "取消收藏后右上角的收藏按钮应重新出现")
        tab("收藏").tap()
        wait(text(containing: "还没有收藏"), "在讲解页取消收藏后收藏页应为空")
    }

    func testUnfavoritedGrammarKeepsButtonAndHasNoTag() {
        openDetailBySearch("にもかかわらず")
        wait(id("detail.favorite"), "讲解页右上角应有收藏按钮")
        XCTAssertFalse(id("detail.favorited").exists, "没收藏的语法不应显示「已收藏」")
        assertStays(id("detail.favorite"), "没点收藏时按钮应一直在")
    }
}

final class LibraryTests: E2ETestCase {
    func testLevelFilters() {
        tab("语法库").tap()
        for level in ["N5", "N4", "N3", "N2", "N1"] {
            app.buttons[level].firstMatch.tap()
            wait(id("library.row"), "筛选 \(level) 后应有语法点")
        }
        button(startingWith: "全部").tap()
        wait(id("library.row"), "全部")
    }

    func testLevelFilterStaysPinnedWhenScrolling() {
        tab("语法库").tap()
        let filter = id("library.levelFilter")
        wait(filter, "语法库应有等级筛选")
        let search = app.searchFields.firstMatch
        wait(search, "语法库应有搜索框")
        XCTAssertLessThanOrEqual(search.frame.maxY, filter.frame.minY + 1, "没滑动时搜索框和等级筛选不重叠：搜索框 \(search.frame)，筛选 \(filter.frame)")
        for _ in 0..<4 { app.swipeUp() }
        XCTAssertTrue(filter.isHittable, "往上滑后等级筛选应仍固定在顶部、可点")
        XCTAssertTrue(search.exists && app.windows.firstMatch.frame.contains(search.frame), "往上滑后搜索框也应固定在顶部")
        XCTAssertGreaterThan(filter.frame.minY, search.frame.minY, "等级筛选应在搜索框下面")
        XCTAssertLessThan(filter.frame.maxY, 260, "等级筛选应停在屏幕顶部")
        filter.buttons["N3"].tap()
        wait(id("library.row"), "滑到下面后点 N3 也应能筛选")
        XCTAssertTrue(filter.buttons["N3"].isSelected, "N3 应被选中")
    }

    func testLibrarySearchOpensDetail() {
        tab("语法库").tap()
        let field = app.searchFields.firstMatch
        wait(field, "语法库应有搜索框")
        field.tap()
        field.typeText("にもかかわらず")
        wait(id("library.row"), "应有搜索结果")
        id("library.row").tap()
        wait(detailScreen, "搜索结果应能打开讲解")
    }

    func testLibrarySearchNoResults() {
        tab("语法库").tap()
        let field = app.searchFields.firstMatch
        wait(field, "语法库应有搜索框")
        field.tap()
        field.typeText("zzqqxx")
        waitGone(id("library.row"), "无结果时不应列出语法点")
    }

    func testTabKeepsItsOwnPage() {
        tab("语法库").tap()
        wait(id("library.row"), "语法库列表")
        id("library.row").tap()
        wait(detailScreen, "讲解页")
        tab("首页").tap()
        wait(id("home.search"), "首页")
        tab("语法库").tap()
        wait(detailScreen, "切回语法库应仍停在讲解页")
        tab("语法库").tap()
        wait(id("library.row"), "再点一次语法库应回到列表")
    }
}

final class FavoritesTests: E2ETestCase {
    private func favoriteThreeFromLibrary() {
        tab("语法库").tap()
        let stars = ids("row.star")
        wait(stars.firstMatch, "语法库每行应有收藏星号")
        for i in 0..<3 { stars.element(boundBy: i).tap() }
        tab("收藏").tap()
        wait(id("favorites.row"), "收藏页应有内容")
        XCTAssertEqual(ids("favorites.row").count, 3)
    }

    func testSortMenuAllOptions() {
        favoriteThreeFromLibrary()
        for option in ["快遗忘了", "最多查看", "最近收藏"] {
            button(startingWith: "排序").tap()
            button(startingWith: option).tap()
            XCTAssertEqual(ids("favorites.row").count, 3, "按「\(option)」排序后条目数不变")
        }
    }

    func testSwipeToUnfavorite() {
        favoriteThreeFromLibrary()
        ids("favorites.row").firstMatch.swipeLeft()
        let unfavorite = app.buttons["取消收藏"].firstMatch
        wait(unfavorite, "左滑应出现「取消收藏」")
        XCTAssertFalse(app.buttons["删除"].exists, "左滑按钮应写「取消收藏」，不是「删除」")
        unfavorite.tap()
        let p = expectation(for: NSPredicate(format: "count == 2"), evaluatedWith: ids("favorites.row"))
        wait(for: [p], timeout: 8)
    }

    func testOpenDetailAndRetapTab() {
        favoriteThreeFromLibrary()
        id("favorites.row").tap()
        wait(detailScreen, "收藏页应能打开讲解")
        tab("收藏").tap()
        wait(id("favorites.row"), "再点收藏标签应回到列表")
    }
}

final class SearchTests: E2ETestCase {
    private var field: XCUIElement { app.searchFields.firstMatch }

    func testRecentViewsShownWhenEmpty() {
        tab("搜索").tap()
        wait(field, "搜索框")
        wait(id("search.result"), "没输入时应显示最近查看")
        id("search.result").tap()
        wait(detailScreen, "最近查看应能打开讲解")
    }

    func testNoResults() {
        tab("搜索").tap()
        wait(field, "搜索框")
        _ = waitForFocus(field)
        field.typeText("zzqqxx")
        waitGone(id("search.result"), "无结果时不应列出语法点")
    }

    func testFoundOnlyInExamples() {
        tab("搜索").tap()
        wait(field, "搜索框")
        _ = waitForFocus(field)
        field.typeText("観光客")
        wait(text(containing: "在例句中出现"), "只在例句里出现的词应显示「在例句中出现」")
        id("search.result").tap()
        wait(detailScreen, "应能打开讲解")
    }

    func testChineseMeaningSearch() {
        tab("搜索").tap()
        wait(field, "搜索框")
        _ = waitForFocus(field)
        field.typeText("尽管")
        wait(id("search.result"), "按中文意思搜索应有结果")
    }

    func testTapOutsideDismissesKeyboard() {
        tab("搜索").tap()
        wait(field, "搜索框")
        XCTAssertTrue(waitForFocus(field), "进入搜索页应弹出键盘")
        field.typeText("sstv")
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "sstv")).firstMatch.tap()
        waitGone(app.keyboards.firstMatch, "无结果时点空白处应收起键盘")
        XCTAssertEqual(field.value as? String, "sstv", "收起键盘后输入的文字应保留")

        field.tap()
        XCTAssertTrue(waitForFocus(field), "再点搜索框应重新弹出键盘")
        field.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + "ように")
        wait(id("search.result"), "应有结果")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).tap()
        waitGone(app.keyboards.firstMatch, "点空白处应收起键盘")
        id("search.result").tap()
        wait(detailScreen, "收起键盘后结果仍能打开讲解")
    }
}

final class SakuraAnimationTests: E2ETestCase {
    override var extraLaunchArguments: [String] { ["-playAnimations"] }

    func testReviewRowTappableWhileSakuraDrifts() {
        scrollToTop()
        let row = id("home.review")
        wait(row, "有到期的语法时应显示复习提醒")
        row.tap()
        wait(id("review.bar"), "樱花飘过时点复习提醒也应进入复习")
    }

    func testReviewReminderDoesNotReplayWhenComingBackToHome() {
        scrollToTop()
        let row = id("home.review")
        wait(row, "有到期的语法时应显示复习提醒")
        Thread.sleep(forTimeInterval: 2)
        row.tap()
        wait(id("review.bar"), "点复习提醒应进入复习")
        back()
        wait(row, "返回首页后仍有复习提醒")
        XCTAssertFalse(app.staticTexts["0 个语法可以复习了"].exists, "从别的页面返回首页不应再把数字从 0 滚一遍")
        XCTAssertTrue(text(containing: "个语法可以复习了").exists, "返回后直接显示数量")
    }

    func testFavoritesTabReachableWhenPouchTurnsPink() {
        openDetailBySearch("にもかかわらず")
        id("detail.favorite").tap()
        Thread.sleep(forTimeInterval: FlightTiming.pouchGlowStart)
        XCTAssertTrue(tab("收藏").exists, "樱花落进袋子、标签图标变粉时仍应找得到「收藏」标签")
        tab("收藏").tap()
        wait(id("favorites.row"), "标签图标变粉时点「收藏」应能打开收藏页")
    }

    func testFavoriteFlightDoesNotBlockTabs() {
        openDetailBySearch("にもかかわらず")
        id("detail.favorite").tap()
        tab("收藏").tap()
        wait(id("favorites.row"), "收藏后马上切到收藏页应能看到")
        id("row.star").tap()
        wait(text(containing: "还没有收藏"), "取消收藏后应为空")
    }
}

private enum FlightTiming {
    static let pouchGlowStart: TimeInterval = 2.9
}

final class DetailScrollTests: E2ETestCase {
    func testDetailScrollNeverJumpsBackWhileScrollingDown() {
        openDetailBySearch("だけ")
        let column = id("detail.titleColumn")
        wait(column, "讲解页应有标题")
        let feedback = id("detail.feedback")
        var positions = [column.frame.minY]
        for _ in 0..<40 where !(feedback.exists && feedback.isHittable) {
            app.swipeUp(velocity: .slow)
            positions.append(column.frame.minY)
        }
        let moves = zip(positions, positions.dropFirst()).map { $1 - $0 }
        XCTAssertTrue(feedback.exists && feedback.isHittable, "一直往下滑应能滑到底：\(positions)")
        XCTAssertTrue(moves.allSatisfy { $0 <= 1 }, "一直往下滑，页面不应往回跳：每次滑动后的标题位置 \(positions)")
        let bottom = feedback.frame.minY
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(feedback.frame.minY, bottom, accuracy: 1, "滑到底停住后不应往回弹")
    }
}
