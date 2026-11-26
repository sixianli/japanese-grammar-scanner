import SwiftUI

struct LineSelectView: View {
    let image: UIImage
    let lines: [RecognizedLine]
    @Binding var selected: Set<Int>
    let onAnalyzeAll: () -> Void
    let onAnalyzeSelected: () -> Void

    @State private var zoom = SelectionZoom()
    @State private var containerFrame: CGRect = .zero
    @State private var dragStartLine: Int?
    @State private var selectionBeforeDrag: Set<Int>?
    @State private var pinching = false
    @State private var gestureHadPinch = false

    private static let tapTravel: CGFloat = 10
    private static let tapSlack: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            photo
                .padding(.horizontal, 8)
                .padding(.top, 4)
            hint
            bottomBar
        }
        .background(Theme.background)
    }

    private var hint: some View {
        ZStack(alignment: .top) {
            emptyHint.hidden().accessibilityHidden(true)
            selectedHint.hidden().accessibilityHidden(true)
            Group {
                if selected.isEmpty { emptyHint } else { selectedHint }
            }
            .accessibilityIdentifier("select.hint")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var emptyHint: some View {
        Text(localized: "点一行只看这一行的语法；按住上下拖动可以选几行。双指可放大照片。")
            .fixedSize(horizontal: false, vertical: true)
    }

    private var selectedHint: some View {
        Text(localized: "再点别的行可以加选，点已选的行取消。")
            .fixedSize(horizontal: false, vertical: true)
    }

    private var bottomBar: some View {
        ZStack(alignment: .bottom) {
            selectedButtons(tagged: false).hidden().accessibilityHidden(true).allowsHitTesting(false)
            if selected.isEmpty {
                Button(action: onAnalyzeAll) {
                    Text(localized: "分析整页").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("select.analyzeAll")
            } else {
                selectedButtons(tagged: true)
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    private func selectedButtons(tagged: Bool) -> some View {
        VStack(spacing: 8) {
            Button(action: onAnalyzeSelected) {
                Text(localized: "分析这 \(max(selected.count, 1)) 行").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(tagged ? "select.analyzeSelected" : "")
            Button(action: onAnalyzeAll) {
                Text(localized: "改为分析整页").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(tagged ? "select.analyzeAll" : "")
        }
    }

    private var photo: some View {
        GeometryReader { geo in
            let display = ImageFit.fit.displayedRect(imageSize: image.size, in: geo.size)
            let quads = LineSelection.lineQuads(lines).map { q in
                q.map { CGPoint(x: display.minX + $0.x * display.width, y: display.minY + $0.y * display.height) }
            }
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: display.width, height: display.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .position(x: display.midX, y: display.midY)
                    .accessibilityHidden(true)
                selectionLayer(quads: quads, size: geo.size, display: display)
                lineElements(quads: quads)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .scaleEffect(zoom.scale, anchor: .topLeading)
            .offset(x: zoom.offset.x, y: zoom.offset.y)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("select.photo")
            .scanPinch(
                began: { location in
                    pinching = true
                    gestureHadPinch = true
                    if let before = selectionBeforeDrag { selected = before }
                    zoom.pinchBegan(at: local(location))
                },
                changed: { ratio, location in zoom.pinchChanged(ratio: ratio, at: local(location)) },
                rebase: { ratio, location in zoom.rebase(ratio: ratio, at: local(location)) },
                ended: {
                    pinching = false
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { zoom.settle(in: geo.size) }
                }
            )
            .simultaneousGesture(selectGesture(quads: quads))
            .onAppear { containerFrame = geo.frame(in: .global) }
            .onChange(of: geo.frame(in: .global)) { _, f in containerFrame = f }
        }
    }

    private func local(_ global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - containerFrame.minX, y: global.y - containerFrame.minY)
    }

    private func selectGesture(quads: [[CGPoint]]) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if selectionBeforeDrag == nil {
                    selectionBeforeDrag = selected
                    gestureHadPinch = false
                    dragStartLine = LineSelection.line(at: zoom.contentPoint(value.startLocation), quads: quads, slack: .infinity)
                }
                guard !pinching, !gestureHadPinch, hypot(value.translation.width, value.translation.height) >= Self.tapTravel,
                      let start = dragStartLine,
                      let current = LineSelection.line(at: zoom.contentPoint(value.location), quads: quads, slack: .infinity)
                else { return }
                selected = LineSelection.span(from: start, to: current)
            }
            .onEnded { value in
                defer {
                    selectionBeforeDrag = nil
                    dragStartLine = nil
                }
                guard !gestureHadPinch else { return }
                let travel = hypot(value.translation.width, value.translation.height)
                guard travel < Self.tapTravel,
                      let line = LineSelection.line(at: zoom.contentPoint(value.location), quads: quads, slack: Self.tapSlack / zoom.scale)
                else { return }
                if selected.contains(line) { selected.remove(line) } else { selected.insert(line) }
            }
    }

    private func selectionLayer(quads: [[CGPoint]], size: CGSize, display: CGRect) -> some View {
        LineSpotlight(outlines: LineSelection.outlines(selected: selected, quads: quads, pad: 4),
                      display: display, lineWidth: 2.5 / zoom.scale)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .animation(.easeOut(duration: 0.12), value: selected)
    }

    private func lineElements(quads: [[CGPoint]]) -> some View {
        ForEach(Array(quads.enumerated()), id: \.offset) { i, q in
            let bounds = HighlightGeometry.bounds(q)
            let isSelected = selected.contains(i)
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: max(bounds.width, 1), height: max(bounds.height, 1))
                .position(x: bounds.midX, y: bounds.midY)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: lines[i].text))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier(isSelected ? "select.line.selected" : "select.line")
                .accessibilityAction {
                    if isSelected { selected.remove(i) } else { selected.insert(i) }
                }
        }
    }
}

struct LineSpotlight: View {
    let outlines: [[CGPoint]]
    let display: CGRect
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !outlines.isEmpty {
                Path { p in
                    p.addRoundedRect(in: display, cornerSize: CGSize(width: 12, height: 12))
                    for o in outlines { p.addLines(o); p.closeSubpath() }
                }
                .fill(Color.black.opacity(0.4), style: FillStyle(eoFill: true))
                ForEach(Array(outlines.enumerated()), id: \.offset) { _, o in
                    Path { p in p.addLines(o); p.closeSubpath() }
                        .fill(Theme.accent.opacity(0.12))
                    Path { p in p.addLines(o); p.closeSubpath() }
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct SelectedLinesShade: View {
    let lines: [RecognizedLine]
    let selected: Set<Int>
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geo in
            let display = ImageFit.fit.displayedRect(imageSize: imageSize, in: geo.size)
            let quads = LineSelection.lineQuads(lines).map { q in
                q.map { CGPoint(x: display.minX + $0.x * display.width, y: display.minY + $0.y * display.height) }
            }
            LineSpotlight(outlines: LineSelection.outlines(selected: selected, quads: quads, pad: 4),
                          display: display, lineWidth: 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
