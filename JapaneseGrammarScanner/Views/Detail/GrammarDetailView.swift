import SwiftUI

/// 语法点详细讲解：一整页连续阅读的讲义（不分卡片），铺满屏幕宽度，只保留标准阅读边距。
/// 颜色只用在重点上：例句里的目标语法（主色）；其余为黑白灰。
struct GrammarDetailView: View {
    let grammarID: String
    /// 从扫描结果打开时，原文里命中的文字（用于显示「你扫到的」并找出对应的用法）
    var matchedText: String? = nil
    /// 从首页「快要忘了」进来复习时，之后还要复习的语法（nil = 不是从复习进来的）
    var reviewQueue: [String]? = nil
    @EnvironmentObject private var library: GrammarLibrary
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var entitlements: EntitlementStore
    @EnvironmentObject private var history: HistoryStore
    /// 滚动相关的状态放在单独的对象里：只有标题浮层读取它，滚动时不会让整页内容重新排版（否则会卡顿、闪烁）。
    @State private var scroll = DetailScrollModel()
    /// iOS 26+：自己画的标题栏在导航栏区域以下的高度（标题一行或两行 + 等级），页面标题要从它下面开始
    @State private var barContentHeight: CGFloat = TitleBarLayout.navBarHeight

    /// iOS 26+ 导航栏透明（Liquid Glass），标题可以直接“飞”进导航栏；更早的系统用淡入方式。
    private var usesFlyingTitle: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    var body: some View {
        if let point = library.point(id: grammarID) {
            content(point)
                // 复习自评条只在从首页「快要忘了」进来时出现；从语法库、搜索、扫描结果等打开都不出现。
                // 复习时隐藏底部标签栏，自评条独占底部。
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let reviewQueue {
                        ReviewBar(grammarID: point.id, queue: reviewQueue)
                    }
                }
                .toolbar(reviewQueue != nil ? .hidden : .automatic, for: .tabBar)
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
                if usesFlyingTitle {
                    // 页面大标题正常随内容滚走，滚到标题栏下面就被不透明的标题栏盖住；
                    // 标题栏里的小标题按滚动距离一比一从下往上移到正中（Build 17 反馈 1）
                    header(p)
                        .padding(.horizontal, Theme.margin)
                        .padding(.top, TitleBarLayout.headerTopPadding(barContentHeight: barContentHeight))
                }
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !usesFlyingTitle {
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

                        if let contrasts = library.contrasts(for: p.id) {
                            // 新版：分三组 + 对比例句。新版资料里没有合格内容（groups 为空）时整节不显示，不退回旧版列表
                            if !contrasts.groups.isEmpty {
                                DocSection("相近语法", icon: "arrow.triangle.branch", anchor: "section-similar") {
                                    ContrastSection(contrasts: contrasts, currentTitle: p.titleForm)
                                }
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
                .padding(.top, usesFlyingTitle ? 0 : 8)
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
            .modifier(ScrollOffsetTracker(scroll: scroll))
            .overlay(alignment: .top) {
                if usesFlyingTitle {
                    DetailTitleBar(title: p.titleForm, level: p.level, scroll: scroll, contentHeight: $barContentHeight)
                }
            }
            .modifier(DemoScrollOffset())
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
        }
        .background(Theme.background)
        .navigationTitle(p.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if usesFlyingTitle {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                } else {
                    LegacyNavTitle(scroll: scroll) {
                        VStack(spacing: 2) {
                            Text(verbatim: p.titleForm).font(.headline).lineLimit(2).multilineTextAlignment(.center)
                            LevelText(level: p.level, small: true)
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

    /// 页面顶部：标题居中（汉字上方注假名），下面一行居中放等级和「必考」。
    private func header(_ p: GrammarPoint) -> some View {
        VStack(alignment: .center, spacing: 10) {
            RubyText(japanese: p.titleForm, style: .init(font: .largeTitle.bold(), rubySize: 12, lineSpacing: 2,
                                                       alignment: .center))
            DetailTags(level: p.level, mustKnow: p.frequency == .high)
        }
        .frame(maxWidth: .infinity)
        // 端到端测试用：页面最顶部的标记（label 是语法标题），用来确认打开的是哪个语法、页面是否在顶部
        .overlay(alignment: .top) {
            Color.clear.frame(width: 2, height: 2)
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: p.titleForm))
                .accessibilityIdentifier("detail.title")
        }
    }

    @ViewBuilder
    private func similarItem(_ s: GrammarPoint.Similar) -> some View {
        let target = s.id.flatMap { library.point(id: $0) } ?? library.point(matchingTitle: s.title)
        let row = VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                Text(target?.titleForm ?? s.title).font(.headline).foregroundStyle(Color.primary)
                if let target { LevelBadge(level: target.level) }
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
                            HStack(alignment: .center, spacing: 6) {
                                Text(sense.label).font(.body.weight(.semibold)).foregroundStyle(Color.primary)
                                if showsLevels { LevelBadge(level: point.level(of: sense)) }
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
                HStack(alignment: .center, spacing: 6) {
                    Text(sense.label).font(.title3.weight(.semibold))
                    if let level { LevelBadge(level: level) }
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
    /// 旧系统：大标题滚出的进度 0~1
    var progress: CGFloat = 0
    /// iOS 26+：往上滚了多少（0 = 在顶部）
    var offset: CGFloat = 0
    @ObservationIgnored var headerBaseline: CGFloat?
}

/// QA 截图：按启动参数 -demoScrollY 把讲解页滚到指定位置（iOS 18+）
private struct DemoScrollOffset: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let y = DemoMode.scrollY {
            Scrolled(content: content, y: y)
        } else {
            content
        }
    }

    @available(iOS 18.0, *)
    private struct Scrolled: View {
        let content: Content
        let y: CGFloat
        @State private var position = ScrollPosition(edge: .top)
        var body: some View {
            content
                .scrollPosition($position)
                .task {
                    try? await Task.sleep(for: .milliseconds(800))
                    position.scrollTo(y: y)
                }
        }
    }
}

/// iOS 26+ 标题栏的几何（纯计算，单元测试覆盖）。
/// 页面大标题随内容滚动，滚到标题栏下沿就被不透明的标题栏盖住；此后每滚 1pt，标题栏里的小标题从下往上移 1pt，
/// 移到标题栏正中后停住；往回滚时反过来。标题字号固定，不缩放。
enum TitleBarLayout {
    /// 系统导航栏高度（返回、收藏按钮所在的一行）
    static let navBarHeight: CGFloat = 44
    /// 页面标题和标题栏下沿之间的距离
    static let topPadding: CGFloat = 8
    /// 标题栏里标题块上下的留白
    static let barVerticalPadding: CGFloat = 6
    /// 左右各留出一个按钮（44）加边距的宽度
    static let sideInset: CGFloat = 68

    /// 标题栏（状态栏以下部分）的高度：至少一行导航栏高，标题两行时变高
    static func barContentHeight(titleBlockHeight: CGFloat) -> CGFloat {
        max(navBarHeight, titleBlockHeight + 2 * barVerticalPadding)
    }

    /// 页面标题的上边距：标题栏比系统导航栏高出的部分也要让出来，没滚动时页面标题不被盖住
    static func headerTopPadding(barContentHeight: CGFloat) -> CGFloat {
        max(0, barContentHeight - navBarHeight) + topPadding
    }

    /// 标题栏里的小标题相对正中位置往下偏移多少（0 = 在正中；等于 travel = 完全藏在标题栏下沿以下）
    static func titleOffset(scrolled: CGFloat, barContentHeight: CGFloat) -> CGFloat {
        let travel = barContentHeight
        return min(travel, max(0, travel - (scrolled - topPadding)))
    }

    /// 标题栏下沿分隔线的不透明度：页面标题碰到标题栏下沿时开始出现
    static func dividerOpacity(scrolled: CGFloat) -> Double {
        Double(min(1, max(0, scrolled / topPadding)))
    }
}

/// iOS 26+：详情页顶部自己画的标题栏。毛玻璃但几乎不透明，铺到屏幕顶端；返回、收藏按钮由系统导航栏画在它上面。
/// 标题居中、最多两行、字号不缩小，等级在标题正下方居中。
private struct DetailTitleBar: View {
    let title: String
    let level: JLPTLevel
    let scroll: DetailScrollModel
    @Binding var contentHeight: CGFloat

    var body: some View {
        // 铺满整个滚动视图量出安全区高度（状态栏 + 系统导航栏），标题栏从屏幕顶端画起
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let offset = TitleBarLayout.titleOffset(scrolled: scroll.offset, barContentHeight: contentHeight)
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    // 安全区顶部包含状态栏和系统导航栏；标题区从系统导航栏那一行开始，和返回、收藏按钮同一行起
                    Color.clear.frame(height: max(0, safeTop - TitleBarLayout.navBarHeight))
                    ZStack {
                        VStack(spacing: 2) {
                            Text(verbatim: title)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .accessibilityIdentifier("detail.barTitle")
                            LevelText(level: level, small: true)
                                .accessibilityIdentifier("detail.barLevel")
                        }
                        .padding(.horizontal, TitleBarLayout.sideInset)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                            let bar = TitleBarLayout.barContentHeight(titleBlockHeight: h)
                            if abs(bar - contentHeight) > 0.5 { contentHeight = bar }
                        }
                        .offset(y: offset)
                        .opacity(offset >= contentHeight ? 0 : 1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: contentHeight)
                    .clipped()
                }
                .background {
                    ZStack(alignment: .bottom) {
                        Rectangle().fill(.regularMaterial)
                        Rectangle().fill(Theme.background.opacity(0.94))
                        Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5)
                            .opacity(TitleBarLayout.dividerOpacity(scrolled: scroll.offset))
                    }
                }
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .top)
        }
        .allowsHitTesting(false)
    }
}

/// 记录详情页往上滚了多少（iOS 18+ 才有滚动几何回调；更早的系统用旧的淡入方式，不需要）
private struct ScrollOffsetTracker: ViewModifier {
    let scroll: DetailScrollModel

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { g in
                g.contentOffset.y + g.contentInsets.top
            } action: { _, y in
                if abs(y - scroll.offset) > 0.25 { scroll.offset = y }
            }
        } else {
            content
        }
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
