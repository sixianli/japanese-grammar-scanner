import SwiftUI

/// 对一张图片（相机定格或相册）做高精度识别，把所有语法点在图片和文本中高亮，供用户选择查看。
struct ScanResultView: View {
    let scanImage: ScanImage

    @EnvironmentObject private var library: GrammarLibrary
    @EnvironmentObject private var history: HistoryStore
    @Environment(\.pushRoute) private var pushRoute
    @State private var recordID: UUID?
    @State private var phase: Phase = .loading
    @State private var tappedCluster: HighlightCluster?
    @State private var selectedClusterID: Int?
    @State private var pushedGrammarID: String?
    @State private var isEditing = false
    @State private var draftText = ""
    @State private var textWasEdited = false
    /// 放大查看（手势中的缩放、位置都在这个模型里，结果页本身不随手势重绘）
    @State private var zoom = ScanZoomModel()
    /// 照片里笔画的分布（荧光笔样式把语法所在的字染成主题色时用）
    @State private var ink: CGImage?

    enum Phase {
        case loading
        case done(ScanResult)
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                imageSection
                    .zIndex(1)
                switch phase {
                case .loading:
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(localized: "正在识别文字和语法点…")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                case .failed(let message):
                    ContentUnavailableView(tr("识别失败"), systemImage: "exclamationmark.triangle", description: Text(message))
                case .done(let result):
                    resultSections(result)
                }
            }
            .padding()
        }
        .background(Theme.background)
        // 记录全屏覆盖层的位置（放大的终点）
        .overlay {
            GeometryReader { g in
                Color.clear
                    .onAppear { zoom.container = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, f in zoom.container = f }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .overlay { zoomStage }
        .toolbar(zoom.isOpen ? .hidden : .automatic, for: .navigationBar, .tabBar)
        .statusBarHidden(zoom.isOpen)
        .onAppear { zoom.imageSize = scanImage.image.size }
        .navigationTitle(tr("识别结果"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $pushedGrammarID) { id in
            GrammarDetailView(grammarID: id)
        }
        .grammarChooser(cluster: $tappedCluster, library: library) { id, matched in
            if let pushRoute { pushRoute(.grammarMatch(id, matched ?? "")) } else { pushedGrammarID = id }
        }
        .sheet(isPresented: $isEditing) { editSheet }
        .task { await analyze() }
    }

    private var isDone: Bool {
        if case .done = phase { return true }
        return false
    }

    // MARK: - 图片 + 高亮框

    private var imageSection: some View {
        Image(uiImage: scanImage.image)
            .resizable()
            .scaledToFit()
            .overlay {
                if case .done(let result) = phase, !textWasEdited {
                    HighlightOverlay(
                        result: result,
                        imageSize: scanImage.image.size,
                        fit: .fit,
                        library: library,
                        selectedClusterID: selectedClusterID,
                        style: .marker(ink: ink)
                    ) { cluster in
                        selectedClusterID = cluster.id
                        tappedCluster = cluster
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) {
                Button { zoom.open() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.5), in: Circle())
                        .padding(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(localized: "放大查看"))
                .accessibilityIdentifier("result.zoomButton")
            }
            .contentShape(Rectangle())
            .onTapGesture { zoom.open() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("result.image")
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 460)
            // 记录图片在屏幕上的位置：放大从这里开始，缩小回到这里（不触发重绘）
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { zoom.sourceFrame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, f in zoom.sourceFrame = f }
            })
            // 放大时原位置的图片隐藏，由覆盖层接管
            .opacity(zoom.presented ? 0.001 : 1)
            // 直接在结果页双指放大：以两指中点为中心、按手指分开的比例实时放大，松手后铺满全屏
            .scanPinch(
                began: { zoom.pinchBegan(at: $0) },
                changed: { zoom.pinchChanged(ratio: $0, at: $1) },
                rebase: { zoom.rebaseRatio($0, at: $1) },
                ended: { zoom.pinchEnded(onClosed: {}) }
            )
    }

    /// 放大查看覆盖层
    @ViewBuilder
    private var zoomStage: some View {
        if zoom.presented {
            let result: ScanResult = {
                if case .done(let r) = phase, !textWasEdited { return r }
                return .empty
            }()
            ScanZoomStage(
                model: zoom,
                image: scanImage.image,
                result: result,
                library: library,
                selectedClusterID: selectedClusterID,
                ink: ink,
                onClosed: {}
            ) { cluster in
                selectedClusterID = cluster.id
                tappedCluster = cluster
            }
        }
    }

    // MARK: - 结果

    @ViewBuilder
    private func resultSections(_ result: ScanResult) -> some View {
        let ids = library.displayableIDs(result.orderedGrammarIDs)
        if result.text.isEmpty {
            ContentUnavailableView(tr("没有识别到日文"), systemImage: "text.magnifyingglass",
                                   description: Text(localized: "请让文字清晰、光线充足，尽量正对书页拍摄。"))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    (ids.isEmpty ? Text(localized: "没有识别到收录的语法点") : Text(localized: "识别到 \(ids.count) 个语法点"))
                        .font(.title3.bold())
                }
                if !ids.isEmpty {
                    Text(localized: "点击高亮或下方列表查看讲解；双指可直接放大图片。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if result.pageIsCurved && !textWasEdited {
                    Label {
                        Text(localized: "书页弯曲较大，个别高亮可能落在相邻的行。把书页压平、正对拍摄，效果更好。")
                    } icon: {
                        Image(systemName: "book.pages")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("result.curvedHint")
                }
                VStack(spacing: 0) {
                    ForEach(ids, id: \.self) { id in
                        if let p = library.point(id: id) {
                            NavigationLink(value: Route.grammarMatch(id, result.matchedText(for: id) ?? "")) {
                                GrammarRow(point: p, occurrences: result.matches.filter { $0.grammarID == id }.count)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("result.grammarRow")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            Divider().padding(.leading, 28)
                        }
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            // 识别错字导致漏掉语法时的补救入口：平时不打扰
            Button {
                draftText = result.text
                isEditing = true
            } label: {
                HStack(spacing: 4) {
                    Text(localized: "有语法没识别出来？")
                    Text(localized: "手动修正文字").foregroundStyle(Theme.accentText)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("result.editText")
            if textWasEdited {
                Text(localized: "文本已手动修改，图片上的高亮已隐藏。").font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var editSheet: some View {
        NavigationStack {
            TextEditor(text: $draftText)
                .accessibilityIdentifier("result.editor")
                .font(.title3)
                .padding()
                .keyboardDoneButton()
                .navigationTitle(tr("修正识别文本"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("取消")) { isEditing = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("重新识别")) {
                            let result = ScanAnalyzer.analyze(text: draftText, lines: [], matcher: library.matcher)
                            textWasEdited = true
                            selectedClusterID = nil
                            phase = .done(result)
                            if let recordID { history.updateScan(recordID, grammarIDs: library.displayableIDs(result.orderedGrammarIDs)) }
                            isEditing = false
                        }
                    }
                }
        }
    }

    // MARK: -

    private func analyze() async {
        guard case .loading = phase else { return }
        let image = scanImage.image
        let matcher = library.matcher
        let outcome: Result<(ScanResult, [RecognizedLine]), Error> = await Task.detached(priority: .userInitiated) { () -> Result<(ScanResult, [RecognizedLine]), Error> in
            guard let cg = image.cgImage else {
                return .failure(NSError(domain: "Scan", code: 1, userInfo: [NSLocalizedDescriptionKey: tr("无法读取图片")]))
            }
            do {
                let ocr = try TextRecognizer.recognize(cgImage: cg, orientation: .init(image.imageOrientation))
                return .success((ScanAnalyzer.analyze(text: ocr.text, lines: ocr.lines, matcher: matcher), ocr.lines))
            } catch {
                return .failure(error)
            }
        }.value
        switch outcome {
        case .success(let (r, lines)):
            phase = .done(r)
            if let cg = image.cgImage {
                ink = await Task.detached(priority: .userInitiated) { InkMask.make(from: cg) }.value
            }
            if DemoMode.opensZoom {
                try? await Task.sleep(for: .milliseconds(600))
                zoom.open()
            }
            let ids = library.displayableIDs(r.orderedGrammarIDs)
            if let existing = scanImage.historyID {
                recordID = existing
                // 重新识别的结果可能与保存时略有不同：以现在显示的为准，首页「继续上次」的数字随之一致
                history.updateScan(existing, grammarIDs: ids)
            } else if !scanImage.isSample, !r.text.isEmpty, DemoMode.screen == nil {
                recordID = history.recordScan(image: scanImage.image, grammarIDs: ids)
            }
            // 第二步：切竖条重新识别，把高亮框挪到更准的位置（弯曲、斜拍的书页上尤其明显）。
            // 先显示第一步的结果，不让用户干等；语法点列表不变，只是框的位置更准
            if image.imageOrientation == .up, let cg = image.cgImage {
                let refined = await Task.detached(priority: .userInitiated) { StripLocator.refine(r, lines: lines, image: cg) }.value
                if case .done = phase { phase = .done(refined) }
            }
        case .failure(let e): phase = .failed(e.localizedDescription)
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
