import XCTest

/// 识别结果页：高亮框、放大查看（按钮 / 双指 / 下滑关闭）、手动修正文字、扫描页相册
final class ScanResultTests: E2ETestCase {
    func testHighlightBoxOpensGrammarOrChooser() {
        openSampleFromHome()
        let box = id("highlight.box")
        wait(box, "示例书页上应有高亮框")
        box.tap()
        // 一个框里有多个语法点时先弹出选择
        let detail = id("screen.grammarDetail")
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
            wait(id("screen.grammarDetail"), "识别结果第 \(i + 1) 个语法点应能打开")
            back()
            wait(navBar("识别结果"), "返回识别结果")
        }
    }
}
