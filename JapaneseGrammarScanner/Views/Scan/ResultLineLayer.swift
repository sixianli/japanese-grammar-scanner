import SwiftUI

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

struct ResultLineLayer: View {
    let lines: [RecognizedLine]
    let chosen: Set<Int>?
    var lineWidth: CGFloat = 2
    var tapSlack: CGFloat = 12
    let onDragging: (Bool) -> Void
    var onPreview: (Set<Int>?) -> Void = { _ in }
    let onChoose: (Set<Int>) -> Void

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ResultLineCanvas(
                lines: lines,
                quads: LineSelection.lineQuads(lines).map { q in
                    q.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                },
                size: size,
                chosen: chosen,
                lineWidth: lineWidth,
                tapSlack: tapSlack,
                onDragging: onDragging,
                onPreview: onPreview,
                onChoose: onChoose
            )
        }
    }
}

private struct ResultLineCanvas: View {
    let lines: [RecognizedLine]
    let quads: [[CGPoint]]
    let size: CGSize
    let chosen: Set<Int>?
    let lineWidth: CGFloat
    let tapSlack: CGFloat
    let onDragging: (Bool) -> Void
    let onPreview: (Set<Int>?) -> Void
    let onChoose: (Set<Int>) -> Void

    @State private var preview: Set<Int>?
    @State private var dragStartLine: Int?
    @State private var holdCount = 0

    var body: some View {
        let shown = preview ?? chosen ?? []
        ZStack(alignment: .topLeading) {
            LineSpotlight(outlines: LineSelection.outlines(selected: shown, quads: quads, pad: 4),
                          display: CGRect(origin: .zero, size: size), lineWidth: lineWidth)
            lineElements(shown: shown)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture()
                .onEnded { value in
                    guard let line = LineSelection.line(at: value.location, quads: quads, slack: tapSlack),
                          chosen != [line] else { return }
                    onChoose([line])
                }
        )
        .simultaneousGesture(dragGesture)
        .sensoryFeedback(.selection, trigger: holdCount)
        .transaction { $0.animation = nil }
    }

    private var dragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragStartLine == nil {
                    let start = drag?.startLocation
                    guard let start, let line = LineSelection.line(at: start, quads: quads, slack: .infinity) else { return }
                    dragStartLine = line
                    holdCount += 1
                    onDragging(true)
                }
                guard let start = dragStartLine, let drag,
                      let current = LineSelection.line(at: drag.location, quads: quads, slack: .infinity) else { return }
                let span = LineSelection.span(from: start, to: current)
                if span != preview {
                    preview = span
                    onPreview(span)
                }
            }
            .onEnded { _ in
                let picked = preview
                preview = nil
                if dragStartLine != nil {
                    onDragging(false)
                    onPreview(nil)
                }
                dragStartLine = nil
                if let picked, !picked.isEmpty, picked != chosen { onChoose(picked) }
            }
    }

    private func lineElements(shown: Set<Int>) -> some View {
        ForEach(Array(quads.enumerated()), id: \.offset) { i, q in
            let bounds = HighlightGeometry.bounds(q)
            let isSelected = shown.contains(i)
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: max(bounds.width, 1), height: max(bounds.height, 1))
                .position(x: bounds.midX, y: bounds.midY)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: lines[i].text))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier(isSelected ? "result.line.selected" : "result.line")
                .accessibilityAction { onChoose([i]) }
        }
    }
}
