import XCTest

/// 「快要忘了」复习（FSRS）：首页卡片 → 讲解页底部自评 → 下一个 / 先到这里 → 全部复习完卡片消失。
/// 端到端测试的固定数据里有 5 个 10 天前看过的语法（已到期）和 5 个刚看过的（未到期）。
final class ReviewTests: E2ETestCase {
    private var card: XCUIElement { id("home.review") }

    func testReviewNextThenStop() {
        scrollToTop()
        wait(card, "有到期的语法时首页应显示「快要忘了」卡片")
        XCTAssertTrue(text(containing: "有 5 个快要忘了").exists, "卡片标题应写出数量")
        id("home.review.start").tap()
        wait(detailScreen, "点「开始复习」应进入讲解页")
        wait(id("review.bar"), "复习时讲解页底部应有自评条")

        id("review.grade.3").tap()
        wait(id("review.done"), "自评后应显示已记录")
        XCTAssertTrue(text(containing: "还剩 4 个要复习").exists, "应显示还剩几个")
        XCTAssertFalse(id("review.grade.1").exists, "自评后不再显示三个按钮")

        id("review.next").tap()
        wait(id("review.grade.1"), "「下一个」应打开下一条，并重新显示自评按钮")
        id("review.grade.2").tap()
        wait(id("review.stop"), "还有要复习的时应有「先到这里」")
        id("review.stop").tap()

        wait(id("home.search"), "「先到这里」应回到首页")
        wait(card, "还有没复习的，卡片仍在")
        XCTAssertTrue(text(containing: "有 3 个快要忘了").waitForExistence(timeout: 5), "复习了 2 个，标题应变成 3 个")
    }

    func testReviewAllHidesCard() {
        scrollToTop()
        wait(card, "首页应显示「快要忘了」卡片")
        id("home.review.start").tap()
        for i in 0..<5 {
            wait(id("review.grade.1"), "第 \(i + 1) 个应显示自评按钮")
            id(["review.grade.1", "review.grade.2", "review.grade.3"][i % 3]).tap()
            if i < 4 {
                wait(id("review.next"), "第 \(i + 1) 个自评后应有「下一个」")
                id("review.next").tap()
            }
        }
        wait(id("review.home"), "全部复习完应显示「回首页」")
        XCTAssertTrue(text(containing: "今天的复习都完成了").exists)
        id("review.home").tap()
        wait(id("home.search"), "应回到首页")
        waitGone(card, "全部复习完后「快要忘了」卡片应整块消失")
    }

    /// 单独打开一个到期的语法：底部也有自评条，但没有「下一个」；没到期的语法不显示自评条
    func testDueGrammarOpenedDirectly() {
        openDetailBySearch("にもかかわらず")
        wait(id("review.bar"), "打开一个到期的语法时应出现自评条")
        id("review.grade.3").tap()
        wait(id("review.done"), "自评后应显示已记录")
        XCTAssertFalse(id("review.next").exists, "不是从「快要忘了」进来的，没有「下一个」")
        XCTAssertFalse(id("review.home").exists)
    }

    func testNotDueGrammarHasNoReviewBar() {
        openDetailBySearch("ことにする")
        XCTAssertFalse(id("review.bar").waitForExistence(timeout: 3), "没到期的语法不应出现自评条")
    }
}
