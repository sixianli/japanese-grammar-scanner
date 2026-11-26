import SwiftUI
import UIKit

@Observable
final class ScanZoomModel {
    private(set) var presented = false
    private(set) var isOpen = false
    var scale: CGFloat = 1
    var origin: CGPoint = .zero
    var dim: Double = 0
    private(set) var settledScale: CGFloat = 1

    @ObservationIgnored var sourceFrame: CGRect = .zero
    @ObservationIgnored var container: CGRect = .zero
    @ObservationIgnored var imageSize: CGSize = .zero
    @ObservationIgnored var lineDragging = false

    @ObservationIgnored private var baseScale: CGFloat = 1
    @ObservationIgnored private var baseOrigin: CGPoint = .zero
    @ObservationIgnored private var anchorPoint: CGPoint = .zero
    @ObservationIgnored private var startedOpen = false
    @ObservationIgnored private var panStartOrigin: CGPoint = .zero
    @ObservationIgnored private var pinching = false
    @ObservationIgnored private var panNeedsRebase = true

    private var size: CGSize { container.size }

    var target: CGRect { ImageFit.fit.displayedRect(imageSize: imageSize, in: size) }

    private var source: CGRect {
        let local = sourceFrame.offsetBy(dx: -container.minX, dy: -container.minY)
        return ImageFit.fit.displayedRect(imageSize: imageSize, in: local.size)
            .offsetBy(dx: local.minX, dy: local.minY)
    }

    private var sourceScale: CGFloat {
        target.width > 0 ? source.width / target.width : 1
    }

    private var progress: CGFloat {
        let s0 = sourceScale
        guard 1 - s0 > 0.001 else { return scale >= 1 ? 1 : 0 }
        return min(1, max(0, (scale - s0) / (1 - s0)))
    }

    func pinchBegan(at location: CGPoint) {
        pinching = true
        if !presented {
            scale = sourceScale
            origin = source.origin
            dim = 0
            presented = true
            startedOpen = false
        } else {
            startedOpen = isOpen
        }
        rebase(at: location)
    }

    func rebase(at location: CGPoint) {
        let c = local(location)
        baseScale = scale
        baseOrigin = origin
        anchorPoint = CGPoint(x: (c.x - origin.x) / scale, y: (c.y - origin.y) / scale)
        pinchRatioBase = 1
    }

    @ObservationIgnored private var pinchRatioBase: CGFloat = 1

    func rebaseRatio(_ ratio: CGFloat, at location: CGPoint) {
        rebase(at: location)
        pinchRatioBase = ratio
    }

    func pinchChanged(ratio: CGFloat, at location: CGPoint) {
        let c = local(location)
        var s = baseScale * ratio / max(pinchRatioBase, 0.0001)
        let maxScale: CGFloat = 8
        if s > maxScale { s = maxScale + (s - maxScale) * 0.3 }
        s = max(s, sourceScale * 0.5)
        scale = s
        origin = CGPoint(x: c.x - s * anchorPoint.x, y: c.y - s * anchorPoint.y)
        dim = Double(progress)
    }

    func pinchEnded(onClosed: @escaping () -> Void) {
        pinching = false
        panNeedsRebase = true
        if startedOpen {
            if scale < 0.85 { close(then: onClosed) } else { settle() }
        } else {
            if progress > 0.12 || scale >= 1 { open() } else { close(then: onClosed) }
        }
    }

    func panChanged(_ t: CGSize) {
        guard isOpen, !pinching, !lineDragging else { return }
        if panNeedsRebase {
            panStartOrigin = CGPoint(x: origin.x - t.width, y: origin.y - t.height)
            panNeedsRebase = false
        }
        origin = CGPoint(x: panStartOrigin.x + t.width, y: panStartOrigin.y + t.height)
        if scale <= 1.01 {
            dim = max(0.2, 1 - Double(abs(t.height)) / 500)
        }
    }

    func panEnded(_ t: CGSize, onClosed: @escaping () -> Void) {
        panNeedsRebase = true
        guard isOpen, !pinching else { return }
        let moved = origin.y - panStartOrigin.y
        if scale <= 1.01, moved > 110, !lineDragging {
            close(then: onClosed)
        } else {
            settle()
        }
    }

    func doubleTap(at location: CGPoint) {
        guard isOpen else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
            if scale > 1.05 {
                scale = 1
                origin = target.origin
            } else {
                let c = local(location)
                let p = CGPoint(x: (c.x - origin.x) / scale, y: (c.y - origin.y) / scale)
                scale = 2.5
                origin = clamped(CGPoint(x: c.x - 2.5 * p.x, y: c.y - 2.5 * p.y), scale: 2.5)
            }
        } completion: { [self] in settledScale = scale }
    }

    func open() {
        if !presented {
            scale = sourceScale
            origin = source.origin
            dim = 0
            presented = true
            isOpen = true
            DispatchQueue.main.async { [self] in animateOpen() }
            return
        }
        isOpen = true
        animateOpen()
    }

    private func animateOpen() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
            if scale > 1 {
                origin = clamped(origin, scale: min(scale, 8))
                scale = min(scale, 8)
            } else {
                scale = 1
                origin = target.origin
            }
            dim = 1
        } completion: { [self] in settledScale = scale }
    }

    func close(then action: @escaping () -> Void = {}) {
        isOpen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [self] in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                scale = sourceScale
                origin = source.origin
                dim = 0
            } completion: { [self] in
                presented = false
                settledScale = 1
                action()
            }
        }
    }

    private func settle() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
            if scale < 1 {
                scale = 1
                origin = target.origin
            } else {
                let s = min(scale, 8)
                if s != scale {
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    let p = CGPoint(x: (c.x - origin.x) / scale, y: (c.y - origin.y) / scale)
                    origin = CGPoint(x: c.x - s * p.x, y: c.y - s * p.y)
                    scale = s
                }
                origin = clamped(origin, scale: scale)
            }
            dim = 1
        } completion: { [self] in settledScale = scale }
    }

    private func clamped(_ o: CGPoint, scale s: CGFloat) -> CGPoint {
        let w = target.width * s, h = target.height * s
        func axis(_ v: CGFloat, content: CGFloat, bounds: CGFloat) -> CGFloat {
            content <= bounds ? (bounds - content) / 2 : min(0, max(bounds - content, v))
        }
        return CGPoint(x: axis(o.x, content: w, bounds: size.width),
                       y: axis(o.y, content: h, bounds: size.height))
    }

    private func local(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - container.minX, y: p.y - container.minY)
    }
}

@available(iOS 18.0, *)
struct PinchRecognizer: UIGestureRecognizerRepresentable {
    var onBegan: (CGPoint) -> Void
    var onChanged: (CGFloat, CGPoint) -> Void
    var onRebase: (CGFloat, CGPoint) -> Void
    var onEnded: () -> Void

    final class Coordinator { var touches = 0 }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        UIPinchGestureRecognizer()
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        let location = context.converter.location(in: .global)
        switch recognizer.state {
        case .began:
            context.coordinator.touches = recognizer.numberOfTouches
            onBegan(location)
        case .changed:
            if recognizer.numberOfTouches != context.coordinator.touches {
                context.coordinator.touches = recognizer.numberOfTouches
                onRebase(recognizer.scale, location)
            } else {
                onChanged(recognizer.scale, location)
            }
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }
}

extension View {
    @ViewBuilder
    func scanPinch(
        began: @escaping (CGPoint) -> Void,
        changed: @escaping (CGFloat, CGPoint) -> Void,
        rebase: @escaping (CGFloat, CGPoint) -> Void,
        ended: @escaping () -> Void
    ) -> some View {
        if #available(iOS 18.0, *) {
            gesture(PinchRecognizer(onBegan: began, onChanged: changed, onRebase: rebase, onEnded: ended))
        } else {
            modifier(LegacyPinch(began: began, changed: changed, ended: ended))
        }
    }
}

private struct LegacyPinch: ViewModifier {
    let began: (CGPoint) -> Void
    let changed: (CGFloat, CGPoint) -> Void
    let ended: () -> Void
    @State private var active = false
    @State private var start: CGPoint = .zero
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { frame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, f in frame = f }
            })
            .gesture(
            MagnifyGesture(minimumScaleDelta: 0)
                .onChanged { value in
                    if !active {
                        active = true
                        start = CGPoint(x: frame.minX + value.startLocation.x, y: frame.minY + value.startLocation.y)
                        began(start)
                    }
                    changed(value.magnification, start)
                }
                .onEnded { _ in
                    active = false
                    ended()
                }
        )
    }
}

struct ScanZoomStage: View {
    struct LineChoice {
        let lines: [RecognizedLine]
        let chosen: Set<Int>?
        let onChoose: (Set<Int>) -> Void
    }

    let model: ScanZoomModel
    let image: UIImage
    let result: ScanResult
    let library: GrammarLibrary
    let selectedClusterID: Int?
    var lineChoice: LineChoice?
    let onClosed: () -> Void
    let onSelect: (HighlightCluster) -> Void

    var body: some View {
        let target = model.target
        let radius = 12 * (1 - min(1, CGFloat(model.dim)))
        ZStack(alignment: .topLeading) {
            Color.black.opacity(model.dim)
            ScanZoomContent(
                image: image, result: result, library: library,
                selectedClusterID: selectedClusterID,
                settledScale: model.settledScale,
                lineChoice: model.isOpen ? lineChoice : nil,
                onDragging: { model.lineDragging = $0 },
                onSelect: { cluster in
                    guard model.isOpen else { return }
                    model.close { onSelect(cluster) }
                }
            )
            .equatable()
            .frame(width: target.width, height: target.height)
            .clipShape(RoundedRectangle(cornerRadius: radius / max(model.scale, 0.01)))
            .scaleEffect(model.scale, anchor: .topLeading)
            .offset(x: model.origin.x, y: model.origin.y)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .scanPinch(
            began: { model.pinchBegan(at: $0) },
            changed: { model.pinchChanged(ratio: $0, at: $1) },
            rebase: { model.rebaseRatio($0, at: $1) },
            ended: { model.pinchEnded(onClosed: onClosed) }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in model.panChanged(value.translation) }
                .onEnded { value in model.panEnded(value.translation, onClosed: onClosed) }
        )
        .simultaneousGesture(
            SpatialTapGesture(count: 2, coordinateSpace: .global)
                .onEnded { model.doubleTap(at: $0.location) }
        )
        .overlay(alignment: .topTrailing) {
            if model.isOpen {
                Button { model.close(then: onClosed) } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .accessibilityLabel(Text(localized: "关闭"))
                .accessibilityIdentifier("zoom.close")
                .padding()
                .padding(.top, 44)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if model.isOpen {
                Text(lineChoice == nil ? tr("双指缩放查看原文，点击高亮查看讲解") : tr("点一行改看这一行，按住拖动可选几行；点高亮看讲解"))
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, 34)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.isOpen)
        .ignoresSafeArea()
    }
}

private struct ScanZoomContent: View, Equatable {
    let image: UIImage
    let result: ScanResult
    let library: GrammarLibrary
    let selectedClusterID: Int?
    let settledScale: CGFloat
    let lineChoice: ScanZoomStage.LineChoice?
    let onDragging: (Bool) -> Void
    let onSelect: (HighlightCluster) -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.image === b.image && a.selectedClusterID == b.selectedClusterID
            && a.settledScale == b.settledScale && a.result.boxes == b.result.boxes
            && a.result.text == b.result.text
            && (a.lineChoice == nil) == (b.lineChoice == nil)
            && a.lineChoice?.chosen == b.lineChoice?.chosen
            && a.lineChoice?.lines.count == b.lineChoice?.lines.count
    }

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .overlay {
                if let lineChoice {
                    ResultLineLayer(lines: lineChoice.lines, chosen: lineChoice.chosen,
                                    lineWidth: 2 / max(settledScale, 1),
                                    tapSlack: 12 / max(settledScale, 1),
                                    onDragging: onDragging,
                                    onChoose: lineChoice.onChoose)
                }
            }
            .overlay {
                HighlightOverlay(
                    result: result,
                    imageSize: image.size,
                    fit: .fit,
                    library: library,
                    selectedClusterID: selectedClusterID,
                    lineWidth: 1.2 / max(settledScale, 1)
                ) { onSelect($0) }
            }
    }
}
