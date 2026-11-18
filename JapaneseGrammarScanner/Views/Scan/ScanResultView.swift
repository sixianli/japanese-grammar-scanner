import SwiftUI

/// 对一张图片（相机定格或相册）做高精度识别，把所有语法点在图片和文本中高亮，供用户选择查看。
struct ScanResultView: View {
    let scanImage: ScanImage

    @EnvironmentObject private var library: GrammarLibrary
    @State private var phase: Phase = .loading
    @State private var tappedCluster: HighlightCluster?
    @State private var selectedClusterID: Int?
    @State private var pushedGrammarID: String?
    @State private var isEditing = false
    @State private var draftText = ""
    @State private var textWasEdited = false
    @State private var showZoom = false

    enum Phase {
        case loading
        case done(ScanResult)
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                imageSection
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
        .navigationTitle("识别结果")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑文本") {
                    if case .done(let result) = phase {
                        draftText = result.text
                        isEditing = true
                    }
                }
                .disabled(!isDone)
            }
        }
        .navigationDestination(item: $pushedGrammarID) { id in
            GrammarDetailView(grammarID: id)
        }
        .grammarChooser(cluster: $tappedCluster, library: library) { id in
            pushedGrammarID = id
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
            .onTapGesture { showZoom = true }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 460)
            .fullScreenCover(isPresented: $showZoom) {
                if case .done(let result) = phase {
                    ZoomableScanView(image: scanImage.image, result: textWasEdited ? .empty : result, library: library) { cluster in
                        showZoom = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            selectedClusterID = cluster.id
                            tappedCluster = cluster
                        }
                    }
                } else {
                    ZoomableScanView(image: scanImage.image, result: .empty, library: library) { _ in }
                }
            }
    }

    // MARK: - 结果

    @ViewBuilder
    private func resultSections(_ result: ScanResult) -> some View {
        let ids = result.orderedGrammarIDs
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
                    Text("点击高亮或下方列表查看讲解；点击图片可放大查看原文。")
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
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("识别文本").font(.title3.bold())
                if textWasEdited {
                    Text("文本已手动修改，图片上的高亮已隐藏。").font(.footnote).foregroundStyle(.secondary)
                }
                HighlightedText(result: result, library: library, selectedClusterID: selectedClusterID) { cluster in
                    selectedClusterID = cluster.id
                    tappedCluster = cluster
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
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
        case .success(let r): phase = .done(r)
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
