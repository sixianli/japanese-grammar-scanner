import SwiftUI
import UIKit

@MainActor
final class FavoriteFlight: ObservableObject {
    enum Style: Equatable { case intoPouch, away }

    struct Flight: Identifiable, Equatable {
        let id = UUID()
        let style: Style
        let from: CGPoint
        let to: CGPoint
        let start: Date
    }

    @Published private(set) var flights: [Flight] = []
    @Published private(set) var toast: UUID?

    nonisolated static let toastDuration: Double = 2.4

    nonisolated static func shouldLaunch(wasFavorite: Bool, reduceMotion: Bool, arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        !wasFavorite && DecorativeMotion.enabled(reduceMotion: reduceMotion, arguments: arguments)
    }

    func launch(from: CGPoint, style: Style = .intoPouch) {
        let to = style == .intoPouch ? (TabBarLocator.pouchMouth() ?? TabBarLocator.estimatedPouchMouth()) : from
        let f = Flight(style: style, from: from, to: to, start: Date())
        flights.append(f)
        if style == .intoPouch {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(FlightPath.arrival(.intoPouch) - 0.15))
                self?.catchInPouch()
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(FlightPath.total(style) + 0.1))
            self?.flights.removeAll { $0.id == f.id }
        }
    }

    func confirmSaved() {
        let token = UUID()
        toast = token
        UIAccessibility.post(notification: .announcement, argument: tr("已收进收藏"))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.toastDuration))
            if self?.toast == token { self?.toast = nil }
        }
    }

    private func catchInPouch() {
        guard DecorativeMotion.enabled(reduceMotion: UIAccessibility.isReduceMotionEnabled),
              let icon = TabBarLocator.pouchIcon() else { return }
        PouchDip.play(on: icon.layer)
    }
}

enum FlightPath {
    enum Kind { case flower, petal }
    struct Particle {
        let kind: Kind
        let size: CGFloat
        let delay: Double
        let duration: Double
        let drift: CGFloat
        let turns: Double
    }

    static let flowerSize: CGFloat = 40
    static let buttonScale: CGFloat = 0.55
    static let landing: Double = 0.9

    static func particles(_ style: FavoriteFlight.Style) -> [Particle] {
        switch style {
        case .intoPouch:
            [.init(kind: .flower, size: flowerSize, delay: 0, duration: 2.1, drift: 0, turns: 0.7),
             .init(kind: .petal, size: 18, delay: 0.30, duration: 2.4, drift: -46, turns: 1.3),
             .init(kind: .petal, size: 17, delay: 0.40, duration: 2.6, drift: 38, turns: -1.5),
             .init(kind: .petal, size: 16, delay: 0.50, duration: 2.3, drift: -70, turns: 1.7)]
        case .away:
            [.init(kind: .flower, size: flowerSize, delay: 0, duration: 2.0, drift: 0, turns: 0.75),
             .init(kind: .petal, size: 18, delay: 0.30, duration: 2.2, drift: -60, turns: 1.2),
             .init(kind: .petal, size: 16, delay: 0.40, duration: 2.4, drift: 30, turns: -1.4)]
        }
    }

    static func arrival(_ style: FavoriteFlight.Style) -> Double {
        particles(style).map { $0.delay + $0.duration }.max() ?? 0
    }

    static func total(_ style: FavoriteFlight.Style) -> Double {
        arrival(style) + (style == .intoPouch ? landing : 0)
    }

    static func control(from a: CGPoint, to b: CGPoint) -> CGPoint {
        CGPoint(x: min(a.x, b.x) - 0.15 * abs(a.x - b.x) - 30, y: a.y + 0.35 * (b.y - a.y))
    }

    static func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    static func state(_ p: Particle, style: FavoriteFlight.Style, elapsed: Double, from a: CGPoint, to b: CGPoint)
        -> (point: CGPoint, angle: Double, scale: CGFloat, opacity: Double)? {
        let unclamped = (elapsed - p.delay) / p.duration
        guard unclamped >= 0, unclamped <= 1 + 1e-9 else { return nil }
        let raw = min(unclamped, 1)
        switch style {
        case .intoPouch: return intoPouch(p, raw: raw, from: a, to: b)
        case .away: return away(p, raw: raw, from: a)
        }
    }

    private static func intoPouch(_ p: Particle, raw: Double, from a: CGPoint, to b: CGPoint)
        -> (point: CGPoint, angle: Double, scale: CGFloat, opacity: Double) {
        let t = smooth(raw)
        let c = control(from: a, to: b)
        let u = 1 - t
        let spread = p.drift * CGFloat(sin(.pi * t))
        let x = u * u * a.x + 2 * u * t * c.x + t * t * b.x + spread
        let y = u * u * a.y + 2 * u * t * c.y + t * t * b.y + spread * 0.3
        let scale: CGFloat
        let opacity: Double
        switch p.kind {
        case .flower:
            if raw < 0.12 {
                scale = buttonScale + (1 - buttonScale) * CGFloat(raw / 0.12)
            } else {
                scale = 1 - 0.6 * CGFloat(pow((raw - 0.12) / 0.88, 2.2))
            }
            opacity = raw > 0.9 ? (1 - raw) / 0.1 : 1
        case .petal:
            scale = 1 - 0.4 * CGFloat(t)
            opacity = raw < 0.1 ? raw / 0.1 : (raw > 0.85 ? (1 - raw) / 0.15 : 1)
        }
        return (CGPoint(x: x, y: y), 360 * p.turns * t, scale, opacity)
    }

    private static func away(_ p: Particle, raw: Double, from a: CGPoint)
        -> (point: CGPoint, angle: Double, scale: CGFloat, opacity: Double) {
        switch p.kind {
        case .flower:
            let t = smooth(raw)
            let x = a.x - 120 * CGFloat(t)
            let y = a.y + 140 * CGFloat(sin(.pi * 0.75 * t))
            let scale = raw < 0.2 ? buttonScale + (1 - buttonScale) * CGFloat(raw / 0.2) : 1 - 0.65 * CGFloat((raw - 0.2) / 0.8)
            let opacity = raw < 0.6 ? 1 : (1 - raw) / 0.4
            return (CGPoint(x: x, y: y), 360 * p.turns * t, scale, opacity)
        case .petal:
            let x = a.x + p.drift * CGFloat(sin(.pi * raw)) - 40 * CGFloat(raw)
            let y = a.y + 30 + 220 * CGFloat(raw)
            let opacity = raw < 0.1 ? raw / 0.1 : (raw > 0.7 ? (1 - raw) / 0.3 : 1)
            return (CGPoint(x: x, y: y), 360 * p.turns * raw, 1, opacity)
        }
    }
}

struct FavoriteFlightOverlay: View {
    @ObservedObject var model: FavoriteFlight

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                ForEach(model.flights) { f in
                    TimelineView(.animation) { context in
                        let e = context.date.timeIntervalSince(f.start)
                        ZStack {
                            ForEach(Array(FlightPath.particles(f.style).enumerated()), id: \.offset) { _, p in
                                if let s = FlightPath.state(p, style: f.style, elapsed: e, from: f.from, to: f.to) {
                                    particle(p)
                                        .scaleEffect(s.scale)
                                        .rotationEffect(.degrees(s.angle))
                                        .opacity(s.opacity)
                                        .position(s.point)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .accessibilityHidden(true)

            if DemoMode.e2e, let target = model.flights.last(where: { $0.style == .intoPouch })?.to {
                Color.clear
                    .frame(width: 2, height: 2)
                    .position(target)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: "flight target"))
                    .accessibilityIdentifier("favorite.flightTarget")
            }

            if model.toast != nil {
                SavedToast()
                    .padding(.top, 52)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: model.toast)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func particle(_ p: FlightPath.Particle) -> some View {
        switch p.kind {
        case .flower: SakuraFlower(size: p.size)
        case .petal:
            SakuraPetalShape().fill(Sakura.petal)
                .overlay(SakuraPetalShape().stroke(Sakura.center.opacity(0.45), lineWidth: 0.6))
                .frame(width: p.size * 0.7, height: p.size)
        }
    }
}

private struct SavedToast: View {
    var body: some View {
        HStack(spacing: 6) {
            Image("Kinchaku").renderingMode(.template).resizable().scaledToFit().frame(height: 16)
            Text(localized: "已收进收藏")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.78), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("favorite.toast")
    }
}

enum PouchDip {
    static let duration: Double = 0.35
    static let squash: Double = 0.1

    static func scale(progress p: Double) -> (x: Double, y: Double) {
        let t = min(1, max(0, p))
        let y = 1 - squash * sin(.pi * t) + 0.03 * sin(2 * .pi * t) * (1 - t)
        return (2 - y, y)
    }

    @MainActor
    static func play(on layer: CALayer) {
        let steps = 12
        let height = layer.bounds.height
        let values: [CATransform3D] = (0...steps).map { i in
            let s = scale(progress: Double(i) / Double(steps))
            let lift = height * (1 - s.y) / 2
            return CATransform3DConcat(CATransform3DMakeScale(s.x, s.y, 1), CATransform3DMakeTranslation(0, lift, 0))
        }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = values
        animation.duration = duration
        animation.calculationMode = .linear
        layer.add(animation, forKey: "pouchDip")
    }
}

enum TabBarLocator {
    static let mouthDepth: CGFloat = 0.25

    @MainActor
    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
    }

    @MainActor
    static func favoritesTabButton() -> UIView? {
        guard let window = keyWindow else { return nil }
        var found: UIView?
        func isFavoritesTab(_ v: UIView) -> Bool {
            if v.accessibilityIdentifier == "detail.favorite" { return false }
            if v.accessibilityIdentifier?.hasPrefix("Kinchaku") == true { return true }
            return v.isAccessibilityElement && v.accessibilityLabel == tr("收藏")
                && v.accessibilityTraits.contains(.button) && hasTabBarAncestor(v)
        }
        func search(_ v: UIView) {
            if found != nil || v.isHidden { return }
            if isFavoritesTab(v) {
                found = v
                return
            }
            v.subviews.forEach(search)
        }
        search(window)
        return found
    }

    @MainActor
    private static func hasTabBarAncestor(_ v: UIView) -> Bool {
        var p = v.superview
        while let current = p {
            if current is UITabBar { return true }
            p = current.superview
        }
        return false
    }

    @MainActor
    static func pouchIcon() -> UIView? {
        guard let button = favoritesTabButton() else { return nil }
        if button is UIImageView { return button }
        var icon: UIImageView?
        func search(_ v: UIView) {
            if icon != nil { return }
            if let iv = v as? UIImageView, iv.image != nil, !iv.isHidden, iv.bounds.width > 8 {
                icon = iv
                return
            }
            v.subviews.forEach(search)
        }
        search(button)
        return icon
    }

    @MainActor
    static func pouchMouth() -> CGPoint? {
        guard let window = keyWindow else { return nil }
        if let icon = pouchIcon(), icon.window != nil {
            let r = icon.convert(icon.bounds, to: window)
            if !r.isEmpty { return mouth(ofIcon: r) }
        }
        guard let button = favoritesTabButton(), button.window != nil else { return nil }
        let r = button.convert(button.bounds, to: window)
        guard !r.isEmpty else { return nil }
        return CGPoint(x: r.midX, y: r.minY + r.height * 0.3)
    }

    static func mouth(ofIcon r: CGRect) -> CGPoint {
        CGPoint(x: r.midX, y: r.minY + r.height * mouthDepth)
    }

    static func estimatedMouth(tabBar: CGRect, tabCount: Int, index: Int) -> CGPoint {
        let width = tabBar.width / CGFloat(max(tabCount, 1))
        return CGPoint(x: tabBar.minX + width * (CGFloat(index) + 0.5), y: tabBar.minY + tabBar.height * 0.3)
    }

    @MainActor
    static func estimatedPouchMouth() -> CGPoint {
        let screen = keyWindow?.bounds ?? CGRect(x: 0, y: 0, width: 390, height: 844)
        let bar = CGRect(x: 0, y: screen.height - 83, width: screen.width, height: 49)
        return estimatedMouth(tabBar: bar, tabCount: AppTab.count, index: AppTab.favorites)
    }
}

struct FavoriteSakuraButton: View {
    let id: String
    var size: CGFloat? = nil
    var outlineColor: Color = Theme.accentText
    var flightStyle: FavoriteFlight.Style = .intoPouch
    var confirmsSaved = false
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var flight: FavoriteFlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var center: CGPoint = .zero

    var body: some View {
        let isFavorite = favorites.isFavorite(id)
        Button {
            let launch = FavoriteFlight.shouldLaunch(wasFavorite: isFavorite, reduceMotion: reduceMotion)
            favorites.toggle(id)
            if launch { flight.launch(from: center, style: flightStyle) }
            if !isFavorite, confirmsSaved { flight.confirmSaved() }
        } label: {
            icon(isFavorite)
        }
        .foregroundStyle(outlineColor)
        .onGeometryChange(for: CGPoint.self) { g in
            let r = g.frame(in: .global)
            return CGPoint(x: r.midX, y: r.midY)
        } action: { center = $0 }
        .accessibilityLabel(isFavorite ? Text(localized: "取消收藏") : Text(localized: "收藏"))
    }

    @ViewBuilder
    private func icon(_ isFavorite: Bool) -> some View {
        let image = Image(isFavorite ? "SakuraFilled" : "SakuraOutline")
        if let size {
            image.resizable().frame(width: size, height: size)
                .frame(width: max(size, 28), height: max(size, 28))
                .contentShape(Rectangle())
        } else {
            image
        }
    }
}
