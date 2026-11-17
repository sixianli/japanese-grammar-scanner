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
