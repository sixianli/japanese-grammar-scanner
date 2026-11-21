import XCTest

/// 讲解页：义项跳转、相近语法、反馈入口、收藏
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
        let similar = id("detail.similar")
        scrollTo(similar, maxSwipes: 25)
        XCTAssertTrue(similar.exists, "讲解页应有相近语法")
        similar.tap()
        wait(detailScreen, "点相近语法应打开另一个讲解页")
        back()
        wait(detailScreen, "返回应回到原来的讲解页")
        back()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 8), "再返回应回到搜索页")
    }

    /// 新版相近语法：默认收起只显示差别；点「看例句对比」展开例句和「怎么分辨」，再点收起；点语法名跳到对方讲解页
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

        let similar = id("detail.similar")
        scrollTo(similar)
        similar.tap()
        wait(detailScreen, "点相近语法的语法名应进入对方的讲解页")
        back()
        wait(id("detail.contrast.toggle"), "返回后应回到原来的讲解页")
    }

    /// Build 17 反馈 1：往上滑后，标题栏正中出现同一个标题和等级；回到顶部后标题栏里的标题藏起来
    func testTitleBarShowsCenteredTitleAfterScrolling() {
        openDetailBySearch("ようになる")
        let pageTitle = id("detail.title")
        wait(pageTitle, "讲解页顶部应有标题")
        let title = pageTitle.label
        let barTitle = id("detail.barTitle")
        XCTAssertFalse(barTitle.exists, "没滚动时标题栏里不应显示标题（页面上已经有大标题）")

        app.swipeUp()
        app.swipeUp()
        wait(barTitle, "往上滑后标题栏应显示标题")
        XCTAssertEqual(barTitle.label, title, "标题栏显示的应是本页语法的完整标题")
        let screen = app.windows.firstMatch.frame
        XCTAssertEqual(barTitle.frame.midX, screen.midX, accuracy: 2, "标题应在屏幕水平正中")
        XCTAssertLessThan(barTitle.frame.maxY, 200, "标题应在屏幕顶部的标题栏里")
        let level = id("detail.barLevel")
        XCTAssertTrue(level.exists, "标题栏里标题下方应有等级")
        XCTAssertTrue(level.label.hasPrefix("JLPT N"), "等级应写成「JLPT N…」")
        XCTAssertGreaterThan(level.frame.minY, barTitle.frame.minY, "等级应在标题下方")
        XCTAssertEqual(level.frame.midX, screen.midX, accuracy: 2, "等级应居中")

        scrollToTop()
        XCTAssertTrue(pageTitle.isHittable, "回到顶部后页面大标题可见")
        waitGone(barTitle, "回到顶部后标题栏里的标题应藏起来")
    }

    func testDetailFeedbackLink() {
        openDetailBySearch("ように")
        let link = id("detail.feedback")
        scrollTo(link, maxSwipes: 40)
        link.tap()
        wait(navBar("反馈"), "讲解页底部的反馈入口应打开反馈页")
        navBar("反馈").buttons["取消"].tap()
        waitGone(navBar("反馈"), "取消后关闭")
        XCTAssertTrue(detailScreen.exists, "关闭反馈后仍在讲解页")
    }

    func testFavoriteFromDetailAndUnfavoriteFromList() {
        openDetailBySearch("にもかかわらず")
        id("detail.favorite").tap()
        tab("收藏").tap()
        wait(id("favorites.row"), "收藏后应出现在收藏页")
        id("row.star").tap()
        wait(text(containing: "还没有收藏"), "在列表里点星号取消收藏后应为空")
    }
}

/// 语法库：等级筛选、搜索、例句中出现、无结果
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

/// 收藏：排序、左滑删除、打开讲解、再次点标签回到列表
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

    func testSwipeToDelete() {
        favoriteThreeFromLibrary()
        ids("favorites.row").firstMatch.swipeLeft()
        let delete = app.buttons.matching(NSPredicate(format: "label == '删除' OR label == 'Delete'")).firstMatch
        wait(delete, "左滑应出现删除")
        delete.tap()
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

/// 搜索：最近查看、无结果、例句中出现、中文意思搜索
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

    /// 输入后点键盘以外的空白处，键盘收起，输入的文字保留（无结果和有结果两种页面）
    func testTapOutsideDismissesKeyboard() {
        tab("搜索").tap()
        wait(field, "搜索框")
        XCTAssertTrue(waitForFocus(field), "进入搜索页应弹出键盘")
        field.typeText("sstv")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        waitGone(app.keyboards.firstMatch, "无结果时点空白处应收起键盘")
        XCTAssertEqual(field.value as? String, "sstv", "收起键盘后输入的文字应保留")

        field.tap()
        XCTAssertTrue(waitForFocus(field), "再点搜索框应重新弹出键盘")
        // 有结果时：点结果以外的空白处也收起键盘，结果仍可点开
        field.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + "ように")
        wait(id("search.result"), "应有结果")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).tap()
        waitGone(app.keyboards.firstMatch, "点空白处应收起键盘")
        id("search.result").tap()
        wait(detailScreen, "收起键盘后结果仍能打开讲解")
    }
}
