import XCTest

final class ReviewTests: E2ETestCase {
    private var card: XCUIElement { id("home.review") }

    private func nextTitle() -> String {
        let label = id("review.next").label
        guard let r = label.range(of: "：") else { return label }
        return String(label[r.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    private func assertFreshReviewPage(_ step: String, file: StaticString = #filePath, line: UInt = #line) {
        wait(id("review.grade.1"), "\(step)：应显示自评按钮", file: file, line: line)
        XCTAssertTrue(id("review.grade.2").exists && id("review.grade.3").exists, "\(step)：三个按钮都应在", file: file, line: line)
        XCTAssertFalse(id("review.done").exists, "\(step)：不应残留上一个语法的「已记录」", file: file, line: line)
        XCTAssertFalse(tab("首页").isHittable, "\(step)：复习时底部标签栏应隐藏", file: file, line: line)
    }

    func testReviewReminderIsOneQuietRow() {
        scrollToTop()
        wait(card, "有到期的语法时首页应显示复习提醒")
        XCTAssertTrue(text(containing: "5 个语法可以复习了").exists, "提醒里应写出数量")
        XCTAssertLessThan(card.frame.height, 80, "复习提醒应只占一行")
        XCTAssertFalse(id("home.review.start").exists, "不再有「开始复习」大按钮")
        XCTAssertFalse(id("home.review.row").exists, "不再列出要复习的语法")
    }

    func testReviewReminderTextIsCenteredInTheCard() {
        scrollToTop()
        wait(card, "有到期的语法时首页应显示复习提醒")
        let number = id("home.review.count"), words = id("home.review.text")
        wait(number, "提醒里应有数字")

        XCTAssertEqual(number.frame.midY, card.frame.midY, accuracy: 1, "数字应在卡片正中：数字 \(number.frame)，卡片 \(card.frame)")
        XCTAssertEqual(words.frame.midY, card.frame.midY, accuracy: 1, "「个语法可以复习了」应在卡片正中，不往下沉：文字 \(words.frame)，卡片 \(card.frame)")
    }

    func testReviewReminderHasCaptionBelow() {
        scrollToTop()
        wait(card, "有到期的语法时首页应显示复习提醒")
        let caption = id("home.review.caption")

        wait(caption, "复习提醒下面应有一行说明")
        XCTAssertTrue(caption.label.contains("遗忘曲线"), "说明应讲提醒是怎么来的：\(caption.label)")
        XCTAssertGreaterThanOrEqual(caption.frame.minY, card.frame.maxY, "说明在卡片下面")
    }

    func testFavoriteDuringReviewHidesButtonAndConfirms() {
        scrollToTop()
        wait(card, "有到期的语法时首页应显示复习提醒")
        card.tap()
        wait(id("review.bar"), "复习时讲解页底部应有自评条")
        XCTAssertFalse(id("favorite.toast").exists, "还没收藏时不应有提示")
        id("detail.favorite").tap()
        let toast = id("favorite.toast")
        wait(toast, "复习页收藏后顶部应提示「已收进收藏」", timeout: 5)
        XCTAssertTrue(toast.label.contains("已收进收藏"), "提示文字应是「已收进收藏」：\(toast.label)")
        waitGone(id("detail.favorite"), "复习页收藏后右上角的收藏按钮应消失")
        wait(id("detail.favorited"), "复习页收藏后标题下方应出现「已收藏」")
        waitGone(toast, "提示过一会儿应自动消失", timeout: 8)
        XCTAssertTrue(id("review.grade.1").exists, "收藏不影响下面的自评按钮")
    }

    func testReviewNextThenStop() {
        scrollToTop()
        wait(card, "有到期的语法时首页应显示复习提醒")
        XCTAssertTrue(text(containing: "5 个语法可以复习了").exists, "提醒里应写出数量")
        card.tap()
        wait(detailScreen, "点复习提醒应进入讲解页")
        wait(id("review.bar"), "复习时讲解页底部应有自评条")
        assertFreshReviewPage("第 1 个")

        id("review.grade.3").tap()
        wait(id("review.done"), "自评后应显示已记录")
        XCTAssertTrue(text(containing: "还剩 4 个要复习").exists, "应显示还剩几个")
        XCTAssertFalse(id("review.grade.1").exists, "自评后不再显示三个按钮")

        app.swipeUp()
        let next = nextTitle()
        XCTAssertTrue(id("review.done").label.contains("下一个：\(next)"), "下一个语法名应写在「还剩几个」那行：\(id("review.done").label)")
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
        wait(card, "还有没复习的，提醒仍在")
        XCTAssertTrue(text(containing: "3 个语法可以复习了").waitForExistence(timeout: 5), "复习了 2 个，标题应变成 3 个")
        XCTAssertTrue(tab("首页").isHittable, "回到首页后标签栏应恢复")
    }

    func testReviewAllHidesCard() {
        scrollToTop()
        wait(card, "首页应显示复习提醒")
        card.tap()
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
        waitGone(card, "5 个都评过分后复习提醒应整块消失")
    }

    func testCountDropsByOneEachTime() {
        for remaining in stride(from: 5, to: 2, by: -1) {
            scrollToTop()
            wait(card, "首页应显示复习提醒")
            XCTAssertTrue(text(containing: "\(remaining) 个语法可以复习了").waitForExistence(timeout: 5), "应还有 \(remaining) 个")
            card.tap()
            assertFreshReviewPage("还剩 \(remaining) 个时")
            id("review.grade.3").tap()
            wait(id("review.stop"), "自评后应有「先到这里」")
            id("review.stop").tap()
            wait(id("home.search"), "应回到首页")
        }
        XCTAssertTrue(text(containing: "2 个语法可以复习了").waitForExistence(timeout: 5), "复习了 3 个，应剩 2 个")
    }

    func testDueGrammarFromOtherEntriesHasNoReviewBar() {
        openDetailBySearch("にもかかわらず")
        XCTAssertFalse(id("review.bar").waitForExistence(timeout: 3), "从搜索打开到期的语法不应出现复习栏")

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

        tab("首页").tap()
        wait(id("home.search"), "点「首页」标签应回到首页")
        scrollTo(id("home.continueScan"))
        id("home.continueScan").tap()
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
