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

    func testZoomButtonOpensAndCloses() {
        openSamplePage()
        id("result.zoomButton").tap()
        wait(id("zoom.close"), "点放大按钮应进入全屏")
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
        waitForScanFlow()
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

final class LineSelectFlowTests: E2ETestCase {
    private func openSampleForSelection() {
        tab("扫描").tap()
        wait(id("scan.trySample"), "扫描页应有「试试示例」")
        id("scan.trySample").tap()
        waitForLineSelection()
    }

    private func row(containing text: String) -> XCUIElement {
        ids("result.grammarRow").matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func headline() -> String {
        id("result.headline").label
    }

    private func analyzeOnlyLine(containing text: String) {
        openSampleForSelection()
        tapLine(containing: text)
        wait(row(containing: text), "点一行后应马上列出这一行的语法")
    }

    private func holdAndDrag(from: String, to: String) {
        let start = selectLine(containing: from), end = selectLine(containing: to)
        start.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
            .press(forDuration: 0.6, thenDragTo: end.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)))
    }

    func testScanTabOnlyFramesWithoutRecognizing() {
        tab("扫描").tap()
        wait(id("scan.hint"), "扫描页应提示按快门拍照")
        XCTAssertTrue(id("scan.hint").label.contains("按快门"), "提示应说明先拍下来：\(id("scan.hint").label)")
        let hint = id("scan.hint").frame
        let shutter = id("scan.shutter").frame
        XCTAssertEqual(ids("scan.trySample").count, 1, "扫描页只有一个「试试示例」，在快门上方的提示里")
        let sample = id("scan.trySample").frame
        XCTAssertLessThanOrEqual(hint.maxY, shutter.minY, "提示应在快门上方：提示 \(hint)，快门 \(shutter)")
        XCTAssertLessThan(shutter.minY - hint.maxY, shutter.height, "提示应紧挨快门，不应留在取景框顶部：提示 \(hint)，快门 \(shutter)")
        XCTAssertLessThan(abs(sample.midY - hint.midY), hint.height, "「试试示例」应和提示在同一行：示例 \(sample)，提示 \(hint)")
        XCTAssertFalse(id("highlight.box").exists, "取景时不应有语法框")
    }

    func testPhotoShowsLinesWithoutGrammarBoxesBeforeAnalyzing() {
        openSampleForSelection()

        XCTAssertTrue(navBar("识别结果").exists, "拍完直接在识别结果页上选，不再有单独的选行页")
        XCTAssertGreaterThan(ids("result.line").count, 5, "示例书页应认出多行文字")
        XCTAssertFalse(id("highlight.box").exists, "选行之前照片上不应有语法框")
        XCTAssertFalse(id("result.grammarRow").exists, "选行之前不应列出语法点")
        XCTAssertFalse(id("select.analyzeSelected").exists, "不再有「分析这 N 行」按钮")
    }

    func testAnalyzeAllButtonSitsOnThePhotoCorner() {
        openSampleForSelection()

        let photo = id("result.image").frame, button = id("result.analyzeAll").frame
        XCTAssertTrue(photo.contains(button), "「分析整页」应在照片上：照片 \(photo)，按钮 \(button)")
        XCTAssertLessThan(button.midX, photo.midX, "「分析整页」应在照片左边：照片 \(photo)，按钮 \(button)")
        XCTAssertGreaterThan(button.midY, photo.midY, "「分析整页」应在照片下边：照片 \(photo)，按钮 \(button)")
    }

    func testTapOneLineAnalyzesItRightAway() {
        openSampleForSelection()
        let before = selectLine(containing: "ながら").frame

        tapLine(containing: "ながら")

        wait(row(containing: "ながら"), "点一行后不用再点按钮，这一行的「ながら」应马上列出来")
        XCTAssertTrue(headline().contains("这一行有"), "标题应说明只看这一行：\(headline())")
        XCTAssertEqual(ids("result.line.selected").count, 1, "照片上应只框出这一行")
        XCTAssertEqual(id("result.line.selected").frame.minY, before.minY, accuracy: 1, "选中后照片不能挪动")
        XCTAssertFalse(row(containing: "らしい").exists, "最后一行的「らしい」不在选中的行里，不应列出")
        XCTAssertTrue(id("highlight.box").exists, "选中的行里的语法点应马上框出来")
    }

    func testHoldAndDragSelectsSeveralWholeLines() {
        openSampleForSelection()

        holdAndDrag(from: "おかげで", to: "と思う")

        wait(row(containing: "おかげで"), "拖过的几行里的「おかげで」应列出来")
        XCTAssertTrue(headline().contains("这 3 行有"), "标题应写明 3 行：\(headline())")
        XCTAssertEqual(ids("result.line.selected").count, 3, "从「おかげで」那行拖到「と思う」那行，应选中整整 3 行")
        XCTAssertFalse(row(containing: "ながら").exists, "没拖到的行里的「ながら」不应列出")
    }

    func testQuickDragWithoutHoldingSelectsNothing() {
        openSampleForSelection()
        let start = selectLine(containing: "おかげで"), end = selectLine(containing: "と思う")

        start.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: end.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)))

        XCTAssertFalse(id("result.grammarRow").waitForExistence(timeout: 2), "没按住就拖，是滚动页面，不应选行、不应分析")
        XCTAssertFalse(id("result.line.selected").exists)
        XCTAssertTrue(id("result.chooseHint").exists, "仍停在选行提示")
    }

    func testTapAnotherLineOnResultSwitchesToThatLine() {
        analyzeOnlyLine(containing: "ながら")
        XCTAssertFalse(row(containing: "らしい").exists, "还没改选时不应有最后一行的「らしい」")

        tapLine(containing: "らしい")

        wait(row(containing: "らしい"), "点照片上最后一行后应改看那一行")
        XCTAssertTrue(headline().contains("这一行有"), "标题：\(headline())")
        XCTAssertFalse(row(containing: "ながら").exists, "改选后原来那行的「ながら」不应再列出")
        XCTAssertEqual(ids("result.line.selected").count, 1, "照片上应只框出新选的这一行")
    }

    func testTapSameLineOnResultKeepsResult() {
        analyzeOnlyLine(containing: "ながら")
        let before = ids("result.grammarRow").count

        tapLine(containing: "ながら")

        XCTAssertTrue(row(containing: "ながら").waitForExistence(timeout: 2))
        XCTAssertEqual(ids("result.grammarRow").count, before, "点已经选中的那一行，结果不变")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS '(N'")).firstMatch.exists, "点行首不应打开语法选择")
    }

    func testHoldAndDragOnResultChangesTheLines() {
        analyzeOnlyLine(containing: "ながら")

        holdAndDrag(from: "おかげで", to: "と思う")

        wait(row(containing: "おかげで"), "拖过的几行里的「おかげで」应列出来")
        XCTAssertTrue(headline().contains("这 3 行有"), "标题应写明 3 行：\(headline())")
        XCTAssertFalse(row(containing: "ながら").exists, "没拖到的行里的「ながら」不应列出")
    }

    func testAnalyzeAllBeforeChoosingShowsWholePage() {
        openSampleForSelection()

        id("result.analyzeAll").tap()

        wait(row(containing: "らしい"), "分析整页应列出最后一行的「らしい」")
        XCTAssertTrue(headline().contains("整页有"), "整页标题：\(headline())")
        waitGone(id("result.analyzeAll"), "已经是整页时不再显示「分析整页」")
        XCTAssertFalse(id("result.line.selected").exists, "整页时不框出某几行")
    }

    func testAnalyzeAllAfterChoosingShowsWholePage() {
        analyzeOnlyLine(containing: "ながら")

        id("result.analyzeAll").tap()

        wait(row(containing: "らしい"), "分析整页应列出最后一行的「らしい」")
        XCTAssertTrue(headline().contains("整页有"), "整页标题：\(headline())")
        waitGone(id("result.analyzeAll"), "已经是整页时不再显示「分析整页」")
    }

    func testZoomedPhotoCanSwitchLine() {
        analyzeOnlyLine(containing: "ながら")
        id("result.zoomButton").tap()
        wait(id("zoom.close"), "进入全屏")

        tapLine(containing: "らしい")
        id("zoom.close").tap()
        waitGone(id("zoom.close"), "退出全屏")

        wait(row(containing: "らしい"), "全屏里点最后一行后，结果应改成那一行")
        XCTAssertFalse(row(containing: "ながら").exists, "改选后原来那行的「ながら」不应再列出")
    }

    func testZoomedPhotoHasAnalyzeAllAtTopLeftAndOneHint() {
        openSampleForSelection()
        id("result.zoomButton").tap()
        wait(id("zoom.close"), "进入全屏")

        let all = id("zoom.analyzeAll"), close = id("zoom.close")
        wait(all, "全屏里应有「分析整页」")
        XCTAssertLessThan(all.frame.midX, close.frame.midX, "「分析整页」在左上，关闭在右上")
        XCTAssertEqual(all.frame.midY, close.frame.midY, accuracy: 2, "「分析整页」和关闭在同一行")
        XCTAssertEqual(ids("zoom.hint").count, 1, "底部只有一行提示")

        all.tap()
        waitGone(all, "分析整页后全屏里不再显示「分析整页」")
        close.tap()
        wait(row(containing: "らしい"), "全屏里分析整页后，结果页列出整页的语法")
    }

    func testDraggingZoomedPhotoUpKeepsOneCloseButtonAndOneHint() {
        analyzeOnlyLine(containing: "ながら")
        id("result.zoomButton").tap()
        wait(id("zoom.close"), "进入全屏")
        tapLine(containing: "らしい")
        wait(row(containing: "らしい"), "全屏里点最后一行后结果改成那一行")

        let from = selectLine(containing: "らしい").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -80)))

        wait(id("zoom.close"), "往上拖一小段不应退出全屏")
        XCTAssertEqual(ids("zoom.close").count, 1, "全屏里只应有一个关闭按钮")
        XCTAssertEqual(ids("zoom.hint").count, 1, "全屏里只应有一行提示")
    }
}
