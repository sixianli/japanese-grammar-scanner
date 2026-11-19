import SwiftUI

/// 语法点详细讲解：一整页连续阅读的讲义（不分卡片），铺满屏幕宽度，只保留标准阅读边距。
/// 颜色只用在重点上：例句里的目标语法（主色）；其余为黑白灰。
struct GrammarDetailView: View {
    let grammarID: String
    @EnvironmentObject private var library: GrammarLibrary
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var entitlements: EntitlementStore
    @EnvironmentObject private var history: HistoryStore
    /// 大标题滚出屏幕的进度 0~1（旧系统用于把标题淡入顶部导航栏）
    @State private var titleProgress: CGFloat = 0
    @State private var headerBaseline: CGFloat?
    /// 标题行当前位置与初始位置（屏幕坐标），用于让标题跟着手指移动、缩小到顶部导航栏正中
    @State private var titleFrame: CGRect = .zero
    @State private var titleBaseline: CGRect?
    /// 内容区顶部（导航栏下沿）在屏幕上的位置
    @State private var contentTop: CGFloat = 0

    /// iOS 26+ 导航栏透明（Liquid Glass），标题可以直接“飞”进导航栏；更早的系统用淡入方式。
    private var usesFlyingTitle: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

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
        let showsSenseLevels = p.levels.count > 1
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(p, titleHidden: usesFlyingTitle && titleBaseline != nil)
                        .opacity(usesFlyingTitle ? 1 : 1 - Double(titleProgress) * 0.9)
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(key: HeaderFrameKey.self, value: g.frame(in: .named("detailScroll")))
                            }
                        )

                    // 概述
                    RubyText(explanation: p.meaning, style: .init(font: .body, lineSpacing: 7))
                        .padding(.top, 14)

                    // 义项目录：整行可点，跳到下方对应用法
                    SenseOutline(point: p, showsLevels: showsSenseLevels, tappable: entitlements.hasFullAccess) { i in
                        withAnimation(.easeInOut) { proxy.scrollTo("sense-\(i)", anchor: .top) }
                    }
                    .padding(.top, 18)

                    if !entitlements.hasFullAccess {
                        LockedContentCard().padding(.top, 28)
                    } else {
                        DocSection("用法", icon: "text.book.closed") {
                            VStack(alignment: .leading, spacing: 34) {
                                ForEach(Array(p.senses.enumerated()), id: \.offset) { i, sense in
                                    SenseBlock(index: i + 1, sense: sense,
                                               level: showsSenseLevels ? p.level(of: sense) : nil,
                                               regexes: regexes)
                                        .id("sense-\(i)")
                                }
                            }
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

                        if !p.similar.isEmpty {
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
                        Text("讲解有误或看不懂？")
                        Text("告诉我们").foregroundStyle(Theme.accentText)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 40)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .coordinateSpace(name: "detailScroll")
            .onAppear {
                // CI 截图：滚动到指定位置
                if let anchor = DemoMode.scrollAnchor {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { proxy.scrollTo(anchor, anchor: .top) }
                }
            }
            .onPreferenceChange(HeaderFrameKey.self) { frame in
                // 以初始位置为基准，标题向上移出自身高度的过程中，进度从 0 平滑变到 1
                if headerBaseline == nil { headerBaseline = frame.minY }
                let moved = (headerBaseline ?? frame.minY) - frame.minY
                let progress = min(1, max(0, moved / max(frame.height, 1)))
                if abs(progress - titleProgress) > 0.005 { titleProgress = progress }
            }
        }
        .background(Theme.background)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { contentTop = g.frame(in: .global).minY }
                .onChange(of: g.frame(in: .global).minY) { _, v in contentTop = v }
        })
        .overlay(alignment: .topLeading) {
            if usesFlyingTitle { flyingTitle(p) }
        }
        .onPreferenceChange(TitleFrameKey.self) { frame in
            guard frame != .zero else { return }
            if titleBaseline == nil { titleBaseline = frame }
            titleFrame = frame
        }
        .navigationTitle(p.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if usesFlyingTitle {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                } else {
                    HStack(alignment: .top, spacing: 3) {
                        Text(verbatim: p.titleForm).font(.headline)
                        LevelBadge(level: p.level, small: true)
                    }
                    .opacity(Double(titleProgress))
                    .offset(y: (1 - titleProgress) * 10)
                    .animation(.easeOut(duration: 0.15), value: titleProgress)
                    .accessibilityHidden(titleProgress < 0.5)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    favorites.toggle(p.id)
                } label: {
                    Image(systemName: favorites.isFavorite(p.id) ? "star.fill" : "star")
                        .foregroundStyle(Theme.accent)
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

    /// 标题跟着手指上移，同时缩小并移到导航栏正中；滑回顶部时还原成大标题。
    @ViewBuilder
    private func flyingTitle(_ p: GrammarPoint) -> some View {
        if let measured = titleBaseline {
            // 起点固定为页面未滚动时标题的位置（内容顶部 + 上边距），不依赖第一次测到的位置，
            // 这样即使页面一打开就被滚动，标题的起点和终点也都正确
            let base = CGRect(x: measured.minX, y: contentTop + 8, width: titleFrame.width, height: titleFrame.height)
            GeometryReader { geo in
                let origin = geo.frame(in: .global).origin
                let screenWidth = geo.size.width
                let barCenterY = contentTop - 22
                // 最终大小：能放进导航栏（返回键与收藏键之间）
                let endScale = min(0.55, 34 / max(base.height, 1), (screenWidth - 150) / max(base.width, 1))
                let targetY = barCenterY - base.height * endScale / 2
                let travel = max(base.minY - targetY, 1)
                let progress = min(1, max(0, (base.minY - titleFrame.minY) / travel))
                let scale = 1 - (1 - endScale) * progress
                let y = max(titleFrame.minY, targetY)
                // 横向位置用本页坐标计算（页面推入动画期间屏幕坐标的 x 会变化）
                let x = Theme.margin + ((screenWidth - base.width * endScale) / 2 - Theme.margin) * progress
                titleRow(p)
                    .frame(width: base.width, alignment: .leading)
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: x, y: y - origin.y)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func header(_ p: GrammarPoint, titleHidden: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow(p)
                .opacity(titleHidden ? 0 : 1)
                .background(GeometryReader { g in
                    Color.clear.preference(key: TitleFrameKey.self, value: g.frame(in: .global))
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
            Label {
                Text(title).font(.title2.bold())
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26)
            }
            .labelStyle(.titleAndIcon)
            .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 40)
        .id(anchor ?? "")
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
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .disabled(!tappable)
                .accessibilityHint(tappable ? Text("跳到用法") : Text(verbatim: ""))
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
                Text("接续").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
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
                Text(label).font(.title3.weight(.semibold)).foregroundStyle(Color.primary)
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
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(correct ? Color.green : Color.red)
                                .padding(.top, 15)
                                .accessibilityLabel(correct ? Text("正确") : Text("错误"))
                            RubyText(japanese: sentence, style: .init(font: .body, rubySize: 9, lineSpacing: 4))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background((correct ? Color.green : Color.red).opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

private struct TitleFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct HeaderFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
