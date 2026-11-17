import SwiftUI

/// 语法点详细讲解：意思、接续与用法、使用场景、词源、例句、相似语法扩展。
struct GrammarDetailView: View {
    let grammarID: String
    @EnvironmentObject private var library: GrammarLibrary
    @EnvironmentObject private var favorites: FavoritesStore

    var body: some View {
        if let point = library.point(id: grammarID) {
            content(point)
        } else {
            ContentUnavailableView("找不到该语法点", systemImage: "questionmark.folder")
        }
    }

    private func content(_ p: GrammarPoint) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(p)

                DetailSection(title: "意思", icon: "lightbulb") {
                    Text(p.meaning)
                }

                DetailSection(title: "用法", icon: "list.bullet.rectangle") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledBlock(label: "接续") { Text(p.connection).font(.body.weight(.medium)) }
                        BulletList(items: p.usage)
                    }
                }

                DetailSection(title: "使用场景", icon: "person.2.wave.2") {
                    BulletList(items: p.scenarios)
                }

                DetailSection(title: "词源", icon: "scroll") {
                    Text(p.etymology)
                }

                DetailSection(title: "例句", icon: "text.quote") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(p.examples.enumerated()), id: \.offset) { _, ex in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(highlightedExample(ex.ja, point: p)).font(.title3)
                                Text(ex.zh).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                DetailSection(title: "相似・相近语法", icon: "arrow.triangle.branch") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(p.similar.enumerated()), id: \.offset) { index, s in
                            similarItem(s)
                            if index < p.similar.count - 1 { Divider() }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(p.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    favorites.toggle(p.id)
                } label: {
                    Image(systemName: favorites.isFavorite(p.id) ? "star.fill" : "star")
                        .foregroundStyle(favorites.isFavorite(p.id) ? Color.yellow : Color.accentColor)
                }
                .accessibilityLabel(favorites.isFavorite(p.id) ? "取消收藏" : "收藏")
            }
        }
    }

    private func header(_ p: GrammarPoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(p.title).font(.largeTitle.bold())
                LevelBadge(level: p.level)
            }
            if let reading = p.reading, !reading.isEmpty, reading != p.title {
                Text(reading).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func similarItem(_ s: GrammarPoint.Similar) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let id = s.id, let target = library.point(id: id) {
                NavigationLink(value: Route.grammar(id)) {
                    HStack(spacing: 6) {
                        Text(s.title).font(.headline)
                        LevelBadge(level: target.level)
                        Spacer()
                        Text("查看讲解").font(.caption)
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .foregroundStyle(Color.accentColor)
                }
            } else {
                Text(s.title).font(.headline)
            }
            Text(s.explanation).font(.callout)
        }
    }

    /// 例句中本语法点的部分加粗高亮。
    private func highlightedExample(_ sentence: String, point: GrammarPoint) -> AttributedString {
        var attributed = AttributedString(sentence)
        let ns = sentence as NSString
        for pattern in point.patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for m in regex.matches(in: sentence, range: NSRange(location: 0, length: ns.length)) where m.range.length > 0 {
                if let r = Range(m.range, in: sentence),
                   let ar = Range(r, in: attributed) {
                    attributed[ar].backgroundColor = point.level.color.opacity(0.25)
                    attributed[ar].font = Font.title3.bold()
                }
            }
        }
        return attributed
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.title3.bold())
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct LabeledBlock<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(.secondary)
                    Text(item)
                }
            }
        }
    }
}
