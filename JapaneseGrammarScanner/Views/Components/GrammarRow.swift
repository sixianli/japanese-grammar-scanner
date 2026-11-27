import SwiftUI

struct GrammarRow: View {
    let point: GrammarPoint
    var occurrences: Int? = nil
    var shownLevel: JLPTLevel? = nil
    @EnvironmentObject private var favorites: FavoritesStore

    static func badgeLevel(for point: GrammarPoint, shownLevel: JLPTLevel?) -> JLPTLevel {
        if let shownLevel, point.levels.contains(shownLevel) { return shownLevel }
        return point.level
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 6) {
                    Text(point.displayTitle).font(.headline)
                    LevelBadge(level: GrammarRow.badgeLevel(for: point, shownLevel: shownLevel))
                        .accessibilityIdentifier("row.level")
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
