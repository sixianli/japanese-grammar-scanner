import SwiftUI

/// 语法点列表行：标题、等级标签、「必考」（只有必考的语法显示）、意思摘要、收藏按钮。
struct GrammarRow: View {
    let point: GrammarPoint
    var occurrences: Int? = nil
    /// 在某个等级的列表里显示时，标签显示该等级（合并后的语法点可能横跨多个等级）。
    var shownLevel: JLPTLevel? = nil
    @EnvironmentObject private var favorites: FavoritesStore

    private var badgeLevel: JLPTLevel {
        if let shownLevel, point.levels.contains(shownLevel) { return shownLevel }
        return point.level
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 6) {
                    Text(point.displayTitle).font(.headline)
                    LevelBadge(level: badgeLevel)
                    if point.frequency == .high {
                        MustKnowBadge()
                    }
                    if let occurrences, occurrences > 1 {
                        Text(verbatim: "×\(occurrences)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(point.meaning)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            FavoriteSakuraButton(id: point.id, size: 19, outlineColor: .secondary)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("row.star")
        }
        .padding(.vertical, 4)
    }
}
