import SwiftUI

/// 语法点详细讲解：一整页连续阅读的讲义（不分卡片），铺满屏幕宽度，只保留标准阅读边距。
/// 颜色只用在重点上：例句里的目标语法（主色）；其余为黑白灰。
struct GrammarDetailView: View {
    let grammarID: String
    /// 从扫描结果打开时，原文里命中的文字（用于显示「你扫到的」并找出对应的用法）
    var matchedText: String? = nil
    @EnvironmentObject private var library: GrammarLibrary
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var entitlements: EntitlementStore
    @EnvironmentObject private var history: HistoryStore
    /// 滚动相关的状态放在单独的对象里：只有标题浮层读取它，滚动时不会让整页内容重新排版（否则会卡顿、闪烁）。
    @State private var scroll = DetailScrollModel()

    /// iOS 26+ 导航栏透明（Liquid Glass），标题可以直接“飞”进导航栏；更早的系统用淡入方式。
    private var usesFlyingTitle: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    var body: some View {
        if let point = library.point(id: grammarID) {
            content(point)
                .onAppear {
                    history.recordViewed(point.id)
                    UsageStats.shared.grammarViewed(point.id, level: point.level)
                }
        } else {
            ContentUnavailableView(tr("找不到该语法点"), systemImage: "questionmark.folder")
        }
    }

    private func content(_ p: GrammarPoint) -> some View {
        let regexes = p.patterns.compactMap { try? NSRegularExpression(pattern: $0) }
        let showsSenseLevels = p.levels.count > 1
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if usesFlyingTitle {
                        // 标题由浮层绘制（跟手移动到导航栏）；这里只占位并测量大小
                        header(p, titleHidden: true)
                    } else {
                        FadingHeader(scroll: scroll) { header(p) }
                            .background(GeometryReader { g in
                                Color.clear.preference(key: HeaderFrameKey.self, value: g.frame(in: .named("detailScroll")))
                            })
                    }

                    // 从扫描结果进来：先告诉用户扫到的原文对应这里的哪个用法
                    let focus = matchedText.flatMap { Self.bestSense(for: $0, in: p) }
                    if let matchedText {
                        ScannedMatchBanner(matched: matchedText, senseIndex: focus,
                                           senseLabel: focus.map { p.senses[$0].label }) {
                            if let focus { withAnimation(.easeInOut) { proxy.scrollTo("sense-\(focus)", anchor: .top) } }
                        }
                        .padding(.top, 14)
                    }

                    // 概述
                    RubyText(explanation: p.meaning, style: .init(font: .body, lineSpacing: 7))
                        .padding(.top, 14)

                    // 义项目录：整行可点，跳到下方对应用法
                    SenseOutline(point: p, showsLevels: showsSenseLevels, tappable: entitlements.hasFullAccess,
                                 highlighted: focus) { i in
                        withAnimation(.easeInOut) { proxy.scrollTo("sense-\(i)", anchor: .top) }
                    }
                    .padding(.top, 18)

                    if !entitlements.hasFullAccess {
                        LockedContentCard().padding(.top, 28)
                    } else {
                        // 每个义项作为单独的一项，长页面只排版看得见的部分
                        DocSectionTitle("用法", icon: "text.book.closed")
                            .padding(.top, 40)
                            .padding(.bottom, 14)
                        ForEach(Array(p.senses.enumerated()), id: \.offset) { i, sense in
                            SenseBlock(index: i + 1, sense: sense,
                                       level: showsSenseLevels ? p.level(of: sense) : nil,
                                       regexes: regexes)
                                .padding(.bottom, i < p.senses.count - 1 ? 34 : 0)
                                .id("sense-\(i)")
                        }

                        if !p.notes.isEmpty {
                            DocSection("注意", icon: "exclamationmark.triangle", anchor: "section-notes") {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(Array(p.notes.enumerated()), id: \.offset) { _, note in
                                        NoteView(note: note)
                                    }
                                }
                            }
                        }

                        DocSection("使用场景", icon: "person.2", anchor: "section-scenes") {
                            VStack(alignment: .leading, spacing: 30) {
                                SceneGroup(label: "日常生活", icon: "house", scenes: p.scenes.daily, regexes: regexes)
                                SceneGroup(label: "职场", icon: "briefcase", scenes: p.scenes.work, regexes: regexes)
                            }
                        }

                        // 词源与组词逻辑内容高度重合，合并为一节；组词逻辑更完整，优先使用
                        let origin = p.formation.isEmpty ? p.etymology : p.formation
                        if !origin.isEmpty {
                            DocSection("来源与构成", icon: "puzzlepiece.extension") {
                                RubyText(explanation: origin, style: .init(font: .body, lineSpacing: 7))
                            }
                        }

                        if let contrasts = library.contrasts(for: p.id), !contrasts.groups.isEmpty {
                            // 新版：分三组 + 对比例句（样板阶段只有部分语法点有）
                            DocSection("相近语法", icon: "arrow.triangle.branch", anchor: "section-similar") {
                                ContrastSection(contrasts: contrasts, currentTitle: p.titleForm)
                            }
                        } else if !p.similar.isEmpty {
                            DocSection("相近语法", icon: "arrow.triangle.branch", anchor: "section-similar") {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(p.similar.enumerated()), id: \.offset) { index, s in
                                        similarItem(s)
                                        if index < p.similar.count - 1 { Divider().padding(.vertical, 2) }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 8)
                .padding(.bottom, 16)

                // 讲解有误时的反馈入口
                Button {
                    NotificationCenter.default.post(name: .showFeedback, object: "grammar: \(p.id) \(p.titleForm)")
                } label: {
                    HStack(spacing: 4) {
                        Text(localized: "讲解有误或看不懂？")
                        Text(localized: "告诉我们").foregroundStyle(Theme.accentText)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 40)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("detail.feedback")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .coordinateSpace(name: "detailScroll")
            .onAppear {
                // CI 截图：滚动到指定位置
                if let anchor = DemoMode.scrollAnchor {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { proxy.scrollTo(anchor, anchor: .top) }
                }
            }
            .onPreferenceChange(HeaderFrameKey.self) { [scroll] frame in
                // 旧系统：以初始位置为基准，标题向上移出自身高度的过程中，进度从 0 平滑变到 1
                if scroll.headerBaseline == nil { scroll.headerBaseline = frame.minY }
                let moved = (scroll.headerBaseline ?? frame.minY) - frame.minY
                let progress = min(1, max(0, moved / max(frame.height, 1)))
                if abs(progress - scroll.progress) > 0.005 { scroll.progress = progress }
            }
            .onPreferenceChange(TitleSizeKey.self) { [scroll] size in
                if size != .zero, size != scroll.titleSize { scroll.titleSize = size }
            }
            .trackScrollOffset(scroll)
        }
        .background(Theme.background)
        .overlay(alignment: .topLeading) {
            if usesFlyingTitle {
                FlyingTitle(scroll: scroll, topPadding: 8) {
                    titleRow(p)
                } compact: {
                    // 导航栏里的标题：单行、标准导航栏字号，长标题自动略缩小；等级标签用正常大小
                    HStack(alignment: .top, spacing: 4) {
                        Text(verbatim: p.titleForm)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        LevelBadge(level: p.level)
                    }
                }
            }
        }
        .navigationTitle(p.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if usesFlyingTitle {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                } else {
                    LegacyNavTitle(scroll: scroll) {
                        HStack(alignment: .top, spacing: 4) {
                            Text(verbatim: p.titleForm).font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                            LevelBadge(level: p.level)
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    favorites.toggle(p.id)
                } label: {
                    Image(systemName: favorites.isFavorite(p.id) ? "star.fill" : "star")
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel(favorites.isFavorite(p.id) ? Text(localized: "取消收藏") : Text(localized: "收藏"))
                .accessibilityIdentifier("detail.favorite")
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

    /// 标题行：汉字上方注假名；等级标签紧贴标题文字的右上角（上标位置）。
    private func titleRow(_ p: GrammarPoint) -> some View {
        let rubyOffset = FuriganaStore.shared.hasRuby(p.titleForm)
            ? ceil(UIFontMetrics(forTextStyle: .body).scaledValue(for: 12) * 1.3) : 0
        return HStack(alignment: .top, spacing: 4) {
            RubyText(japanese: p.titleForm, style: .init(font: .largeTitle.bold(), rubySize: 12, lineSpacing: 2))
            LevelBadge(level: p.level)
                .padding(.top, rubyOffset + 4)
        }
    }

    private func header(_ p: GrammarPoint, titleHidden: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow(p)
                .opacity(titleHidden ? 0 : 1)
                .accessibilityHidden(titleHidden)
                .background(GeometryReader { g in
                    Color.clear.preference(key: TitleSizeKey.self, value: g.size)
                })
            if let f = p.frequency, f != .low {
                FrequencyBadge(frequency: f)
            }
        }
    }

    @ViewBuilder
    private func similarItem(_ s: GrammarPoint.Similar) -> some View {
        let target = s.id.flatMap { library.point(id: $0) } ?? library.point(matchingTitle: s.title)
        let row = VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 3) {
                Text(target?.titleForm ?? s.title).font(.headline).foregroundStyle(Color.primary)
                if let target { LevelBadge(level: target.level, small: true) }
                Spacer(minLength: 8)
                if target != nil {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 3)
                }
            }
            RubyText(explanation: s.explanation, style: .init(font: .callout, color: .secondary, lineSpacing: 5))
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        if let target {
            NavigationLink(value: Route.grammar(target.id)) { row }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier("detail.similar")
        } else {
            row
        }
    }
}

// MARK: - 组件

/// 讲义中的一节：线条图标 + 标题 + 内容，节与节之间只用留白分隔，不分卡片。
private struct DocSection<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    var anchor: String? = nil
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, icon: String, anchor: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.anchor = anchor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DocSectionTitle(title, icon: icon)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 40)
        .id(anchor ?? "section-\(icon)")
    }
}

/// 义项序号：灰色描边圆圈。
private struct NumberBadge: View {
    let number: Int

    var body: some View {
        Text(verbatim: "\(number)")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .overlay(Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1))
    }
}

/// 列表行按下时整行轻微变暗（iOS 系统列表的反馈方式）。
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.systemFill).opacity(configuration.isPressed ? 1 : 0))
                    .padding(.horizontal, -10)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 义项目录：编号 + 义项名 + 接续；整行可点，右侧淡灰「›」提示可跳转。
private struct SenseOutline: View {
    let point: GrammarPoint
    let showsLevels: Bool
    let tappable: Bool
    var highlighted: Int? = nil
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            ForEach(Array(point.senses.enumerated()), id: \.offset) { i, sense in
                Button {
                    if tappable { onSelect(i) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        NumberBadge(number: i + 1)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top, spacing: 3) {
                                Text(sense.label).font(.body.weight(.semibold)).foregroundStyle(Color.primary)
                                if showsLevels { LevelBadge(level: point.level(of: sense), small: true) }
                            }
                            ForEach(Array(GrammarDetailView.connectionLines(sense.connection).enumerated()), id: \.offset) { _, line in
                                RubyText(explanation: line, style: .init(font: .subheadline, color: .secondary, lineSpacing: 4))
                            }
                        }
                        Spacer(minLength: 8)
                        if tappable {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, i == highlighted ? 10 : 0)
                    .background(i == highlighted ? Theme.accentFill : .clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier(i == highlighted ? "detail.senseRow.matched" : "detail.senseRow")
                .disabled(!tappable)
                .accessibilityHint(tappable ? Text(localized: "跳到用法") : Text(verbatim: ""))
                Divider().padding(.leading, 34)
            }
        }
    }
}

/// 一个义项的完整讲解：编号 + 标题，下面依次是意思讲解、接续、例句。
private struct SenseBlock: View {
    let index: Int
    let sense: GrammarPoint.Sense
    let level: JLPTLevel?
    let regexes: [NSRegularExpression]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                NumberBadge(number: index)
                HStack(alignment: .top, spacing: 3) {
                    Text(sense.label).font(.title3.weight(.semibold))
                    if let level { LevelBadge(level: level, small: true) }
                }
            }

            RubyText(explanation: sense.meaning, style: .init(font: .body, lineSpacing: 7))

            VStack(alignment: .leading, spacing: 6) {
                Text(localized: "接续").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(GrammarDetailView.connectionLines(sense.connection).enumerated()), id: \.offset) { _, line in
                        RubyText(explanation: line, style: .init(font: .callout, lineSpacing: 4, weight: .medium))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(sense.examples.enumerated()), id: \.offset) { _, ex in
                    ExampleView(example: ex, regexes: regexes)
                }
            }
            .padding(.top, 2)
        }
    }
}

/// 日语例句（注音 + 语法部分用主色标出）+ 译文。
private struct ExampleView: View {
    let example: GrammarPoint.Example
    let regexes: [NSRegularExpression]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule().fill(Color(.separator)).frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                RubyText(
                    japanese: example.ja,
                    highlights: highlightRanges,
                    style: .init(font: .title3, rubySize: 10, highlightColor: Theme.accentText, lineSpacing: 6)
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

/// 一组场景（日常生活 / 职场）：分类名用正文色 + 线条图标，醒目但不抢例句。
private struct SceneGroup: View {
    let label: LocalizedStringKey
    let icon: String
    let scenes: [GrammarPoint.Scene]
    let regexes: [NSRegularExpression]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 30, height: 30)
                    .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(localized: label).font(.title3.weight(.semibold)).foregroundStyle(Color.primary)
            }
            ForEach(Array(scenes.enumerated()), id: \.offset) { _, scene in
                VStack(alignment: .leading, spacing: 6) {
                    Text(scene.title).font(.body.weight(.semibold))
                    RubyText(explanation: scene.description, style: .init(font: .callout, color: .secondary, lineSpacing: 5))
                    ExampleView(example: scene.example, regexes: regexes)
                        .padding(.top, 4)
                }
            }
        }
    }
}

/// 「注意」中的一条：讲解文字 + 单独成行的 ✕ 错误句 / ○ 正确句（红叉、绿勾），按原文顺序排列。
private struct NoteView: View {
    let note: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "•").font(.body.weight(.bold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(NoteParser.parse(note).enumerated()), id: \.offset) { i, item in
                    switch item {
                    case .text(let t):
                        RubyText(explanation: t, style: .init(font: i == 0 ? .body : .callout,
                                                              color: i == 0 ? .primary : .secondary, lineSpacing: 6))
                    case .example(let correct, let sentence):
                        // 图标与句子的正文行对齐（有注音时，正文在注音行下方）
                        let rubyLine = FuriganaStore.shared.hasRuby(sentence)
                            ? ceil(UIFontMetrics(forTextStyle: .body).scaledValue(for: 9) * 1.3) : 0
                        let lineHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(correct ? Color.green : Color.red)
                                .frame(height: lineHeight)
                                .padding(.top, rubyLine)
                                .accessibilityLabel(correct ? Text(localized: "正确") : Text(localized: "错误"))
                            RubyText(japanese: sentence, style: .init(font: .body, rubySize: 9, lineSpacing: 4))
                        }
                        .padding(.leading, 2)
                    }
                }
            }
        }
    }
}

/// 从注意事项文字中拆出「✕「…」」「○「…」」例句，按原文顺序返回文字与例句。
enum NoteParser {
    enum Item: Equatable {
        case text(String)
        case example(correct: Bool, sentence: String)
    }

    private static let regex = try! NSRegularExpression(pattern: "([×✕✗Ｘ])\\s*「([^」]+)」|([○〇◯])\\s*「([^」]+)」")
    private static let junk = CharacterSet(charactersIn: " 　→⇒➡，,、。.；;：:（）()").union(.whitespacesAndNewlines)

    static func parse(_ note: String) -> [Item] {
        let ns = note as NSString
        let matches = regex.matches(in: note, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [.text(note)] }
        var items: [Item] = []
        var cursor = 0
        func addText(_ raw: String) {
            let t = clean(raw, isFirst: items.isEmpty)
            if !t.isEmpty { items.append(.text(t)) }
        }
        for m in matches {
            if m.range.location > cursor {
                addText(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)))
            }
            if m.range(at: 2).location != NSNotFound {
                items.append(.example(correct: false, sentence: ns.substring(with: m.range(at: 2))))
            } else {
                items.append(.example(correct: true, sentence: ns.substring(with: m.range(at: 4))))
            }
            cursor = NSMaxRange(m.range)
        }
        if cursor < ns.length { addText(ns.substring(from: cursor)) }
        return items
    }

    private static func clean(_ s: String, isFirst: Bool) -> String {
        let t = isFirst
            ? s.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "：:，,、→ "))
            : s.trimmingCharacters(in: junk)
        // 只剩箭头、标点、括号时视为空
        return t.unicodeScalars.allSatisfy { junk.contains($0) } ? "" : t
    }
}

/// 节标题：线条图标 + 标题。
private struct DocSectionTitle: View {
    let title: LocalizedStringKey
    let icon: String

    init(_ title: LocalizedStringKey, icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        Label {
            Text(localized: title).font(.title2.bold())
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
        }
        .labelStyle(.titleAndIcon)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 滚动与标题

/// 详情页的滚动状态。用 Observation：只有读取这些值的小视图（标题浮层、导航栏标题）会随滚动刷新，
/// 整页讲解不会因为滚动而重新排版。
@Observable
final class DetailScrollModel {
    /// 已向上滚动的距离（内容顶部为 0，下拉回弹时为负）
    var offset: CGFloat = 0
    /// 大标题行的尺寸
    var titleSize: CGSize = .zero
    /// 旧系统：大标题滚出的进度 0~1
    var progress: CGFloat = 0
    @ObservationIgnored var headerBaseline: CGFloat?
}

private struct TitleSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

extension View {
    /// 直接读取滚动偏移（iOS 18+），与内容同一帧更新，标题不会滞后一帧。
    @ViewBuilder
    func trackScrollOffset(_ model: DetailScrollModel) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, new in
                model.offset = new
            }
        } else {
            self
        }
    }
}

/// 大标题浮层：跟着滚动上移，同时缩小并移到导航栏正中；下拉回顶部时还原成大标题。
/// 位置完全由滚动偏移计算（不依赖上一帧测量到的位置），所以惯性滚动时不会闪烁或滞后。
private struct FlyingTitle<Title: View, Compact: View>: View {
    let scroll: DetailScrollModel
    /// 标题在内容中的上边距（与页面内容的 top padding 一致）
    let topPadding: CGFloat
    @ViewBuilder let title: Title
    /// 到达导航栏后显示的单行标题（大标题缩小后字太小、换行的长标题放不下，所以最后交叉淡入这个）
    @ViewBuilder let compact: Compact

    var body: some View {
        let size = scroll.titleSize
        GeometryReader { geo in
            if size != .zero {
                let width = geo.size.width
                let barCenterY: CGFloat = -22   // 导航栏中线（浮层坐标原点在导航栏下沿）
                let endScale = min(0.55, 34 / max(size.height, 1), (width - 150) / max(size.width, 1))
                let targetY = barCenterY - size.height * endScale / 2
                let restY = topPadding
                let travel = max(restY - targetY, 1)
                let progress = min(1, max(0, scroll.offset / travel))
                let y = max(restY - scroll.offset, targetY)
                let x = Theme.margin + ((width - size.width * endScale) / 2 - Theme.margin) * progress
                let scale = 1 - (1 - endScale) * progress
                ZStack(alignment: .topLeading) {
                    // 标题进入导航栏时，顶部出现几乎不透明的毛玻璃底，正文不会透出来和标题叠在一起
                    ZStack(alignment: .bottom) {
                        Rectangle().fill(.regularMaterial)
                        Rectangle().fill(Theme.background.opacity(0.72))
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
                    }
                    .frame(width: width, height: 120)
                    .offset(y: -120)
                    .opacity(Double(min(1, progress * 1.4)))
                    let swap = Double(min(1, max(0, (progress - 0.72) / 0.28)))
                    title
                        .frame(width: size.width, height: size.height, alignment: .topLeading)
                        .scaleEffect(scale, anchor: .topLeading)
                        .offset(x: x, y: y)
                        .opacity(1 - swap)
                    compact
                        .frame(maxWidth: width - 150)
                        .frame(width: width, height: 44)
                        .offset(y: barCenterY - 22 + (1 - swap) * 6)
                        .opacity(swap)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 旧系统（iOS 17–25）：大标题随滚动淡出。
private struct FadingHeader<Content: View>: View {
    let scroll: DetailScrollModel
    @ViewBuilder let content: Content

    var body: some View {
        content.opacity(1 - Double(scroll.progress) * 0.9)
    }
}

/// 旧系统：导航栏标题随大标题滚出而淡入。
private struct LegacyNavTitle<Content: View>: View {
    let scroll: DetailScrollModel
    @ViewBuilder let content: Content

    var body: some View {
        content
            .opacity(Double(scroll.progress))
            .offset(y: (1 - scroll.progress) * 10)
            .animation(.easeOut(duration: 0.15), value: scroll.progress)
            .accessibilityHidden(scroll.progress < 0.5)
    }
}

private struct HeaderFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

extension GrammarDetailView {
    /// 扫描到的原文最接近哪一个用法：比较原文与各用法的接续说明、例句的最长公共片段（平假名、片假名视为相同）。
    /// 只有一个用法、或无法区分时返回 nil。
    static func bestSense(for matched: String, in p: GrammarPoint) -> Int? {
        guard p.senses.count > 1 else { return nil }
        func norm(_ s: String) -> [Character] {
            let t = s.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
            return Array(t.applyingTransform(.hiraganaToKatakana, reverse: true) ?? t)
        }
        func lcs(_ a: [Character], _ b: [Character]) -> Int {
            guard !a.isEmpty, !b.isEmpty else { return 0 }
            var prev = [Int](repeating: 0, count: b.count + 1), best = 0
            for i in 1...a.count {
                var cur = [Int](repeating: 0, count: b.count + 1)
                for j in 1...b.count where a[i - 1] == b[j - 1] {
                    cur[j] = prev[j - 1] + 1
                    best = max(best, cur[j])
                }
                prev = cur
            }
            return best
        }
        let m = norm(matched)
        let scores = p.senses.map { sense -> Int in
            ([sense.connection, sense.label] + sense.examples.map(\.ja)).map { lcs(m, norm($0)) }.max() ?? 0
        }
        guard let best = scores.max(), best >= 2, scores.filter({ $0 == best }).count == 1 else { return nil }
        return scores.firstIndex(of: best)
    }
}

/// 讲解页顶部：你扫到的原文，以及它对应的用法
private struct ScannedMatchBanner: View {
    let matched: String
    let senseIndex: Int?
    let senseLabel: String?
    let onJump: () -> Void

    private var shown: String {
        let t = matched.replacingOccurrences(of: "\n", with: "")
        return t.count > 16 ? String(t.prefix(7)) + "…" + String(t.suffix(7)) : t
    }

    var body: some View {
        Button(action: onJump) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "text.viewfinder").foregroundStyle(Theme.accentText)
                VStack(alignment: .leading, spacing: 3) {
                    (Text(localized: "你扫到的：") + Text(verbatim: "「\(shown)」")).font(.subheadline.weight(.semibold))
                    if let senseIndex, let senseLabel {
                        (Text(localized: "对应 用法 ") + Text(verbatim: "\(senseIndex + 1)　\(senseLabel)"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if senseIndex != nil {
                    Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(senseIndex == nil)
        .accessibilityIdentifier("detail.scannedMatch")
    }
}
