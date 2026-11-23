import XCTest

final class ScanResultTests: E2ETestCase {
    func testHighlightBoxOpensGrammarOrChooser() {
        openSamplePage()
        let box = id("highlight.box")
        wait(box, "示例书页上应有高亮框")
        box.tap()
        let detail = detailScreen
        if !detail.waitForExistence(timeout: 4) {
            let options = app.buttons.matching(NSPredicate(format: "label CONTAINS '(N'"))
            XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 5), "点高亮框应打开讲解或弹出语法点选择")
            options.firstMatch.tap()
            wait(detail, "选择语法点后应进入讲解页")
        }
        back()
        waitForScanResult()
        wait(id("highlight.box"), "返回后框仍在")
        XCTAssertFalse(id("highlight.box.selected").waitForExistence(timeout: 2), "返回后不应留有选中样式的框")
    }

    func testZoomButtonDoubleTapAndClose() {
        openSamplePage()
        id("result.zoomButton").tap()
        wait(id("zoom.close"), "点放大按钮应进入全屏")
        app.doubleTap()
        app.doubleTap()
        id("zoom.close").tap()
        waitGone(id("zoom.close"), "点关闭应退出全屏")
        wait(navBar("识别结果"), "退出全屏后回到识别结果页")
    }

    func testPinchOpensZoomAndPinchInCloses() {
        openSamplePage()
        id("result.image").pinch(withScale: 2.5, velocity: 2)
        wait(id("zoom.close"), "在结果页双指放大应进入全屏")
        app.pinch(withScale: 0.4, velocity: -2)
        waitGone(id("zoom.close"), "全屏时双指缩小应退回结果页")
    }

    func testSwipeDownClosesZoom() {
        openSamplePage()
        id("result.zoomButton").tap()
        wait(id("zoom.close"), "进入全屏")
        app.swipeDown(velocity: .fast)
        waitGone(id("zoom.close"), "全屏时向下滑应退回结果页")
    }

    func testEditTextAndReanalyze() {
        openSamplePage()
        scrollTo(id("result.editText"))
        id("result.editText").tap()
        let editor = id("result.editor")
        wait(editor, "应打开修正文字")
        editor.tap()
        editor.typeText("\n昨日は雨に降られてしまった。")
        app.buttons["重新识别"].tap()
        waitGone(editor, "重新识别后应关闭修正页")
        wait(text(containing: "文本已手动修改"), "应提示文本已手动修改")
        wait(id("result.grammarRow"), "重新识别后仍应列出语法点")
    }

    func testEditTextCancel() {
        openSamplePage()
        scrollTo(id("result.editText"))
        id("result.editText").tap()
        wait(id("result.editor"), "应打开修正文字")
        app.buttons["取消"].firstMatch.tap()
        waitGone(id("result.editor"), "取消后应关闭修正页")
        XCTAssertFalse(text(containing: "文本已手动修改").exists)
    }

    func testScanTabPhotoPicker() {
        tab("扫描").tap()
        wait(id("scan.photos"), "扫描页应有相册按钮")
        id("scan.photos").tap()
        pickFirstPhoto()
        wait(navBar("识别结果"), "扫描页从相册选图后应进入识别结果页", timeout: 30)
    }

    func testResultRowsAllOpenDetail() {
        openSamplePage()
        let rows = ids("result.grammarRow")
        let count = min(rows.count, 3)
        XCTAssertGreaterThan(count, 0)
        for i in 0..<count {
            let row = rows.element(boundBy: i)
            scrollTo(row)
            row.tap()
            wait(detailScreen, "识别结果第 \(i + 1) 个语法点应能打开")
            back()
            wait(navBar("识别结果"), "返回识别结果")
        }
    }

    func testScannedMatchBannerOnDetail() {
        openSamplePage()
        let rows = ids("result.grammarRow")
        wait(rows.firstMatch, "应列出语法点")
        var found = false
        var bannerCount = 0
        for i in 0..<rows.count {
            let row = rows.element(boundBy: i)
            scrollTo(row)
            row.tap()
            wait(detailScreen, "应进入讲解页")
            let banner = id("detail.scannedMatch")
            if banner.waitForExistence(timeout: 4) {
                bannerCount += 1
                XCTAssertTrue(text(containing: "你扫到的").exists, "横幅应写明「你扫到的」")
                if id("detail.senseRow.matched").exists {
                    found = true
                    banner.tap()
                    XCTAssertTrue(detailScreen.waitForExistence(timeout: 3), "跳转后仍在讲解页")
                }
            }
            back()
            wait(navBar("识别结果"), "返回识别结果")
            if found { break }
        }
        XCTAssertGreaterThan(bannerCount, 0, "从识别结果进入的讲解页应显示扫到的原文")
        XCTAssertTrue(found, "示例书页里至少有一个多用法语法点应定位到具体用法")
    }

    func testNoScannedBannerFromSearch() {
        openDetailBySearch("ようになる")
        XCTAssertFalse(id("detail.scannedMatch").waitForExistence(timeout: 2))
    }

    func testChooserOptionsShowMatchedText() {
        openSamplePage()
        let boxes = ids("highlight.box")
        wait(boxes.firstMatch, "示例书页上应有高亮框")
        let options = app.buttons.matching(NSPredicate(format: "label CONTAINS '(N'"))
        var sawChooser = false
        for i in 0..<min(boxes.count, 40) {
            let box = boxes.element(boundBy: i)
            guard box.isHittable else { continue }
            box.tap()
            if options.firstMatch.waitForExistence(timeout: 2) {
                sawChooser = true
                for j in 0..<options.count {
                    XCTAssertTrue(options.element(boundBy: j).label.contains("「"), "选项应附上命中的原文：\(options.element(boundBy: j).label)")
                }
                break
            }
            if detailScreen.waitForExistence(timeout: 2) {
                back()
                waitForScanResult()
            }
        }
        if !sawChooser {
            print("示例书页上没有多语法点的框，跳过选项检查")
        }
    }
}
