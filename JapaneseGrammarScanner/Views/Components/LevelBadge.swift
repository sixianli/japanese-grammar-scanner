import SwiftUI

/// JLPT 等级标签：灰色描边小标签，只靠文字区分等级（不再用五种颜色）。
struct LevelBadge: View {
    let level: JLPTLevel
    var small = false

    var body: some View {
        Text(level.rawValue)
            .font(small ? .system(size: 9, weight: .semibold) : .caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, small ? 4 : 5)
            .padding(.vertical, small ? 0.5 : 1)
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.45), lineWidth: 0.75))
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
                    .foregroundStyle(frequency == .high ? Theme.accent : Color.secondary)
                    .padding(.horizontal, compact ? 6 : 8)
                    .padding(.vertical, compact ? 1.5 : 3)
                    .background(frequency == .high ? Theme.accentFill : Color(.tertiarySystemFill), in: Capsule())
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
