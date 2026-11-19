import SwiftUI
import UIKit

/// 识别结果图片的放大查看（类似「照片」App）：
/// - 在结果页直接双指捏开，图片从原位置开始、以两指中点为中心、按手指分开的比例实时放大（完全跟手），松手后铺满全屏；
/// - 全屏后继续双指缩放 / 单指拖动 / 双击放大还原；在原大小时双指捏小或向下拖动即缩回原位置。
/// 手势过程中只改变图片的位移与缩放（渲染变换），不重新布局，也不重绘结果页，所以不会卡顿。
@Observable
final class ScanZoomModel {
    /// 覆盖层是否存在（手势或动画进行中，或已全屏）
    private(set) var presented = false
    /// 已完全展开：显示关闭按钮、隐藏导航栏和标签栏
    private(set) var isOpen = false
    /// 图片当前显示的缩放（相对「铺满全屏」的大小）和左上角位置（覆盖层坐标）
    var scale: CGFloat = 1
    var origin: CGPoint = .zero
    /// 背景变黑的程度
    var dim: Double = 0
    /// 高亮框线宽所依据的缩放：只在手势结束时更新，手势中不重绘高亮框
    private(set) var settledScale: CGFloat = 1

    /// 结果页中图片的位置（全局坐标）；覆盖层（全屏）的位置
    @ObservationIgnored var sourceFrame: CGRect = .zero
    @ObservationIgnored var container: CGRect = .zero
    @ObservationIgnored var imageSize: CGSize = .zero

    // 手势基准
    @ObservationIgnored private var baseScale: CGFloat = 1
    @ObservationIgnored private var baseOrigin: CGPoint = .zero
    @ObservationIgnored private var anchorPoint: CGPoint = .zero // 手指下的图片内容点（未缩放坐标）
    @ObservationIgnored private var startedOpen = false
    @ObservationIgnored private var panStartOrigin: CGPoint = .zero
    /// 双指缩放进行中：此时忽略单指拖动；缩放结束后拖动要重新取基准，避免跳动
    @ObservationIgnored private var pinching = false
    @ObservationIgnored private var panNeedsRebase = true

    private var size: CGSize { container.size }

    /// 铺满全屏时图片的位置
    var target: CGRect { ImageFit.fit.displayedRect(imageSize: imageSize, in: size) }

    /// 在结果页时图片的位置（覆盖层坐标）
    private var source: CGRect {
        let local = sourceFrame.offsetBy(dx: -container.minX, dy: -container.minY)
        return ImageFit.fit.displayedRect(imageSize: imageSize, in: local.size)
            .offsetBy(dx: local.minX, dy: local.minY)
    }

    private var sourceScale: CGFloat {
        target.width > 0 ? source.width / target.width : 1
    }

    /// 0 = 原位置大小，1 = 铺满全屏
    private var progress: CGFloat {
        let s0 = sourceScale
        guard 1 - s0 > 0.001 else { return scale >= 1 ? 1 : 0 }
        return min(1, max(0, (scale - s0) / (1 - s0)))
    }

    // MARK: - 双指缩放（location 为两指中点，全局坐标；ratio 为本次手势的累计缩放比例）

    func pinchBegan(at location: CGPoint) {
        pinching = true
        if !presented {
            // 从结果页开始：覆盖层里的图片先摆到原位置
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

    /// 两指数量变化（如抬起一指再放下）时重新取基准，避免跳动
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
        // 超过上限后阻尼
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
            // 已全屏：捏小到明显小于全屏 → 缩回原位置；否则回弹到合理范围
            if scale < 0.85 { close(then: onClosed) } else { settle() }
        } else {
            if progress > 0.12 || scale >= 1 { open() } else { close(then: onClosed) }
        }
    }

    // MARK: - 单指拖动

    func panChanged(_ t: CGSize) {
        guard isOpen, !pinching else { return }
        if panNeedsRebase {
            panStartOrigin = CGPoint(x: origin.x - t.width, y: origin.y - t.height)
            panNeedsRebase = false
        }
        origin = CGPoint(x: panStartOrigin.x + t.width, y: panStartOrigin.y + t.height)
        if scale <= 1.01 {
            // 原大小时向下拖动：背景随之变淡，松手后缩回
            dim = max(0.2, 1 - Double(abs(t.height)) / 500)
        }
    }

    func panEnded(_ t: CGSize, onClosed: @escaping () -> Void) {
        panNeedsRebase = true
        guard isOpen, !pinching else { return }
        let moved = origin.y - panStartOrigin.y
        if scale <= 1.01, moved > 110 {
            close(then: onClosed)
        } else {
            settle()
        }
    }

    // MARK: - 点按

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

    // MARK: - 展开 / 收起

    func open() {
        if !presented {
            // 点按打开：覆盖层先在原位置出现，下一帧再动画展开
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
        // 导航栏重新出现后结果页里图片的位置会更新，稍等片刻再取目标位置
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
                    // 以屏幕中心为基准收回到上限
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

    /// 放大后不留空白：图片比屏幕大的方向不能露出边缘，比屏幕小的方向居中
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

// MARK: - 手势

/// iOS 18 起用系统的双指缩放识别器：能拿到两指中点的实时位置，缩放以手指为中心，最跟手。
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
    /// 双指缩放：iOS 18 起以两指中点为中心实时跟手；iOS 17 以起始位置为中心。
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

// MARK: - 覆盖层

/// 放大查看的覆盖层。只有它读取缩放 / 位置，手势中只有它在更新；图片和高亮框本身不重绘。
struct ScanZoomStage: View {
    let model: ScanZoomModel
    let image: UIImage
    let result: ScanResult
    let library: GrammarLibrary
    let selectedClusterID: Int?
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
                .accessibilityLabel(Text("关闭"))
                .padding()
                .padding(.top, 44)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if model.isOpen {
                Text("双指缩放查看原文，点击高亮查看讲解")
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

/// 图片 + 高亮框。输入不变时 SwiftUI 不会重绘它，手势中只做渲染变换。
private struct ScanZoomContent: View, Equatable {
    let image: UIImage
    let result: ScanResult
    let library: GrammarLibrary
    let selectedClusterID: Int?
    let settledScale: CGFloat
    let onSelect: (HighlightCluster) -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.image === b.image && a.selectedClusterID == b.selectedClusterID
            && a.settledScale == b.settledScale && a.result.boxes.count == b.result.boxes.count
            && a.result.text == b.result.text
    }

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .overlay {
                HighlightOverlay(
                    result: result,
                    imageSize: image.size,
                    fit: .fit,
                    library: library,
                    selectedClusterID: selectedClusterID,
                    lineWidth: 1.2 / max(settledScale, 1),
                    showsCountBadge: settledScale < 2.5
                ) { onSelect($0) }
            }
    }
}
