import SwiftUI

enum TagMetrics {
    static let font: Font = .caption.weight(.semibold)
    static let largeFont: Font = .footnote.weight(.semibold)
    static let cornerRadius: CGFloat = 6
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 2
}

struct LevelBadge: View {
    let level: JLPTLevel
    var large = false

    var body: some View {
        Text(verbatim: large ? "JLPT \(level.rawValue)" : level.rawValue)
            .font(large ? TagMetrics.largeFont : TagMetrics.font)
            .monospacedDigit()
            .foregroundStyle(level.badgeColor)
            .padding(.horizontal, large ? TagMetrics.horizontalPadding + 4 : TagMetrics.horizontalPadding)
            .padding(.vertical, large ? TagMetrics.verticalPadding + 2 : TagMetrics.verticalPadding)
            .background(level.badgeColor.opacity(0.16), in: RoundedRectangle(cornerRadius: TagMetrics.cornerRadius, style: .continuous))
            .fixedSize()
            .accessibilityLabel(Text(verbatim: "JLPT \(level.rawValue)"))
    }
}

struct LevelText: View {
    let level: JLPTLevel
    var small = false

    var body: some View {
        Text(verbatim: "JLPT \(level.rawValue)")
            .font(small ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(level.badgeColor)
            .fixedSize()
    }
}

struct MustKnowBadge: View {
    var large = false
    var showsInfo = false
    @State private var showInfo = false

    var body: some View {
        if showsInfo {
            Button { showInfo = true } label: { label }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tag.mustKnow")
                .alert(tr("出题频率"), isPresented: $showInfo) {
                    Button(tr("好")) {}
                } message: {
                    Text(localized: "根据公开的考试复原资料与教材整理，仅供参考。")
                }
        } else {
            label
                .accessibilityIdentifier("tag.mustKnow")
        }
    }

    private var label: some View {
        Text(localized: "必考")
            .font(large ? TagMetrics.largeFont : TagMetrics.font)
            .foregroundStyle(Color.white)
            .padding(.horizontal, large ? TagMetrics.horizontalPadding + 4 : TagMetrics.horizontalPadding)
            .padding(.vertical, large ? TagMetrics.verticalPadding + 2 : TagMetrics.verticalPadding)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: TagMetrics.cornerRadius, style: .continuous))
            .fixedSize()
    }
}

struct DetailTags: View {
    let level: JLPTLevel
    let mustKnow: Bool

    var body: some View {
        HStack(spacing: 8) {
            LevelBadge(level: level, large: true)
                .accessibilityIdentifier("detail.level")
            if mustKnow { MustKnowBadge(large: true, showsInfo: true) }
        }
    }
}
