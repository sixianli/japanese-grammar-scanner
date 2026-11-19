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
    /// 全屏查看：是否显示、展开进度（0 = 原位置，1 = 铺满全屏）、是否已完全展开可交互
    @State private var zoomPresented = false
    @State private var zoomProgress: CGFloat = 0
    @State private var zoomSettled = false
    @State private var imageFrame: CGRect = .zero

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
        .overlay { zoomStage }
        .toolbar(zoomPresented ? .hidden : .automatic, for: .navigationBar, .tabBar)
        .statusBarHidden(zoomSettled)
        .navigationTitle("识别结果")
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
            .onTapGesture { openZoom() }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 460)
            // 记录图片在屏幕上的位置：放大从这里开始，缩小回到这里
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { imageFrame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, f in imageFrame = f }
            })
            // 放大时原位置的图片隐藏，由覆盖全屏的那一份接管
            .opacity(zoomPresented ? 0.001 : 1)
            // 直接在结果页双指放大：图片从原位置跟着手指渐进放大，直到铺满全屏
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        if !zoomPresented { zoomPresented = true; zoomSettled = false }
                        zoomProgress = min(1, max(0, (value.magnification - 1) / 1.2))
                    }
                    .onEnded { value in
                        if (value.magnification - 1) / 1.2 > 0.2 {
                            openZoom()
                        } else {
                            closeZoom()
                        }
                    }
            )
    }

    /// 放大到全屏（跟手动画的终点）
    private func openZoom() {
        zoomPresented = true
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            zoomProgress = 1
        } completion: {
            zoomSettled = true
        }
    }

    /// 从全屏缩回原位置
    private func closeZoom(then action: (() -> Void)? = nil) {
        zoomSettled = false
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            zoomProgress = 0
        } completion: {
            zoomPresented = false
            action?()
        }
    }

    /// 全屏查看层：未完全展开时，图片在「原位置 ↔ 全屏」之间按进度插值（跟手）；展开后可缩放、拖动、点高亮。
    @ViewBuilder
    private var zoomStage: some View {
        if zoomPresented {
            let result: ScanResult = {
                if case .done(let r) = phase, !textWasEdited { return r }
                return .empty
            }()
            GeometryReader { geo in
                let origin = geo.frame(in: .global).origin
                let source = imageFrame.offsetBy(dx: -origin.x, dy: -origin.y)
                let target = ImageFit.fit.displayedRect(imageSize: scanImage.image.size, in: geo.size)
                let fitSource = ImageFit.fit.displayedRect(imageSize: scanImage.image.size, in: source.size)
                    .offsetBy(dx: source.minX, dy: source.minY)
                let t = zoomProgress
                let frame = CGRect(
                    x: fitSource.minX + (target.minX - fitSource.minX) * t,
                    y: fitSource.minY + (target.minY - fitSource.minY) * t,
                    width: fitSource.width + (target.width - fitSource.width) * t,
                    height: fitSource.height + (target.height - fitSource.height) * t
                )
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(Double(t)).ignoresSafeArea()
                    if zoomSettled {
                        ZoomableScanView(image: scanImage.image, result: result, library: library,
                                         onClose: { closeZoom() }) { cluster in
                            closeZoom {
                                selectedClusterID = cluster.id
                                tappedCluster = cluster
                            }
                        }
                    } else {
                        Image(uiImage: scanImage.image)
                            .resizable()
                            .overlay {
                                HighlightOverlay(result: result, imageSize: scanImage.image.size, fit: .fit,
                                                 library: library, selectedClusterID: selectedClusterID) { _ in }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12 * (1 - t)))
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
            }
            .ignoresSafeArea()
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
