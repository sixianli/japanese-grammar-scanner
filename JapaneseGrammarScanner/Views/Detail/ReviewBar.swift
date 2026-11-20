import SwiftUI

/// 讲解页底部的复习自评条（只在从首页「快要忘了」进来时出现，复习时底部标签栏隐藏）。
/// 先问「还记得吗」，三个按钮：忘了 / 有点模糊 / 记得（固定红黄绿三色，不随主题；不显示下次复习时间）。
/// 自评后：还有要复习的 → 「先到这里」或「下一个：…」；都复习完 → 「回首页」。
struct ReviewBar: View {
    let grammarID: String
    /// 之后还要复习的语法
    let queue: [String]
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var library: GrammarLibrary
    @Environment(\.replaceRoute) private var replaceRoute
    @Environment(\.pushRoute) private var pushRoute
    @State private var rated: FSRS.Grade?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let rated {
                ratedView(rated)
            } else {
                question
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.card
                .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) { Divider() }
        // 点评分按钮时震动：三个按钮手感不同
        .sensoryFeedback(trigger: rated) { _, new in new.map(Self.haptic) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.bar")
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized: "看完了，你还记得这个语法吗？")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                ForEach(FSRS.Grade.allCases, id: \.self) { g in
                    Button {
                        history.rate(grammarID, g)
                        withAnimation(.easeInOut(duration: 0.2)) { rated = g }
                    } label: {
                        Text(localized: Self.label(g))
                            .font(.body.weight(.bold))
                            .foregroundStyle(Self.color(g))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Self.color(g).opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("review.grade.\(g.rawValue)")
                }
            }
        }
    }

    @ViewBuilder
    private func ratedView(_ g: FSRS.Grade) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Self.color(g))
                .frame(width: 30, height: 30)
                .background(Self.color(g).opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                (Text(localized: "已记录：") + Text(localized: Self.label(g)))
                    .font(.subheadline.weight(.semibold))
                if queue.isEmpty {
                    Text(localized: "今天的复习都完成了").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text(localized: "还剩 \(queue.count) 个要复习").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("review.done")
        }
        if let next = queue.first {
            HStack(spacing: 8) {
                Button { goHome() } label: {
                    Text(localized: "先到这里")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 48)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("review.stop")
                Button {
                    let route = Route.review(next, Array(queue.dropFirst()))
                    if let replaceRoute { replaceRoute(route) } else { pushRoute?(route) }
                } label: {
                    HStack(spacing: 4) {
                        Text(localized: "下一个：") + Text(verbatim: library.point(id: next)?.titleForm ?? next)
                        Image(systemName: "chevron.right").font(.footnote.weight(.bold))
                    }
                    .font(.body.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.accentText, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("review.next")
            }
        } else {
            Button { goHome() } label: {
                Text(localized: "回首页")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.accentText, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("review.home")
        }
    }

    private func goHome() {
        NotificationCenter.default.post(name: .popToRoot, object: AppTab.home)
    }

    static func label(_ g: FSRS.Grade) -> LocalizedStringKey {
        switch g {
        case .again: "忘了"
        case .hard: "有点模糊"
        case .good: "记得"
        }
    }

    /// 固定三色，不随主题：忘了＝柔和珊瑚红，有点模糊＝琥珀黄，记得＝抹茶绿（浅色 / 深色模式各一档，文字对比度 ≥ 4.5:1）
    static let colorHex: [FSRS.Grade: (light: UInt32, dark: UInt32)] = [
        .again: (0xB4553F, 0xE8947F),
        .hard: (0x8F6514, 0xE3BC62),
        .good: (0x4F7236, 0xA6C98A),
    ]

    static func color(_ g: FSRS.Grade) -> Color {
        let hex = colorHex[g]!
        return Theme.dynamic(hex.light, hex.dark)
    }

    /// 震动：忘了＝轻柔一下，有点模糊＝普通轻震，记得＝成功提示
    static func haptic(_ g: FSRS.Grade) -> SensoryFeedback {
        switch g {
        case .again: .impact(flexibility: .soft, intensity: 0.6)
        case .hard: .impact(weight: .light)
        case .good: .success
        }
    }
}
