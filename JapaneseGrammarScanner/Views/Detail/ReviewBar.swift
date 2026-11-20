import SwiftUI

/// 讲解页底部的复习自评条（只在复习时出现：从首页「快要忘了」点进来，或打开的语法正好到了复习时间）。
/// 先问「还记得吗」，三个按钮：忘了 / 有点模糊 / 记得（不显示下次复习时间，用户不需要关心）。
/// 自评后：还有要复习的 → 「先到这里」或「下一个：…」；都复习完 → 「回首页」。
struct ReviewBar: View {
    let grammarID: String
    /// 之后还要复习的语法（从「快要忘了」进来时才有；单独打开的到期语法为 nil）
    let queue: [String]?
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.bar")
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(localized: "复习：看完了，你还记得这个语法吗？")
            } icon: {
                Image(systemName: "arrow.counterclockwise").foregroundStyle(Theme.accentText)
            }
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
                            .background(Self.color(g).opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Self.color(g).opacity(0.35), lineWidth: 1.5))
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
        let remaining = queue ?? []
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 30, height: 30)
                .background(Theme.accentFill, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                (Text(localized: "已记录：") + Text(localized: Self.label(g)))
                    .font(.subheadline.weight(.semibold))
                if queue != nil {
                    if remaining.isEmpty {
                        Text(localized: "今天的复习都完成了").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text(localized: "还剩 \(remaining.count) 个要复习").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("review.done")
        }
        if queue != nil {
            if let next = remaining.first {
                HStack(spacing: 8) {
                    Button { goHome() } label: {
                        Text(localized: "先到这里")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accentText)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 48)
                            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1.5))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("review.stop")
                    Button {
                        let route = Route.review(next, Array(remaining.dropFirst()))
                        if let replaceRoute { replaceRoute(route) } else { pushRoute?(route) }
                    } label: {
                        HStack(spacing: 4) {
                            Text(localized: "下一个：") + Text(verbatim: library.point(id: next)?.titleForm ?? next)
                            Image(systemName: "chevron.right").font(.footnote.weight(.bold))
                        }
                        .font(.body.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(.white)
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
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.accentText, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("review.home")
            }
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

    static func color(_ g: FSRS.Grade) -> Color {
        switch g {
        case .again: Theme.dynamic(0xA3402B, 0xF0A08C)
        case .hard: Theme.dynamic(0x8A5A12, 0xE8C27A)
        case .good: Theme.accentText
        }
    }
}
