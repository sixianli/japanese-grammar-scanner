import SwiftUI
import UIKit

/// 收藏 = 收集樱花（Build 18 反馈 2）：点收藏后，樱花化作两朵小樱花和三片花瓣，沿一条弧线（一段，不停顿）
/// 飘进底部「收藏」标签的小布袋（巾着袋）；到达时小布袋轻轻鼓一下、变粉。取消收藏不播；
/// 「减弱动态效果」打开时不播；不震动。
@MainActor
final class FavoriteFlight: ObservableObject {
    struct Flight: Identifiable, Equatable {
        let id = UUID()
        let from: CGPoint
        let to: CGPoint
        let start: Date
    }

    @Published private(set) var flights: [Flight] = []

    /// 点了收藏按钮：只有「从没收藏变成收藏」才飞
    nonisolated static func shouldLaunch(wasFavorite: Bool, reduceMotion: Bool, arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        !wasFavorite && DecorativeMotion.enabled(reduceMotion: reduceMotion, arguments: arguments)
    }

    func launch(from: CGPoint) {
        let to = TabBarLocator.favoritesTabCenter() ?? TabBarLocator.estimatedFavoritesTabCenter()
        let f = Flight(from: from, to: to, start: Date())
        flights.append(f)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(FlightPath.total + 0.1))
            self?.flights.removeAll { $0.id == f.id }
        }
    }
}

/// 飞行轨迹（纯计算，方便单元测试）：一条向上拱起的二次贝塞尔曲线，几片樱花前后错开，像一串。
enum FlightPath {
    enum Kind { case flower, petal }
    struct Particle {
        let kind: Kind
        let size: CGFloat
        let delay: Double
        /// 偏离主轨迹的距离（pt），让几片不完全重合
        let drift: CGFloat
        let turns: Double
    }

    /// 每片飞的时间
    static let flight: Double = 0.9
    static let particles: [Particle] = [
        .init(kind: .flower, size: 16, delay: 0.00, drift: 0, turns: 0.5),
        .init(kind: .petal, size: 9, delay: 0.06, drift: 10, turns: 1.2),
        .init(kind: .flower, size: 12, delay: 0.12, drift: -8, turns: -0.6),
        .init(kind: .petal, size: 8, delay: 0.18, drift: 14, turns: -1.1),
        .init(kind: .petal, size: 8, delay: 0.24, drift: -12, turns: 1.4),
    ]
    /// 最后一片到达的时间
    static var arrival: Double { (particles.map(\.delay).max() ?? 0) + flight }
    /// 到达后小布袋鼓一下、变粉的时间
    static let puff: Double = 0.35
    /// 整段约 1.2 秒（+ 鼓一下）
    static var total: Double { arrival + puff }

    /// 弧线的控制点：从起点往左下方拱出去（起点在右上角，终点在底部）
    static func control(from a: CGPoint, to b: CGPoint) -> CGPoint {
        CGPoint(x: min(a.x, b.x) - 0.15 * abs(a.x - b.x) - 30, y: a.y + 0.35 * (b.y - a.y))
    }

    /// 第 i 片在 elapsed 秒时的位置、角度、大小、透明度；没出发或已到达时返回 nil
    static func state(_ p: Particle, elapsed: Double, from a: CGPoint, to b: CGPoint) -> (point: CGPoint, angle: Double, scale: CGFloat, opacity: Double)? {
        let unclamped = (elapsed - p.delay) / flight
        guard unclamped >= 0, unclamped <= 1 + 1e-9 else { return nil }
        let raw = min(unclamped, 1)
        // 先快后慢地落进袋子
        let t = 1 - pow(1 - raw, 2)
        let c = control(from: a, to: b)
        let u = 1 - t
        var x = u * u * a.x + 2 * u * t * c.x + t * t * b.x
        var y = u * u * a.y + 2 * u * t * c.y + t * t * b.y
        // 中途左右散开一点，越接近袋子越收拢
        let spread = p.drift * CGFloat(sin(.pi * t))
        x += spread
        y += spread * 0.3
        let scale = 1 - 0.45 * CGFloat(t)
        let opacity = raw > 0.9 ? (1 - raw) / 0.1 : 1
        return (CGPoint(x: x, y: y), 360 * p.turns * t, scale, opacity)
    }

    /// 到达后小布袋鼓起的比例（0 = 不显示）
    static func puffScale(elapsed: Double) -> CGFloat? {
        let e = elapsed - arrival + 0.15
        guard e >= 0, e <= puff else { return nil }
        return 1 + 0.25 * CGFloat(sin(.pi * e / puff))
    }
}

/// 根视图上的一层：显示正在飞的樱花和到达时鼓起的小布袋（不接收点击，读屏不读）
struct FavoriteFlightOverlay: View {
    @ObservedObject var model: FavoriteFlight

    var body: some View {
        ZStack {
            ForEach(model.flights) { f in
                TimelineView(.animation) { context in
                    let e = context.date.timeIntervalSince(f.start)
                    ZStack {
                        ForEach(Array(FlightPath.particles.enumerated()), id: \.offset) { _, p in
                            if let s = FlightPath.state(p, elapsed: e, from: f.from, to: f.to) {
                                particle(p)
                                    .scaleEffect(s.scale)
                                    .rotationEffect(.degrees(s.angle))
                                    .opacity(s.opacity)
                                    .position(s.point)
                            }
                        }
                        if let puff = FlightPath.puffScale(elapsed: e) {
                            KinchakuShape()
                                .fill(Sakura.petal)
                                .overlay(KinchakuShape().stroke(Sakura.center, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)))
                                .frame(width: 25, height: 25)
                                .scaleEffect(puff)
                                .position(f.to)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func particle(_ p: FlightPath.Particle) -> some View {
        switch p.kind {
        case .flower: SakuraFlower(size: p.size)
        case .petal:
            SakuraPetalShape().fill(Sakura.petal)
                .overlay(SakuraPetalShape().stroke(Sakura.center.opacity(0.35), lineWidth: 0.5))
                .frame(width: p.size * 0.7, height: p.size)
        }
    }
}

/// 巾着袋（和标签栏图标 Kinchaku.imageset 的 SVG 同一个形状，25×25 坐标）
struct KinchakuShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 25
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        // 袋身
        path.move(to: p(8.6, 9.2))
        path.addCurve(to: p(5.1, 18.6), control1: p(5.4, 11.6), control2: p(4.4, 15.2))
        path.addCurve(to: p(12.5, 22.8), control1: p(5.8, 21.6), control2: p(8.6, 22.8))
        path.addCurve(to: p(19.9, 18.6), control1: p(16.4, 22.8), control2: p(19.2, 21.6))
        path.addCurve(to: p(16.4, 9.2), control1: p(20.6, 15.2), control2: p(19.6, 11.6))
        path.addCurve(to: p(8.6, 9.2), control1: p(15.2, 9.9), control2: p(9.8, 9.9))
        // 收口上面的褶边
        path.move(to: p(8.6, 9.2))
        path.addLine(to: p(7.2, 4.6))
        path.addCurve(to: p(10.4, 4.2), control1: p(8.6, 5.4), control2: p(9.6, 5.2))
        path.addCurve(to: p(14.6, 4.2), control1: p(11.2, 5.2), control2: p(13.8, 5.2))
        path.addCurve(to: p(17.8, 4.6), control1: p(15.4, 5.2), control2: p(16.4, 5.4))
        path.addLine(to: p(16.4, 9.2))
        return path
    }
}

/// 找底部「收藏」标签在屏幕上的位置（樱花飞去的终点）
enum TabBarLocator {
    @MainActor
    static func favoritesTabCenter() -> CGPoint? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow) else { return nil }
        var found: UIView?
        func search(_ v: UIView) {
            if found != nil { return }
            if v.accessibilityIdentifier == "Kinchaku" || (v is UIControl && v.accessibilityLabel == tr("收藏") && v.accessibilityIdentifier != "detail.favorite") {
                found = v
                return
            }
            v.subviews.forEach(search)
        }
        search(window)
        guard let v = found, !v.isHidden, v.window != nil else { return nil }
        let r = v.convert(v.bounds, to: window)
        return r.isEmpty ? nil : CGPoint(x: r.midX, y: r.midY)
    }

    /// 找不到时按常见布局估一个：底部标签栏，五个标签里的第四个
    @MainActor
    static func estimatedFavoritesTabCenter() -> CGPoint {
        let screen = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.bounds
            ?? CGRect(x: 0, y: 0, width: 390, height: 844)
        return CGPoint(x: screen.width * 0.62, y: screen.height - 50)
    }
}

/// 收藏按钮：未收藏 = 线条樱花，已收藏 = 粉色樱花。点了收藏时樱花飘进底部「收藏」标签。
struct FavoriteSakuraButton: View {
    let id: String
    var size: CGFloat = 22
    var outlineColor: Color = Theme.accentText
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var flight: FavoriteFlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var center: CGPoint = .zero

    var body: some View {
        let isFavorite = favorites.isFavorite(id)
        Button {
            let launch = FavoriteFlight.shouldLaunch(wasFavorite: isFavorite, reduceMotion: reduceMotion)
            favorites.toggle(id)
            if launch { flight.launch(from: center) }
        } label: {
            SakuraFlower(size: size, outline: !isFavorite)
                .foregroundStyle(outlineColor)
                .frame(width: max(size, 28), height: max(size, 28))
                .contentShape(Rectangle())
                .onGeometryChange(for: CGPoint.self) { g in
                    let r = g.frame(in: .global)
                    return CGPoint(x: r.midX, y: r.midY)
                } action: { center = $0 }
        }
        .accessibilityLabel(isFavorite ? Text(localized: "取消收藏") : Text(localized: "收藏"))
    }
}
