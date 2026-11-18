import SwiftUI

/// 语法点列表行：标题、等级、意思摘要、收藏按钮。
struct GrammarRow: View {
    let point: GrammarPoint
    var occurrences: Int? = nil
    @EnvironmentObject private var favorites: FavoritesStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(point.level.color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Text(point.displayTitle).font(.headline)
                    LevelBadge(level: point.level)
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
                    .foregroundStyle(favorites.isFavorite(point.id) ? Color.yellow : Color.secondary)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(favorites.isFavorite(point.id) ? Text("取消收藏") : Text("收藏"))
        }
        .padding(.vertical, 4)
    }
}
