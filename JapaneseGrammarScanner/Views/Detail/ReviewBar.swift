import SwiftUI

struct ReviewBar: View {
    let grammarID: String
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
                if let next = queue.first {
                    (Text(localized: "还剩 \(queue.count) 个要复习") + Text(verbatim: " · ")
                        + Text(localized: "下一个：") + Text(verbatim: nextTitle(next)))
                        .font(.footnote).foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text(localized: "今天的复习都完成了").font(.footnote).foregroundStyle(.secondary)
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
                        Text(localized: "下一个")
                        Image(systemName: "chevron.right").font(.footnote.weight(.bold))
                    }
                    .font(.body.weight(.bold))
                    .lineLimit(1)
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.accentText, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(localized: "下一个：") + Text(verbatim: nextTitle(next)))
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

    private func nextTitle(_ id: String) -> String {
        library.point(id: id)?.titleForm ?? id
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

    static let colorHex: [FSRS.Grade: (light: UInt32, dark: UInt32)] = [
        .again: (0xB4553F, 0xE8947F),
        .hard: (0x8F6514, 0xE3BC62),
        .good: (0x4F7236, 0xA6C98A),
    ]

    static func color(_ g: FSRS.Grade) -> Color {
        let hex = colorHex[g]!
        return Theme.dynamic(hex.light, hex.dark)
    }

    static func haptic(_ g: FSRS.Grade) -> SensoryFeedback {
        switch g {
        case .again: .impact(flexibility: .soft, intensity: 0.6)
        case .hard: .impact(weight: .light)
        case .good: .success
        }
    }
}
