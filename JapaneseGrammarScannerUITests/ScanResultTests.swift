import XCTest

/// 识别结果页：高亮框、放大查看（按钮 / 双指 / 下滑关闭）、手动修正文字、扫描页相册
final class ScanResultTests: E2ETestCase {
    func testHighlightBoxOpensGrammarOrChooser() {
        openSampleFromHome()
        let box = id("highlight.box")
        wait(box, "示例书页上应有高亮框")
        box.tap()
        // 一个框里有多个语法点时先弹出选择
        let detail = detailScreen
        if !detail.waitForExistence(timeout: 4) {
            let options = app.buttons.matching(NSPredicate(format: "label CONTAINS '(N'"))
            XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 5), "点高亮框应打开讲解或弹出语法点选择")
            options.firstMatch.tap()
            wait(detail, "选择语法点后应进入讲解页")
        }
        back()
        waitForScanResult()
    }

    func testZoomButtonDoubleTapAndClose() {
        openSampleFromHome()
        id("result.zoomButton").tap()
        wait(id("zoom.close"), "点放大按钮应进入全屏")
        app.doubleTap()
        app.doubleTap()
        id("zoom.close").tap()
        waitGone(id("zoom.close"), "点关闭应退出全屏")
        wait(navBar("识别结果"), "退出全屏后回到识别结果页")
    }

    func testPinchOpensZoomAndPinchInCloses() {
        openSampleFromHome()
        id("result.image").pinch(withScale: 2.5, velocity: 2)
        wait(id("zoom.close"), "在结果页双指放大应进入全屏")
        app.pinch(withScale: 0.4, velocity: -2)
        waitGone(id("zoom.close"), "全屏时双指缩小应退回结果页")
    }

    func testSwipeDownClosesZoom() {
        openSampleFromHome()
        id("result.zoomButton").tap()
        wait(id("zoom.close"), "进入全屏")
        app.swipeDown(velocity: .fast)
        waitGone(id("zoom.close"), "全屏时向下滑应退回结果页")
    }

    func testEditTextAndReanalyze() {
        openSampleFromHome()
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
        openSampleFromHome()
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
        openSampleFromHome()
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

    /// 从识别结果进入讲解：顶部显示「你扫到的：…」，对应的用法高亮，点一下跳到该用法
    func testScannedMatchBannerOnDetail() {
        openSampleFromHome()
        let rows = ids("result.grammarRow")
        wait(rows.firstMatch, "应列出语法点")
        var found = false
        for i in 0..<min(rows.count, 6) {
            let row = rows.element(boundBy: i)
            scrollTo(row)
            row.tap()
            wait(detailScreen, "应进入讲解页")
            let banner = id("detail.scannedMatch")
            XCTAssertTrue(banner.waitForExistence(timeout: 5), "从识别结果进入的讲解页应显示扫到的原文")
            XCTAssertTrue(text(containing: "你扫到的").exists, "横幅应写明「你扫到的」")
            if id("detail.senseRow.matched").exists {
                found = true
                banner.tap()
                XCTAssertTrue(id("detail.senseRow.matched").waitForExistence(timeout: 3))
            }
            back()
            wait(navBar("识别结果"), "返回识别结果")
            if found { break }
        }
        XCTAssertTrue(found, "示例书页里至少有一个多用法语法点应定位到具体用法")
    }

    /// 从搜索进入的讲解页不显示「你扫到的」
    func testNoScannedBannerFromSearch() {
        openDetailBySearch("ようになる")
        XCTAssertFalse(id("detail.scannedMatch").waitForExistence(timeout: 2))
    }

    /// 一个框里有多个语法点时，选项后面附上各自命中的原文
    func testChooserOptionsShowMatchedText() {
        openSampleFromHome()
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
                app.buttons["取消"].firstMatch.tap()
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
