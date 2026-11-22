import SwiftUI

/// 樱花（Build 18 反馈 1、2）：首页复习提醒里飘过的樱花、收藏图标、收藏时飘进「收藏」标签的花瓣。
/// 颜色固定为日本樱花的粉色，不跟主题色走（主题色可能是抹茶绿、柿子橙）。
enum Sakura {
    /// 花瓣
    static let petal = Color(red: 0xF6 / 255, green: 0xB3 / 255, blue: 0xC6 / 255)
    /// 花心、描边
    static let center = Color(red: 0xE8 / 255, green: 0x7A / 255, blue: 0x9A / 255)

    /// 一片花瓣：根部在 (0, 0)，尖端朝上、长度为 r，尖端中间有一个小缺口（樱花瓣的特征）
    static func petalPath(length r: CGFloat) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addQuadCurve(to: CGPoint(x: -0.16 * r, y: -r), control: CGPoint(x: -0.62 * r, y: -0.5 * r))
        p.addLine(to: CGPoint(x: 0, y: -0.84 * r))
        p.addLine(to: CGPoint(x: 0.16 * r, y: -r))
        p.addQuadCurve(to: .zero, control: CGPoint(x: 0.62 * r, y: -0.5 * r))
        p.closeSubpath()
        return p
    }
}

/// 五瓣樱花（填满 rect 的最大正方形）
struct SakuraFlowerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var out = Path()
        let petal = Sakura.petalPath(length: r)
        for k in 0..<5 {
            let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: CGFloat(k) * .pi * 2 / 5)
            out.addPath(petal, transform: t)
        }
        return out
    }
}

/// 一片散落的花瓣（根部在 rect 下方中间）
struct SakuraPetalShape: Shape {
    func path(in rect: CGRect) -> Path {
        Sakura.petalPath(length: rect.height)
            .applying(CGAffineTransform(translationX: rect.midX, y: rect.maxY))
    }
}

/// 一朵樱花：实心粉色 + 花心；`outline` 时只有线条（未收藏的样子，用当前文字颜色）
struct SakuraFlower: View {
    var size: CGFloat
    var outline = false
    var lineWidth: CGFloat = 1.6

    var body: some View {
        ZStack {
            if outline {
                SakuraFlowerShape().stroke(style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
                Circle().frame(width: size * 0.16, height: size * 0.16)
            } else {
                SakuraFlowerShape().fill(Sakura.petal)
                SakuraFlowerShape().stroke(Sakura.center.opacity(0.35), lineWidth: max(0.5, size / 40))
                Circle().fill(Sakura.center).frame(width: size * 0.22, height: size * 0.22)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 樱花飘过的轨迹（首页复习提醒）：几朵樱花和几片花瓣从左边飘到右边，边飘边转，上下轻轻起伏。
/// 纯计算，方便单元测试。
struct SakuraDrift {
    enum Kind { case flower, petal }

    struct Particle {
        let kind: Kind
        let size: CGFloat
        /// 出发时间（秒）
        let delay: Double
        /// 纵向位置（0 = 顶，1 = 底）
        let lane: CGFloat
        /// 上下起伏的幅度（pt）
        let sway: CGFloat
        /// 转动圈数（整段路程）
        let turns: Double
        let phase: Double
    }

    /// 铃铛先摇（0–0.7 秒），樱花接着出发
    static let start: Double = 0.45
    /// 每朵花从左到右用的时间
    static let travel: Double = 2.6
    static let particles: [Particle] = [
        .init(kind: .flower, size: 18, delay: start + 0.00, lane: 0.30, sway: 5, turns: 0.6, phase: 0.0),
        .init(kind: .petal, size: 9, delay: start + 0.15, lane: 0.72, sway: 6, turns: 1.2, phase: 0.3),
        .init(kind: .flower, size: 13, delay: start + 0.35, lane: 0.62, sway: 4, turns: -0.5, phase: 0.6),
        .init(kind: .petal, size: 8, delay: start + 0.55, lane: 0.22, sway: 5, turns: -1.0, phase: 0.1),
        .init(kind: .flower, size: 15, delay: start + 0.75, lane: 0.45, sway: 6, turns: 0.7, phase: 0.8),
        .init(kind: .petal, size: 10, delay: start + 0.90, lane: 0.80, sway: 4, turns: 1.4, phase: 0.45),
        .init(kind: .flower, size: 11, delay: start + 1.10, lane: 0.28, sway: 5, turns: -0.6, phase: 0.25),
        .init(kind: .petal, size: 8, delay: start + 1.25, lane: 0.55, sway: 6, turns: -1.3, phase: 0.7),
    ]
    /// 整段动画的时长（约 4 秒）
    static var duration: Double { (particles.map(\.delay).max() ?? 0) + travel }

    struct State: Equatable {
        var x: CGFloat
        var y: CGFloat
        var angle: Double
        var opacity: Double
    }

    /// 第 i 朵在 elapsed 秒时的位置；还没出发或已经飘出去时返回 nil
    static func state(_ p: Particle, elapsed: Double, in size: CGSize) -> State? {
        let unclamped = (elapsed - p.delay) / travel
        guard unclamped >= 0, unclamped <= 1 + 1e-9 else { return nil }
        let t = min(unclamped, 1)
        let x = -p.size + CGFloat(t) * (size.width + 2 * p.size)
        let y = p.lane * size.height + p.sway * CGFloat(sin(2 * .pi * (t * 1.3 + p.phase)))
        // 两头淡入淡出
        let opacity = min(1, min(t, 1 - t) / 0.12)
        return State(x: x, y: y, angle: 360 * p.turns * t, opacity: opacity)
    }

    /// 铃铛摇的角度（前 0.7 秒左右来回摆，越摆越小）
    static func bellAngle(elapsed: Double) -> Double {
        let d = 0.7
        guard elapsed >= 0, elapsed < d else { return 0 }
        return 16 * sin(elapsed * 2 * .pi * 4) * (1 - elapsed / d)
    }
}

/// 首页复习提醒上飘过的樱花层（不接收点击，读屏不读）
struct SakuraDriftOverlay: View {
    let start: Date

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(start)
            GeometryReader { geo in
                ForEach(Array(SakuraDrift.particles.enumerated()), id: \.offset) { _, p in
                    if let s = SakuraDrift.state(p, elapsed: elapsed, in: geo.size) {
                        particle(p)
                            .rotationEffect(.degrees(s.angle))
                            .opacity(s.opacity)
                            .position(x: s.x, y: s.y)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func particle(_ p: SakuraDrift.Particle) -> some View {
        switch p.kind {
        case .flower: SakuraFlower(size: p.size)
        case .petal:
            SakuraPetalShape().fill(Sakura.petal)
                .overlay(SakuraPetalShape().stroke(Sakura.center.opacity(0.35), lineWidth: 0.5))
                .frame(width: p.size * 0.7, height: p.size)
        }
    }
}

/// 动画只在用户没有打开「减弱动态效果」时播放；端到端测试里默认不播（避免拖慢测试），
/// 传 `-playAnimations` 时照常播放。
enum DecorativeMotion {
    static func enabled(reduceMotion: Bool, arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        if reduceMotion { return false }
        let e2e = arguments.contains("-e2e") || arguments.contains("-e2eFresh")
        return !e2e || arguments.contains("-playAnimations")
    }
}
