import SwiftUI

/// 新用户使用引导：首次启动时全屏显示，可左右滑动；设置页可重新打开。
struct OnboardingView: View {
    /// 用户点「开始使用」或「先用示例书页试试」时调用；参数表示是否要打开示例。
    let onFinish: (_ openSample: Bool) -> Void
    @EnvironmentObject private var store: EntitlementStore
    @State private var page = 0
    private let pageCount = 5

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < pageCount - 1 {
                    // 跳到最后一页（那里写明了试用时长与到期后的价格）
                    Button("跳过") { withAnimation { page = pageCount - 1 } }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
            }
            .frame(height: 44)

            TabView(selection: $page) {
                OnboardingPage(
                    title: "对准日文，语法一目了然",
                    message: "读日语书遇到看不懂的句子？用相机扫一下，文中的语法点会自动找出来并高亮。",
                    illustration: { WelcomeIllustration() }
                ).tag(0)
                OnboardingPage(
                    title: "扫描书本或截图",
                    message: "把相机对准书页，语法会实时高亮，颜色代表 JLPT 等级。按中间的快门定格画面做精细识别，也可以从相册选择截图。",
                    illustration: { ScanIllustration() }
                ).tag(1)
                OnboardingPage(
                    title: "点击高亮，查看讲解",
                    message: "每个语法点都有意思、用法、例句、使用场景、词源和相近语法对比。例句里的汉字都标注了假名。",
                    illustration: { DetailIllustration() }
                ).tag(2)
                OnboardingPage(
                    title: "语法库与收藏",
                    message: "在「语法库」按等级浏览或搜索全部语法，点 ☆ 收藏需要复习的语法。讲解会跟随手机语言显示。",
                    illustration: { LibraryIllustration() }
                ).tag(3)
                OnboardingPage(
                    title: "准备好了",
                    message: "手边没有日语书也没关系，可以先用内置的示例书页体验一下。",
                    illustration: { ReadyIllustration() }
                ).tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            PageDots(count: pageCount, current: page)
                .padding(.bottom, 20)

            VStack(spacing: 10) {
                if page < pageCount - 1 {
                    Button {
                        withAnimation { page += 1 }
                    } label: {
                        Text("下一步").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        onFinish(false)
                    } label: {
                        Text("免费开始使用").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("先用示例书页试试") { onFinish(true) }
                        .font(.subheadline.weight(.medium))
                        .padding(.top, 2)
                    trialNote
                }
            }
            .tint(Brand.red)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .frame(height: 150, alignment: .top)
        }
        .background(Color(.systemBackground))
    }

    /// 审核要求（Guideline 3.1.1）：试用开始前写明时长、到期后需要付费的内容与价格。
    private var trialNote: some View {
        Group {
            if store.access == .unlocked {
                EmptyView()
            } else if let price = store.lifetimeProduct?.displayPrice {
                Text("前 \(EntitlementStore.trialDays) 天免费使用全部功能。之后可一次性 \(price) 永久解锁完整讲解，不订阅、不自动扣费。")
            } else {
                Text("前 \(EntitlementStore.trialDays) 天免费使用全部功能。之后可一次性购买永久解锁完整讲解，不订阅、不自动扣费。")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 2)
    }
}

enum Brand {
    /// 统一使用主色
    static var red: Color { Theme.accent }
    static let paper = Color(red: 1.0, green: 0.988, blue: 0.96)
    static let marker = Color(red: 1.0, green: 0.80, blue: 0.27)
}

private struct OnboardingPage<Illustration: View>: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder let illustration: Illustration

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            illustration
                .frame(height: 300)
                .accessibilityHidden(true)
            VStack(spacing: 14) {
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            Spacer(minLength: 0)
        }
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Brand.red : Color.secondary.opacity(0.3))
                    .frame(width: i == current ? 22 : 8, height: 8)
            }
        }
        .animation(.spring(duration: 0.3), value: current)
    }
}

// MARK: - 插图（纯 SwiftUI 绘制，支持深色模式与动态效果）

/// 取景框四角
private struct ViewfinderCorners: Shape {
    var length: CGFloat = 26
    func path(in r: CGRect) -> Path {
        var p = Path()
        let l = length
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

/// 一行“书页文字”，其中一段被高亮
private struct TextLine: View {
    let text: String
    var highlight: String? = nil
    var color: Color = Theme.accent

    var body: some View {
        HStack(spacing: 0) {
            if let h = highlight, let range = text.range(of: h) {
                Text(text[..<range.lowerBound])
                Text(h)
                    .padding(.horizontal, 2)
                    .background(color.opacity(0.28), in: RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(color, lineWidth: 1.2))
                Text(text[range.upperBound...])
            } else {
                Text(text)
            }
        }
        .font(.system(size: 17, weight: .medium, design: .serif))
        .foregroundStyle(Color(white: 0.15))
    }
}

private struct BookPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextLine(text: "駅に着いたとき、", highlight: nil)
            TextLine(text: "雨が降りそうだった。", highlight: "そうだ", color: Theme.accent)
            TextLine(text: "傘を買っておいた。", highlight: "ておい", color: Theme.accent)
            TextLine(text: "道に迷ってしまった。", highlight: "てしまっ", color: Theme.accent)
        }
        .padding(22)
        .background(Brand.paper, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

private struct WelcomeIllustration: View {
    var body: some View {
        ZStack {
            Circle().fill(Brand.red.opacity(0.12)).frame(width: 280, height: 280)
            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .shadow(color: Brand.red.opacity(0.35), radius: 16, y: 8)
        }
    }
}

private struct ScanIllustration: View {
    @State private var scanY: CGFloat = -70

    var body: some View {
        ZStack {
            BookPage()
            ViewfinderCorners()
                .stroke(Brand.red, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .frame(width: 280, height: 210)
            Capsule()
                .fill(Brand.red)
                .frame(width: 270, height: 3)
                .shadow(color: Brand.red, radius: 6)
                .offset(y: scanY)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { scanY = 70 }
        }
    }
}

private struct DetailIllustration: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(verbatim: "〜てしまう").font(.title2.bold())
                LevelBadge(level: .n4)
            }
            ForEach(Array([("lightbulb.max.fill", Color.secondary), ("list.bullet.rectangle.portrait.fill", .secondary),
                           ("person.2.wave.2.fill", .secondary), ("scroll.fill", .secondary), ("arrow.triangle.branch", .secondary)].enumerated()),
                    id: \.offset) { i, item in
                HStack(spacing: 10) {
                    Image(systemName: item.0)
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(item.1)
                        .frame(width: 28, height: 28)
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.22))
                        .frame(width: CGFloat([150, 180, 130, 165, 140][i]), height: 10)
                }
            }
        }
        .padding(22)
        .frame(width: 290, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct LibraryIllustration: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array([("〜ようになる", JLPTLevel.n4, true), ("〜にもかかわらず", .n3, true), ("〜おかげで", .n3, false), ("〜たい", .n5, false)].enumerated()), id: \.offset) { _, row in
                HStack {
                    HStack(alignment: .top, spacing: 3) {
                        Text(verbatim: row.0).font(.headline)
                        LevelBadge(level: row.1, small: true)
                    }
                    Spacer()
                    Image(systemName: row.2 ? "star.fill" : "star")
                        .foregroundStyle(row.2 ? Theme.accent : Color.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(width: 290)
    }
}

private struct ReadyIllustration: View {
    var body: some View {
        ZStack {
            BookPage().rotationEffect(.degrees(-4))
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 44))
                .foregroundStyle(Brand.red)
                .offset(x: 70, y: 40)
        }
    }
}
