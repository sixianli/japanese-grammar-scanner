import XCTest

/// 讲解页：义项跳转、相近语法、反馈入口、收藏
final class DetailTests: E2ETestCase {
    func testSenseRowsJumpWithinPage() {
        openDetailBySearch("ように")
        let rows = ids("detail.senseRow")
        wait(rows.firstMatch, "讲解页应列出义项")
        rows.element(boundBy: min(1, rows.count - 1)).tap()
        XCTAssertTrue(id("screen.grammarDetail").exists, "点义项应在本页内跳转，不离开讲解页")
    }

    func testSimilarGrammarPushesAndBackReturns() {
        openDetailBySearch("だけに")
        let similar = id("detail.similar")
        scrollTo(similar, maxSwipes: 25)
        XCTAssertTrue(similar.exists, "讲解页应有相近语法")
        similar.tap()
        wait(id("screen.grammarDetail"), "点相近语法应打开另一个讲解页")
        back()
        wait(id("screen.grammarDetail"), "返回应回到原来的讲解页")
        back()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 8), "再返回应回到搜索页")
    }

    func testDetailFeedbackLink() {
        openDetailBySearch("ように")
        let link = id("detail.feedback")
        scrollTo(link, maxSwipes: 40)
        link.tap()
        wait(navBar("反馈"), "讲解页底部的反馈入口应打开反馈页")
        navBar("反馈").buttons["取消"].tap()
        waitGone(navBar("反馈"), "取消后关闭")
        XCTAssertTrue(id("screen.grammarDetail").exists, "关闭反馈后仍在讲解页")
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
        wait(id("screen.grammarDetail"), "搜索结果应能打开讲解")
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
        wait(id("screen.grammarDetail"), "讲解页")
        tab("首页").tap()
        wait(id("home.search"), "首页")
        tab("语法库").tap()
        wait(id("screen.grammarDetail"), "切回语法库应仍停在讲解页")
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
        wait(id("screen.grammarDetail"), "收藏页应能打开讲解")
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
        wait(id("screen.grammarDetail"), "最近查看应能打开讲解")
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
        wait(id("screen.grammarDetail"), "应能打开讲解")
    }

    func testChineseMeaningSearch() {
        tab("搜索").tap()
        wait(field, "搜索框")
        _ = waitForFocus(field)
        field.typeText("尽管")
        wait(id("search.result"), "按中文意思搜索应有结果")
    }
}
