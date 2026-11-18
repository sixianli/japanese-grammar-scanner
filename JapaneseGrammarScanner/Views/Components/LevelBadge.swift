import SwiftUI

struct LevelBadge: View {
    let level: JLPTLevel

    var body: some View {
        Text(level.rawValue)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(level.color, in: Capsule())
    }
}

struct LevelLegend: View {
    let levels: [JLPTLevel]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(levels) { level in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(level.color.opacity(0.6)).frame(width: 12, height: 8)
                    Text(level.rawValue).font(.caption2)
                }
            }
        }
        .foregroundStyle(.secondary)
    }
}

/// 出题频率标签：常考 / 考过（少考不显示）；点击显示数据来源说明
struct FrequencyBadge: View {
    let frequency: ExamFrequency
    var compact = false
    @State private var showInfo = false

    var body: some View {
        if let label {
            Button { showInfo = true } label: {
                Text(label)
                    .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, compact ? 6 : 8)
                    .padding(.vertical, compact ? 2 : 3)
                    .background(color.opacity(0.12), in: Capsule())
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

    private var color: Color {
        frequency == .high ? .red : .secondary
    }
}
