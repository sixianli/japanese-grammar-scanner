import SwiftUI

/// 语法点列表行：标题（等级标签贴在标题右上角）、出题频率、意思摘要、收藏按钮。
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
                    HStack(alignment: .top, spacing: 3) {
                        Text(point.displayTitle).font(.headline)
                        LevelBadge(level: badgeLevel, small: true)
                    }
                    if let f = point.frequency {
                        FrequencyBadge(frequency: f, compact: true)
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
            Button {
                favorites.toggle(point.id)
            } label: {
                Image(systemName: favorites.isFavorite(point.id) ? "star.fill" : "star")
                    .foregroundStyle(favorites.isFavorite(point.id) ? Theme.accent : Color.secondary)
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(favorites.isFavorite(point.id) ? Text(localized: "取消收藏") : Text(localized: "收藏"))
            .accessibilityIdentifier("row.star")
        }
        .padding(.vertical, 4)
    }
}
