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
                        Text("正在识别文字和语法点…")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                case .failed(let message):
                    ContentUnavailableView("识别失败", systemImage: "exclamationmark.triangle", description: Text(message))
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
        .navigationTitle("识别结果")
        .accessibilityIdentifier("screen.scanResult")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $pushedGrammarID) { id in
            GrammarDetailView(grammarID: id)
        }
        .grammarChooser(cluster: $tappedCluster, library: library) { id in
            if let pushRoute { pushRoute(.grammar(id)) } else { pushedGrammarID = id }
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
                        selectedClusterID: selectedClusterID
                    ) { cluster in
                        selectedClusterID = cluster.id
                        tappedCluster = cluster
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.5), in: Circle())
                    .padding(8)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { zoom.open() }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("放大查看"))
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
            ContentUnavailableView("没有识别到日文", systemImage: "text.magnifyingglass",
                                   description: Text("请让文字清晰、光线充足，尽量正对书页拍摄。"))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    (ids.isEmpty ? Text("没有识别到收录的语法点") : Text("识别到 \(ids.count) 个语法点"))
                        .font(.title3.bold())
                }
                if !ids.isEmpty {
                    Text("点击高亮或下方列表查看讲解；双指可直接放大图片。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    ForEach(ids, id: \.self) { id in
                        if let p = library.point(id: id) {
                            NavigationLink(value: Route.grammar(id)) {
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
                    Text("有语法没识别出来？")
                    Text("手动修正文字").foregroundStyle(Theme.accentText)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            if textWasEdited {
                Text("文本已手动修改，图片上的高亮已隐藏。").font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var editSheet: some View {
        NavigationStack {
            TextEditor(text: $draftText)
                .font(.title3)
                .padding()
                .navigationTitle("修正识别文本")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { isEditing = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("重新识别") {
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
        let outcome: Result<ScanResult, Error> = await Task.detached(priority: .userInitiated) { () -> Result<ScanResult, Error> in
            guard let cg = image.cgImage else {
                return .failure(NSError(domain: "Scan", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "无法读取图片")]))
            }
            do {
                let ocr = try TextRecognizer.recognize(cgImage: cg, orientation: .init(image.imageOrientation))
                return .success(ScanAnalyzer.analyze(text: ocr.text, lines: ocr.lines, matcher: matcher))
            } catch {
                return .failure(error)
            }
        }.value
        switch outcome {
        case .success(let r):
            phase = .done(r)
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
