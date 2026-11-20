import XCTest

/// 「快要忘了」复习（FSRS）：首页卡片 → 讲解页底部自评 → 下一个 / 先到这里 → 全部复习完卡片消失。
/// 端到端测试的固定数据里有 5 个 10 天前看过的语法（已到期：ni-mo-kakawarazu、you-ni-naru、okage-de、te-shimau、rashii-typical）
/// 和 5 个刚看过的（未到期）。
final class ReviewTests: E2ETestCase {
    private var card: XCUIElement { id("home.review") }

    /// 「下一个：〜X」按钮上写的下一个语法标题
    private func nextTitle() -> String {
        let label = id("review.next").label
        guard let r = label.range(of: "：") else { return label }
        return String(label[r.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    /// 复习页的状态：三个按钮都在、没有残留「已记录」、标签栏隐藏
    private func assertFreshReviewPage(_ step: String, file: StaticString = #filePath, line: UInt = #line) {
        wait(id("review.grade.1"), "\(step)：应显示自评按钮", file: file, line: line)
        XCTAssertTrue(id("review.grade.2").exists && id("review.grade.3").exists, "\(step)：三个按钮都应在", file: file, line: line)
        XCTAssertFalse(id("review.done").exists, "\(step)：不应残留上一个语法的「已记录」", file: file, line: line)
        XCTAssertFalse(tab("首页").isHittable, "\(step)：复习时底部标签栏应隐藏", file: file, line: line)
    }

    /// 回归（Build 16）：点「下一个」后没有重新出现三个按钮，而是带着上一个的「已记录」；页面停在上一页的滚动位置
    func testReviewNextThenStop() {
        scrollToTop()
        wait(card, "有到期的语法时首页应显示「快要忘了」卡片")
        XCTAssertTrue(text(containing: "有 5 个快要忘了").exists, "卡片标题应写出数量")
        id("home.review.start").tap()
        wait(detailScreen, "点「开始复习」应进入讲解页")
        wait(id("review.bar"), "复习时讲解页底部应有自评条")
        assertFreshReviewPage("第 1 个")

        id("review.grade.3").tap()
        wait(id("review.done"), "自评后应显示已记录")
        XCTAssertTrue(text(containing: "还剩 4 个要复习").exists, "应显示还剩几个")
        XCTAssertFalse(id("review.grade.1").exists, "自评后不再显示三个按钮")

        // 先往下滚一段，换到下一个后应从顶部开始
        app.swipeUp()
        let next = nextTitle()
        id("review.next").tap()
        assertFreshReviewPage("第 2 个")
        wait(id("detail.title"), "讲解页应有标题")
        XCTAssertEqual(id("detail.title").label, next, "「下一个」应打开 \(next)")
        XCTAssertTrue(id("detail.title").isHittable, "换到下一个后应从页面顶部开始，不停在上一页的滚动位置")

        id("review.grade.2").tap()
        wait(id("review.done"), "第 2 个自评后应显示已记录")
        XCTAssertTrue(text(containing: "还剩 3 个要复习").exists)
        wait(id("review.stop"), "还有要复习的时应有「先到这里」")
        id("review.stop").tap()

        wait(id("home.search"), "「先到这里」应回到首页")
        wait(card, "还有没复习的，卡片仍在")
        XCTAssertTrue(text(containing: "有 3 个快要忘了").waitForExistence(timeout: 5), "复习了 2 个，标题应变成 3 个")
        XCTAssertTrue(tab("首页").isHittable, "回到首页后标签栏应恢复")
    }

    /// 回归（Build 16）：把队列一路「下一个」走完，数字只减了 1（后面的根本没评上分）
    func testReviewAllHidesCard() {
        scrollToTop()
        wait(card, "首页应显示「快要忘了」卡片")
        id("home.review.start").tap()
        for i in 0..<5 {
            assertFreshReviewPage("第 \(i + 1) 个")
            id(["review.grade.1", "review.grade.2", "review.grade.3"][i % 3]).tap()
            wait(id("review.done"), "第 \(i + 1) 个自评后应显示已记录")
            if i < 4 {
                XCTAssertTrue(text(containing: "还剩 \(4 - i) 个要复习").exists, "第 \(i + 1) 个后应还剩 \(4 - i) 个")
                id("review.next").tap()
            }
        }
        wait(id("review.home"), "全部复习完应显示「回首页」")
        XCTAssertTrue(text(containing: "今天的复习都完成了").exists)
        id("review.home").tap()
        wait(id("home.search"), "应回到首页")
        waitGone(card, "5 个都评过分后「快要忘了」卡片应整块消失")
    }

    /// 每复习一个就回首页：数字每次刚好少 1
    func testCountDropsByOneEachTime() {
        for remaining in stride(from: 5, to: 2, by: -1) {
            scrollToTop()
            wait(card, "首页应显示「快要忘了」卡片")
            XCTAssertTrue(text(containing: "有 \(remaining) 个快要忘了").waitForExistence(timeout: 5), "应还有 \(remaining) 个")
            id("home.review.start").tap()
            assertFreshReviewPage("还剩 \(remaining) 个时")
            id("review.grade.3").tap()
            wait(id("review.stop"), "自评后应有「先到这里」")
            id("review.stop").tap()
            wait(id("home.search"), "应回到首页")
        }
        XCTAssertTrue(text(containing: "有 2 个快要忘了").waitForExistence(timeout: 5), "复习了 3 个，应剩 2 个")
    }

    /// 回归（Build 16）：从语法库点进一个到期的语法，底部也出现了复习栏。
    /// 复习栏只在从首页「快要忘了」进来时出现；语法库、搜索、扫描结果打开到期的语法都不出现，标签栏照常显示。
    func testDueGrammarFromOtherEntriesHasNoReviewBar() {
        // 搜索
        openDetailBySearch("にもかかわらず")
        XCTAssertFalse(id("review.bar").waitForExistence(timeout: 3), "从搜索打开到期的语法不应出现复习栏")

        // 语法库
        tab("语法库").tap()
        let field = app.searchFields.firstMatch
        wait(field, "语法库应有搜索框")
        field.tap()
        field.typeText("おかげで")
        wait(id("library.row"), "应有搜索结果")
        id("library.row").tap()
        wait(detailScreen, "应打开讲解")
        XCTAssertFalse(id("review.bar").waitForExistence(timeout: 3), "从语法库打开到期的语法不应出现复习栏")
        XCTAssertTrue(tab("语法库").isHittable, "不是复习时标签栏照常显示")

        // 扫描结果（固定数据里的扫描记录含 te-shimau，已到期）
        tab("首页").tap()
        scrollTo(id("scanRecord"))
        id("scanRecord").tap()
        waitForScanResult()
        let row = ids("result.grammarRow").matching(NSPredicate(format: "label CONTAINS %@", "てしまう")).firstMatch
        scrollTo(row)
        row.tap()
        wait(detailScreen, "扫描结果应能打开讲解")
        XCTAssertFalse(id("review.bar").waitForExistence(timeout: 3), "从扫描结果打开到期的语法不应出现复习栏")
    }

    func testNotDueGrammarHasNoReviewBar() {
        openDetailBySearch("ことにする")
        XCTAssertFalse(id("review.bar").waitForExistence(timeout: 3), "没到期的语法不应出现复习栏")
    }
}
