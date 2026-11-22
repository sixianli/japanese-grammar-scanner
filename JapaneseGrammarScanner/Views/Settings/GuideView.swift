import SwiftUI

/// 设置 → 使用指南：只有一页，按核心流程从上往下，每一步一张插图 + 标题 + 一句话（Build 17 反馈 3）。
/// 插图和首次打开的引导共用，纯 SwiftUI 绘制，随界面语言、深浅色变化。
struct GuideView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(Array(AppFeature.core.enumerated()), id: \.element) { i, f in
                    if let card = f.card {
                        GuideCardView(number: i + 1, card: card) { GuideIllustration(feature: f) }
                            .accessibilityIdentifier("guide.card")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle(tr("使用指南"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GuideCardView<Illustration: View>: View {
    let number: Int
    let card: AppFeature.GuideCard
    @ViewBuilder let illustration: Illustration

    var body: some View {
        VStack(spacing: 14) {
            illustration
                .scaleEffect(0.8)
                .frame(height: 230)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: "\(number)")
                    .font(.footnote.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 24, height: 24)
                    .background(Theme.accentFill, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized: LocalizedStringKey(card.title)).font(.headline)
                    Text(localized: LocalizedStringKey(card.line)).font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// 每个核心功能对应的插图
private struct GuideIllustration: View {
    let feature: AppFeature

    var body: some View {
        switch feature {
        case .scan: ScanIllustration()
        case .scanResult: ReadyIllustration()
        case .detail: DetailIllustration()
        case .contrast: ContrastIllustration()
        case .review: ReviewIllustration()
        case .library, .search, .history, .appearance, .feedback: EmptyView()
        }
    }
}

/// 相近语法：两句只换了语法的例句，一句说出差别
private struct ContrastIllustration: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(verbatim: "〜ておく").font(.headline)
                LevelBadge(level: .n4)
            }
            Text(localized: "看例句对比").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentText)
            VStack(alignment: .leading, spacing: 8) {
                example(head: "傘を買って", grammar: "おいた", tail: "。", color: Theme.accentText)
                example(head: "傘を買って", grammar: "しまった", tail: "。", color: Theme.contrastText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(18)
        .frame(width: 290, alignment: .leading)
        .background(Color(.secondarySystemBackground).opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
    }

    private func example(head: String, grammar: String, tail: String, color: Color) -> some View {
        (Text(verbatim: head) + Text(verbatim: grammar).foregroundColor(color).bold() + Text(verbatim: tail))
            .font(.system(size: 17, weight: .medium, design: .serif))
    }
}
