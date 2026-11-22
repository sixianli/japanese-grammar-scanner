import SwiftUI

/// 小标签的统一尺寸（Build 17 反馈 4）：等级、「必考」同高、同字号、同圆角，字号不小于 12pt。
enum TagMetrics {
    static let font: Font = .caption.weight(.semibold)
    static let largeFont: Font = .footnote.weight(.semibold)
    static let cornerRadius: CGFloat = 6
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 2
}

/// JLPT 等级标签：等级颜色的浅底 + 深色字（N5 绿、N4 蓝、N3 黄、N2 橙、N1 红）。
/// `large` 用在详情页标题下方，文字带「JLPT」前缀。
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

/// 详情页标题栏里的等级：只有文字，不加底色（标题栏空间有限）。
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

/// 「必考」标签：只给出题频率最高一档（frequency == .high）的语法显示，实心主题色，最醒目。
/// 其它语法不显示任何频率标签（Build 17 反馈：只为告诉用户这个语法很重要）。
/// 详情页上可点（显示数据来源说明）；列表行里只是标签，不能点，否则会抢走整行的点击（点行没进讲解页，反而弹出说明）。
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

/// 详情页标题下方居中的一行：等级 +（必考时）「必考」。
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
