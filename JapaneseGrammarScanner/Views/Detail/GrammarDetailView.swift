import SwiftUI

/// 语法点详细讲解。每个模块有独立的彩色图标徽章，内容按义项、场景分段，日语自动注音。
struct GrammarDetailView: View {
    let grammarID: String
    @EnvironmentObject private var library: GrammarLibrary
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var entitlements: EntitlementStore
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        if let point = library.point(id: grammarID) {
            content(point)
                .onAppear { history.recordViewed(point.id) }
        } else {
            ContentUnavailableView("找不到该语法点", systemImage: "questionmark.folder")
        }
    }

    private func content(_ p: GrammarPoint) -> some View {
        let regexes = p.patterns.compactMap { try? NSRegularExpression(pattern: $0) }
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(p)

                    // 意思：概述 + 各义项（点击跳到对应用法）
                    SectionCard(icon: "lightbulb.max.fill", title: "意思", tint: .orange) {
                        VStack(alignment: .leading, spacing: 12) {
                            RubyText(explanation: p.meaning, style: .init(font: .body))
                            // 每个义项：编号 + 标题（点击跳到对应用法）+ 该义项的接续（多种接续分行列出）
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(p.senses.enumerated()), id: \.offset) { i, sense in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Button {
                                            guard entitlements.hasFullAccess else { return }
                                            withAnimation(.easeInOut) { proxy.scrollTo("sense-\(i)", anchor: .top) }
                                        } label: {
                                            HStack(spacing: 10) {
                                                NumberBadge(number: i + 1, tint: .orange)
                                                Text(sense.label).font(.body.weight(.semibold)).foregroundStyle(Color.primary)
                                                Spacer(minLength: 0)
                                                if entitlements.hasFullAccess {
                                                    Image(systemName: "arrow.down.circle")
                                                        .font(.subheadline)
                                                        .foregroundStyle(Color.orange)
                                                }
                                            }
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)

                                        VStack(alignment: .leading, spacing: 4) {
                                            ForEach(Array(Self.connectionLines(sense.connection).enumerated()), id: \.offset) { _, line in
                                                HStack(alignment: .top, spacing: 6) {
                                                    Image(systemName: "link")
                                                        .font(.caption.weight(.bold))
                                                        .foregroundStyle(Color.blue)
                                                        .padding(.top, 4)
                                                    RubyText(explanation: line, style: .init(font: .callout, weight: .medium))
                                                }
                                            }
                                        }
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                        }
                    }

                    if !entitlements.hasFullAccess {
                        LockedContentCard()
                    } else {
                        // 用法：每个义项一张卡片（意思讲解 / 接续 / 例句）
                        SectionCard(icon: "list.bullet.rectangle.portrait.fill", title: "用法", tint: .blue) {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(Array(p.senses.enumerated()), id: \.offset) { i, sense in
                                    SenseCard(index: i + 1, sense: sense, regexes: regexes, tint: p.level.color)
                                        .id("sense-\(i)")
                                }
                            }
                        }

                        // 注意：易忽略、易混淆、易出错、失礼与禁忌
                        if !p.notes.isEmpty {
                            SectionCard(icon: "exclamationmark.triangle.fill", title: "注意", tint: .red) {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(Array(p.notes.enumerated()), id: \.offset) { _, note in
                                        HStack(alignment: .top, spacing: 10) {
                                            Image(systemName: "exclamationmark.circle.fill")
                                                .font(.subheadline)
                                                .foregroundStyle(Color.red.opacity(0.85))
                                                .padding(.top, 3)
                                            RubyText(explanation: note, style: .init(font: .callout))
                                        }
                                    }
                                }
                            }
                        }

                        // 使用场景：日常生活 / 职场
                        SectionCard(icon: "person.2.wave.2.fill", title: "使用场景", tint: .green) {
                            VStack(alignment: .leading, spacing: 18) {
                                SceneGroup(icon: "house.fill", label: "日常生活", tint: .teal, scenes: p.scenes.daily, regexes: regexes)
                                SceneGroup(icon: "briefcase.fill", label: "职场", tint: .indigo, scenes: p.scenes.work, regexes: regexes)
                            }
                        }

                        // 词源
                        SectionCard(icon: "scroll.fill", title: "词源", tint: .brown) {
                            RubyText(explanation: p.etymology, style: .init(font: .body, lineSpacing: 8))
                        }

                        // 组词逻辑
                        if !p.formation.isEmpty {
                            SectionCard(icon: "puzzlepiece.extension.fill", title: "组词逻辑", tint: .cyan) {
                                RubyText(explanation: p.formation, style: .init(font: .body, lineSpacing: 8))
                            }
                        }

                        // 相近语法
                        SectionCard(icon: "arrow.triangle.branch", title: "相似・相近语法", tint: .purple) {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(Array(p.similar.enumerated()), id: \.offset) { index, s in
                                    similarItem(s)
                                    if index < p.similar.count - 1 { Divider() }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(p.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    favorites.toggle(p.id)
                } label: {
                    Image(systemName: favorites.isFavorite(p.id) ? "star.fill" : "star")
                        .foregroundStyle(favorites.isFavorite(p.id) ? Color.yellow : Color.accentColor)
                }
                .accessibilityLabel(favorites.isFavorite(p.id) ? Text("取消收藏") : Text("收藏"))
            }
        }
    }

    /// 一个义项可能有多种接续方式（用「；」分隔），拆成多行显示。
    static func connectionLines(_ s: String) -> [String] {
        let parts = s.split(whereSeparator: { $0 == "；" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [s] : parts
    }

    /// 标题：有汉字时在汉字上方注假名（不再单独显示读音行）；等级标签统一放在标题右上角。
    private func header(_ p: GrammarPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                RubyText(japanese: p.titleForm, style: .init(font: .largeTitle.bold(), rubySize: 12, lineSpacing: 2))
                LevelBadge(level: p.level)
                    .padding(.top, FuriganaStore.shared.hasRuby(p.titleForm) ? 18 : 2)
                Spacer(minLength: 0)
            }
            if !p.titleNote.isEmpty {
                Text(verbatim: p.titleNote).font(.subheadline).foregroundStyle(.secondary)
            }
            if let f = p.frequency {
                FrequencyBadge(frequency: f).padding(.top, 2)
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func similarItem(_ s: GrammarPoint.Similar) -> some View {
        let target = s.id.flatMap { library.point(id: $0) } ?? library.point(matchingTitle: s.title)
        VStack(alignment: .leading, spacing: 8) {
            if let target {
                NavigationLink(value: Route.grammar(target.id)) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(target.titleForm).font(.headline)
                        LevelBadge(level: target.level)
                        Spacer()
                        Text("查看讲解").font(.caption)
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .foregroundStyle(Color.purple)
                }
            } else {
                Text(s.title).font(.headline)
            }
            RubyText(explanation: s.explanation, style: .init(font: .callout))
        }
    }
}

// MARK: - 组件

/// 模块卡片：左上角彩色图标徽章 + 标题。
private struct SectionCard<Content: View>: View {
    let icon: String
    let title: LocalizedStringKey
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .shadow(color: tint.opacity(0.35), radius: 4, y: 2)
                    .accessibilityHidden(true)
                Text(title).font(.title3.bold())
            }
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SubHeader: View {
    let icon: String
    let label: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption.weight(.bold)).foregroundStyle(tint)
            Text(label).font(.subheadline.weight(.bold)).foregroundStyle(tint)
        }
    }
}

private struct Pill<Content: View>: View {
    let icon: String
    let label: LocalizedStringKey
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SubHeader(icon: icon, label: label, tint: tint)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct NumberBadge: View {
    let number: Int
    let tint: Color

    var body: some View {
        Text(verbatim: "\(number)")
            .font(.caption.weight(.heavy))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(tint, in: Circle())
    }
}

/// 一个义项：编号 + 标题，下面依次是 意思讲解 / 接续 / 例句。
private struct SenseCard: View {
    let index: Int
    let sense: GrammarPoint.Sense
    let regexes: [NSRegularExpression]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                NumberBadge(number: index, tint: .blue)
                Text(sense.label).font(.headline)
            }

            VStack(alignment: .leading, spacing: 6) {
                SubHeader(icon: "text.bubble.fill", label: "意思", tint: .orange)
                RubyText(explanation: sense.meaning, style: .init(font: .body))
            }

            VStack(alignment: .leading, spacing: 6) {
                SubHeader(icon: "link", label: "接续", tint: .blue)
                RubyText(explanation: sense.connection, style: .init(font: .callout, weight: .medium))
            }

            VStack(alignment: .leading, spacing: 10) {
                SubHeader(icon: "quote.opening", label: "例句", tint: .green)
                ForEach(Array(sense.examples.enumerated()), id: \.offset) { _, ex in
                    ExampleView(example: ex, regexes: regexes, tint: tint)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.blue.opacity(0.15)))
    }
}

/// 日语例句（注音 + 语法部分高亮）+ 译文。
private struct ExampleView: View {
    let example: GrammarPoint.Example
    let regexes: [NSRegularExpression]
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(tint.opacity(0.6)).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                RubyText(
                    japanese: example.ja,
                    highlights: highlightRanges,
                    style: .init(font: .title3, rubySize: 9, highlightColor: tint, lineSpacing: 2)
                )
                Text(example.translation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var highlightRanges: [NSRange] {
        let range = NSRange(location: 0, length: (example.ja as NSString).length)
        return regexes.flatMap { $0.matches(in: example.ja, range: range).map(\.range) }.filter { $0.length > 0 }
    }
}

/// 一组场景（日常生活 / 职场），每个场景单独成段。
private struct SceneGroup: View {
    let icon: String
    let label: LocalizedStringKey
    let tint: Color
    let scenes: [GrammarPoint.Scene]
    let regexes: [NSRegularExpression]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(tint, in: RoundedRectangle(cornerRadius: 7))
                Text(label).font(.headline).foregroundStyle(tint)
            }
            ForEach(Array(scenes.enumerated()), id: \.offset) { _, scene in
                VStack(alignment: .leading, spacing: 8) {
                    Text(scene.title).font(.body.weight(.semibold))
                    RubyText(explanation: scene.description, style: .init(font: .callout, color: .secondary))
                    ExampleView(example: scene.example, regexes: regexes, tint: tint)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
