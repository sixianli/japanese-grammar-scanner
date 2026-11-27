import SwiftUI

struct GrammarDetailView: View {
    let grammarID: String
    var matchedText: String? = nil
    var reviewQueue: [String]? = nil
    @EnvironmentObject private var library: GrammarLibrary
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var entitlements: EntitlementStore
    @EnvironmentObject private var history: HistoryStore
    @State private var scroll = DetailScrollModel()

    private var usesFlyingTitle: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    var body: some View {
        if let point = library.point(id: grammarID) {
            content(point)
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
                    header(p)
                        .padding(.horizontal, Theme.margin)
                        .padding(.top, TitleBarLayout.topPadding)
                }
                VStack(alignment: .leading, spacing: 0) {
                    if !usesFlyingTitle {
                        FadingHeader(scroll: scroll) { header(p) }
                            .background(GeometryReader { g in
                                Color.clear.preference(key: HeaderFrameKey.self, value: g.frame(in: .named("detailScroll")))
                            })
                    }

                    let focus = matchedText.flatMap { Self.bestSense(for: $0, in: p) }
                    if let matchedText {
                        ScannedMatchBanner(matched: matchedText, senseIndex: focus,
                                           senseLabel: focus.map { p.senses[$0].label }) {
                            if let focus { withAnimation(.easeInOut) { proxy.scrollTo("sense-\(focus)", anchor: .top) } }
                        }
                        .padding(.top, 14)
                    }

                    RubyText(explanation: p.meaning, style: .init(font: .body, lineSpacing: 7))
                        .padding(.top, 14)

                    SenseOutline(point: p, showsLevels: showsSenseLevels, tappable: entitlements.hasFullAccess,
                                 highlighted: focus) { i in
                        withAnimation(.easeInOut) { proxy.scrollTo("sense-\(i)", anchor: .top) }
                    }
                    .padding(.top, 18)

                    if !entitlements.hasFullAccess {
                        LockedContentCard().padding(.top, 28)
                    } else {
                        DocSectionTitle("用法", icon: "text.book.closed")
                            .padding(.top, 40)
                            .padding(.bottom, 14)
                        ForEach(Array(p.senses.enumerated()), id: \.offset) { i, sense in
                            SenseBlock(index: i + 1, sense: sense,
                                       level: showsSenseLevels ? p.level(of: sense) : nil,
                                       regexes: regexes)
                                .padding(.bottom, i < p.senses.count - 1 ? 34 : 0)
                                .background(alignment: .top) {
                                    Color.clear
                                        .frame(height: 1)
                                        .alignmentGuide(.top) { _ in senseJumpGap }
                                        .id("sense-\(i)")
                                }
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("detail.sense")
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

                        let origin = p.formation.isEmpty ? p.etymology : p.formation
                        if !origin.isEmpty {
                            DocSection("来源与构成", icon: "puzzlepiece.extension") {
                                RubyText(explanation: origin, style: .init(font: .body, lineSpacing: 7))
                            }
                        }

                        if let contrasts = library.contrasts(for: p.id) {
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
            .modifier(ContentHeightProbe())
            .overlay(alignment: .top) {
                if usesFlyingTitle {
                    FlyingTitle(point: p, scroll: scroll)
                }
            }
            .modifier(DemoScrollOffset())
            .onAppear {
                if let anchor = DemoMode.scrollAnchor {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { proxy.scrollTo(anchor, anchor: .top) }
                }
            }
            .onPreferenceChange(HeaderFrameKey.self) { [scroll] frame in
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
            if !favorites.isFavorite(p.id) {
                ToolbarItem(placement: .topBarTrailing) {
                    FavoriteSakuraButton(id: p.id, flightStyle: reviewQueue == nil ? .intoPouch : .away,
                                         confirmsSaved: reviewQueue != nil)
                        .accessibilityIdentifier("detail.favorite")
                }
            }
        }
    }

    static func connectionLines(_ s: String) -> [String] {
        let parts = s.split(whereSeparator: { $0 == "；" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [s] : parts
    }

    private func header(_ p: GrammarPoint) -> some View {
        VStack(alignment: .center, spacing: 10) {
            headerTitle(p)
            if usesFlyingTitle {
                HeaderTags(point: p)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { [scroll] height in
                        if abs(height - scroll.tagsHeight) > 0.5 { scroll.tagsHeight = height }
                    }
            } else {
                HeaderTags(point: p)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottomLeading) {
            Color.clear.frame(width: 2, height: 2)
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: p.titleForm))
                .accessibilityIdentifier("detail.title")
        }
    }

    static let titleStyle = RubyText.Style(font: .largeTitle.bold(), rubySize: 12, lineSpacing: 2, alignment: .center)

    private var senseJumpGap: CGFloat {
        guard usesFlyingTitle else { return TitleBarLayout.jumpBreathingRoom }
        return TitleBarLayout.jumpGap(lineSize: scroll.lineSize, restTagsHeight: scroll.tagsHeight,
                                      viewWidth: scroll.contentWidth + 2 * Theme.margin)
    }

    @ViewBuilder
    private func headerTitle(_ p: GrammarPoint) -> some View {
        let title = RubyText(japanese: p.titleForm, style: Self.titleStyle)
        if usesFlyingTitle {
            let scale = TitleBarLayout.expandedScale(lineWidth: scroll.lineSize.width, contentWidth: scroll.contentWidth)
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: scroll.lineSize.height * scale)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { [scroll] width in
                    if abs(width - scroll.contentWidth) > 0.5 { scroll.contentWidth = width }
                }
                .overlay {
                    title
                        .fixedSize()
                        .opacity(0)
                        .accessibilityHidden(true)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { [scroll] size in
                            if abs(size.width - scroll.lineSize.width) > 0.5 || abs(size.height - scroll.lineSize.height) > 0.5 {
                                scroll.lineSize = size
                            }
                        }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("detail.titleColumn")
        } else {
            title
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
            RubyText(explanation: s.explanation, style: .init(font: .callout, lineSpacing: 5))
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

private struct NumberBadge: View {
    let number: Int

    var body: some View {
        Text(verbatim: "\(number)")
            .font(.footnote.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Theme.accentText)
            .frame(width: 24, height: 24)
            .background(Theme.accentFill, in: Circle())
    }
}

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
                                RubyText(explanation: line, style: .init(font: .subheadline, lineSpacing: 4))
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
                        let rubyLine = FuriganaStore.shared.hasRuby(sentence)
                            ? ceil(UIFontMetrics(forTextStyle: .body).scaledValue(for: 9) * 1.3) : 0
                        let lineHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
                        HStack(alignment: .top, spacing: 8) {
                            VerdictIcon(correct: correct)
                                .frame(height: lineHeight)
                                .padding(.top, rubyLine)
                            RubyText(japanese: sentence, style: .init(font: .body, rubySize: 9,
                                                                      color: correct ? .primary : .secondary, lineSpacing: 4))
                        }
                        .padding(.leading, 2)
                    }
                }
            }
        }
    }
}

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
        return t.unicodeScalars.allSatisfy { junk.contains($0) } ? "" : t
    }
}

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

@Observable
final class DetailScrollModel {
    var progress: CGFloat = 0
    var offset: CGFloat = 0
    var lineSize: CGSize = .zero
    var contentWidth: CGFloat = 0
    var tagsHeight: CGFloat = 0
    @ObservationIgnored var headerBaseline: CGFloat?
}

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

enum TitleBarLayout {
    static let navBarHeight: CGFloat = 44
    static let topPadding: CGFloat = 8
    static let maxPinnedScale: CGFloat = 0.5
    static let tagsGap: CGFloat = 2
    static let restTagsGap: CGFloat = 10
    static let tagsHeight: CGFloat = 20
    static let barSideInset: CGFloat = 68
    static let barBelowContent: CGFloat = 6

    struct State: Equatable {
        var titleTop: CGFloat
        var scale: CGFloat
        var expandedScale: CGFloat
        var pinnedScale: CGFloat
        var progress: CGFloat
        var tagsTop: CGFloat
        var tagsScale: CGFloat
        var barBottom: CGFloat
        var pillOpacity: Double
    }

    static let jumpBreathingRoom: CGFloat = 12

    static func jumpGap(lineSize: CGSize, restTagsHeight: CGFloat, viewWidth: CGFloat) -> CGFloat {
        let pinned = state(scrolled: 100_000, lineSize: lineSize, restTagsHeight: restTagsHeight, viewWidth: viewWidth, safeTop: 0)
        return max(0, pinned.barBottom) + jumpBreathingRoom
    }

    static func expandedScale(lineWidth: CGFloat, contentWidth: CGFloat) -> CGFloat {
        guard lineWidth > 0, contentWidth > 0 else { return 1 }
        return min(1, contentWidth / lineWidth)
    }

    static func pinnedScale(lineWidth: CGFloat, viewWidth: CGFloat) -> CGFloat {
        guard lineWidth > 0, viewWidth > 0 else { return maxPinnedScale }
        return min(maxPinnedScale, max(0, viewWidth - 2 * barSideInset) / lineWidth)
    }

    static func pinnedTagsScale(restTagsHeight: CGFloat) -> CGFloat {
        guard restTagsHeight > 0 else { return 1 }
        return min(1, tagsHeight / restTagsHeight)
    }

    static func state(scrolled: CGFloat, lineSize: CGSize, restTagsHeight: CGFloat, viewWidth: CGFloat, safeTop: CGFloat) -> State {
        let expanded = expandedScale(lineWidth: lineSize.width, contentWidth: viewWidth - 2 * Theme.margin)
        let pinned = min(expanded, pinnedScale(lineWidth: lineSize.width, viewWidth: viewWidth))
        let rest = safeTop + topPadding
        let current = rest - scrolled
        let pinnedGroup = lineSize.height * pinned + tagsGap + tagsHeight
        let barCenter = safeTop - navBarHeight / 2
        let pinnedTop = max(safeTop - navBarHeight + 2, barCenter - pinnedGroup / 2)
        let travel = max(1, rest - pinnedTop)
        let progress = min(1, max(0, scrolled / travel))
        let scale = expanded + (pinned - expanded) * progress
        let top = max(pinnedTop, current)
        return State(
            titleTop: top,
            scale: scale,
            expandedScale: expanded,
            pinnedScale: pinned,
            progress: progress,
            tagsTop: top + lineSize.height * scale + restTagsGap + (tagsGap - restTagsGap) * progress,
            tagsScale: 1 + (pinnedTagsScale(restTagsHeight: restTagsHeight) - 1) * progress,
            barBottom: max(safeTop, pinnedTop + pinnedGroup + barBelowContent),
            pillOpacity: Double(progress)
        )
    }
}

private struct FlyingTitle: View {
    let point: GrammarPoint
    let scroll: DetailScrollModel

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let size = scroll.lineSize
            let s = TitleBarLayout.state(scrolled: scroll.offset, lineSize: size, restTagsHeight: scroll.tagsHeight,
                                         viewWidth: width, safeTop: proxy.safeAreaInsets.top)
            ZStack(alignment: .top) {
                TitleBarArea(bottom: s.barBottom)
                if size.height > 0 {
                    RubyText(japanese: point.titleForm, style: GrammarDetailView.titleStyle)
                        .fixedSize()
                        .background { GlassPill(scale: s.scale, horizontal: 14, vertical: 4).opacity(s.pillOpacity) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: point.titleForm))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("detail.barTitle")
                        .frame(width: width, height: size.height)
                        .scaleEffect(s.scale, anchor: .top)
                        .offset(y: s.titleTop)
                        .allowsHitTesting(false)
                }
                if size.height > 0, scroll.tagsHeight > 0 {
                    HeaderTags(point: point)
                        .fixedSize()
                        .background { GlassPill(scale: s.tagsScale, horizontal: 6, vertical: 3).opacity(s.pillOpacity) }
                        .frame(width: width, height: scroll.tagsHeight)
                        .scaleEffect(s.tagsScale, anchor: .top)
                        .offset(y: s.tagsTop)
                }
            }
            .frame(width: width)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
        }
    }
}

private struct HeaderTags: View {
    let point: GrammarPoint

    var body: some View {
        HStack(spacing: 8) {
            DetailTags(level: point.level, mustKnow: point.frequency == .high)
            FavoritedTag(id: point.id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.tags")
    }
}

private struct VerdictIcon: View {
    let correct: Bool
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.27, style: .continuous)
        Image(systemName: correct ? "checkmark" : "xmark")
            .font(.system(size: side * 0.5, weight: .semibold))
            .foregroundStyle(correct ? Theme.accentText : Color.secondary)
            .frame(width: side, height: side)
            .background {
                if correct {
                    shape.fill(Theme.accent.opacity(0.18))
                } else {
                    shape.strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(correct ? Text(localized: "正确") : Text(localized: "错误"))
            .accessibilityIdentifier(correct ? "note.correct" : "note.wrong")
    }
}

private struct TitleBarArea: View {
    let bottom: CGFloat

    var body: some View {
        Color.clear
            .frame(height: bottom)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityIdentifier("detail.titleBar")
    }
}

private struct GlassPill: View {
    let scale: CGFloat
    let horizontal: CGFloat
    let vertical: CGFloat

    var body: some View {
        let s = max(scale, 0.1)
        Color.clear
            .glassBackground(in: Capsule())
            .padding(.horizontal, -horizontal / s)
            .padding(.vertical, -vertical / s)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct FavoritedTag: View {
    let id: String
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var confirming = false

    var body: some View {
        if favorites.isFavorite(id) {
            Button { confirming = true } label: {
                HStack(spacing: 4) {
                    Image("Kinchaku")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 15)
                        .foregroundStyle(Sakura.center)
                    Text(localized: "已收藏")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("detail.favorited")
            .accessibilityHint(Text(localized: "点按可取消收藏"))
            .confirmationDialog(tr("已收藏"), isPresented: $confirming, titleVisibility: .hidden) {
                Button(role: .destructive) { favorites.toggle(id) } label: { Text(localized: "取消收藏") }
            }
        }
    }
}

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

private struct ContentHeightProbe: ViewModifier {
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), DemoMode.e2e {
            content
                .onScrollGeometryChange(for: CGFloat.self) { g in
                    g.contentSize.height
                } action: { _, h in
                    height = h
                }
                .overlay(alignment: .bottomTrailing) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(Text(verbatim: "contentHeight"))
                        .accessibilityValue(Text(verbatim: String(Int(height.rounded()))))
                        .accessibilityIdentifier("detail.contentHeight")
                }
        } else {
            content
        }
    }
}

private struct FadingHeader<Content: View>: View {
    let scroll: DetailScrollModel
    @ViewBuilder let content: Content

    var body: some View {
        content.opacity(1 - Double(scroll.progress) * 0.9)
    }
}

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
