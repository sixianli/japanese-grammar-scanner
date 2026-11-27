import SwiftUI

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
    @State private var zoom = ScanZoomModel()
    @State private var fullResult: ScanResult = .empty
    @State private var lines: [RecognizedLine] = []
    @State private var selectedLines: Set<Int> = []
    @State private var chosenLines: Set<Int>?
    @State private var lineDragging = false

    enum Phase {
        case loading
        case selecting
        case done(ScanResult)
        case failed(String)
    }

    private var isSelecting: Bool {
        if case .selecting = phase { return true }
        return false
    }

    var body: some View {
        Group {
            if isSelecting {
                LineSelectView(
                    image: scanImage.image,
                    lines: lines,
                    selected: $selectedLines,
                    onAnalyzeAll: { confirm(nil) },
                    onAnalyzeSelected: { confirm(selectedLines) }
                )
            } else {
                resultPage
            }
        }
        .toolbar(zoom.isOpen || isSelecting ? .hidden : .automatic, for: .tabBar)
        .toolbar(zoom.isOpen ? .hidden : .automatic, for: .navigationBar)
        .statusBarHidden(zoom.isOpen)
        .onAppear {
            zoom.imageSize = scanImage.image.size
            selectedClusterID = nil
        }
        .navigationTitle(isSelecting ? tr("选择要看的行") : tr("识别结果"))
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

    private var resultPage: some View {
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
                case .selecting:
                    EmptyView()
                }
            }
            .padding()
        }
        .scrollDisabled(lineDragging)
        .background(Theme.background)
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
    }

    private var canChooseLines: Bool {
        guard case .done = phase else { return false }
        return !textWasEdited && !lines.isEmpty
    }

    private var isDone: Bool {
        if case .done = phase { return true }
        return false
    }

    private var imageSection: some View {
        Image(uiImage: scanImage.image)
            .resizable()
            .scaledToFit()
            .overlay {
                if canChooseLines {
                    ResultLineLayer(lines: lines, chosen: chosenLines,
                                    onDragging: { lineDragging = $0 },
                                    onChoose: { confirm($0) })
                }
            }
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
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("result.image")
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 460)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { zoom.sourceFrame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, f in zoom.sourceFrame = f }
            })
            .opacity(zoom.presented ? 0.001 : 1)
            .scanPinch(
                began: { zoom.pinchBegan(at: $0) },
                changed: { zoom.pinchChanged(ratio: $0, at: $1) },
                rebase: { zoom.rebaseRatio($0, at: $1) },
                ended: { zoom.pinchEnded(onClosed: {}) }
            )
    }

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
                lineChoice: canChooseLines ? ScanZoomStage.LineChoice(lines: lines, chosen: chosenLines, onChoose: { confirm($0) }) : nil,
                onClosed: {}
            ) { cluster in
                selectedClusterID = cluster.id
                tappedCluster = cluster
            }
        }
    }

    @ViewBuilder
    private func resultSections(_ result: ScanResult) -> some View {
        let ids = library.displayableIDs(result.orderedGrammarIDs)
        if result.text.isEmpty {
            ContentUnavailableView(tr("没有识别到日文"), systemImage: "text.magnifyingglass",
                                   description: Text(localized: "请让文字清晰、光线充足，尽量正对书页拍摄。"))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    headline(count: ids.count)
                        .font(.title3.bold())
                        .accessibilityIdentifier("result.headline")
                    Spacer(minLength: 8)
                    if canChooseLines && chosenLines != nil {
                        Button { confirm(nil) } label: {
                            Text(localized: "分析整页")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.accentText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Theme.accentFill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("result.analyzeAll")
                    }
                }
                if canChooseLines {
                    Text(localized: "点照片上别的行就改看那一行；按住再上下拖可以选几行。点高亮看讲解。")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("result.hint")
                } else if !ids.isEmpty {
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

    @ViewBuilder
    private func headline(count: Int) -> some View {
        if let chosen = chosenLines, !textWasEdited {
            if count == 0 {
                Text(localized: "选中的行里没有收录的语法点")
            } else if chosen.count == 1 {
                Text(localized: "这一行有 \(count) 个语法点")
            } else {
                Text(localized: "这 \(chosen.count) 行有 \(count) 个语法点")
            }
        } else if count == 0 {
            Text(localized: "没有识别到收录的语法点")
        } else {
            Text(localized: "识别到 \(count) 个语法点")
        }
    }

    private func displayed(_ full: ScanResult) -> ScanResult {
        guard let chosen = chosenLines else { return full }
        return full.limited(toLines: chosen, of: lines)
    }

    private func confirm(_ chosen: Set<Int>?) {
        chosenLines = chosen.flatMap { $0.isEmpty ? nil : $0 }
        selectedClusterID = nil
        let result = displayed(fullResult)
        phase = .done(result)
        record(library.displayableIDs(result.orderedGrammarIDs))
    }

    private func record(_ ids: [String]) {
        if let recordID {
            history.updateScan(recordID, grammarIDs: ids)
        } else if let existing = scanImage.historyID {
            recordID = existing
            history.updateScan(existing, grammarIDs: ids)
        } else if !scanImage.isSample, !fullResult.text.isEmpty, DemoMode.screen == nil {
            recordID = history.recordScan(image: scanImage.image, grammarIDs: ids)
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
                            chosenLines = nil
                            selectedClusterID = nil
                            phase = .done(result)
                            if let recordID { history.updateScan(recordID, grammarIDs: library.displayableIDs(result.orderedGrammarIDs)) }
                            isEditing = false
                        }
                    }
                }
        }
    }

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
        case .success(let (r, recognized)):
            fullResult = r
            lines = recognized
            if r.text.isEmpty || recognized.isEmpty {
                phase = .done(r)
            } else if DemoMode.screen != nil {
                selectedLines = DemoMode.lines ?? []
                if DemoMode.staysOnLineSelection { phase = .selecting } else { confirm(DemoMode.lines) }
            } else {
                phase = .selecting
            }
            if DemoMode.opensZoom, case .done = phase {
                try? await Task.sleep(for: .milliseconds(600))
                zoom.open()
            }
            if image.imageOrientation == .up, let cg = image.cgImage, !r.boxes.isEmpty {
                let refined = await Task.detached(priority: .userInitiated) { StripLocator.refine(r, lines: recognized, image: cg) }.value
                fullResult = refined
                if case .done = phase, !textWasEdited { phase = .done(displayed(refined)) }
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
