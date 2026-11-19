import SwiftUI

/// JLPT 等级标签：淡彩色小标签（N5 绿、N4 蓝、N3 黄、N2 橙、N1 红），一眼区分等级。
struct LevelBadge: View {
    let level: JLPTLevel
    var small = false

    var body: some View {
        Text(level.rawValue)
            .font(small ? .system(size: 9, weight: .bold) : .caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(level.badgeColor)
            .padding(.horizontal, small ? 4 : 5)
            .padding(.vertical, small ? 0.5 : 1)
            .background(level.badgeColor.opacity(0.14), in: Capsule())
            .fixedSize()
            .accessibilityLabel(Text(verbatim: "JLPT \(level.rawValue)"))
    }
}

/// 出题频率标签：常考（主色浅底）/ 考过（灰）；少考不显示。点击显示数据来源说明。
struct FrequencyBadge: View {
    let frequency: ExamFrequency
    var compact = false
    @State private var showInfo = false

    var body: some View {
        if let label {
            Button { showInfo = true } label: {
                Text(label)
                    .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                    .foregroundStyle(frequency == .high ? Theme.accentText : Color.secondary)
                    .padding(.horizontal, compact ? 6 : 8)
                    .padding(.vertical, compact ? 1.5 : 3)
                    .background(frequency == .high ? Theme.accentFill : Theme.fill, in: Capsule())
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .alert("出题频率", isPresented: $showInfo) {
                Button("好") {}
            } message: {
                Text("根据公开的考试复原资料与教材整理，仅供参考。")
            }
        }
    }

    private var label: LocalizedStringKey? {
        switch frequency {
        case .high: "常考"
        case .medium: "考过"
        case .low: nil
        }
    }
}
