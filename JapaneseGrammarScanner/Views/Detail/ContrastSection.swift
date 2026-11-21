import SwiftUI

/// 新版「相近语法」：分成「同一个词变来的 / 长得像的 / 意思差不多的」三组（没有内容的组不显示）。
/// 每一条默认收起，只显示语法名 + 一句话差别；展开后是两句对比例句（本页语法 vs 对方语法）、
/// 常见错误（有时）和「怎么分辨」讲解。点语法名跳到对方的讲解页，点「看例句对比」展开，两个按钮分开。
struct ContrastSection: View {
    let contrasts: GrammarContrasts
    /// 本页语法的标题（例句标签「本页 · 〜たところだ」）
    let currentTitle: String
    @EnvironmentObject private var library: GrammarLibrary
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(Array(contrasts.groups.enumerated()), id: \.offset) { g, group in
                VStack(alignment: .leading, spacing: 10) {
                    groupHeader(group)
                    ForEach(Array(group.items.enumerated()), id: \.offset) { i, item in
                        card(item, key: "\(g)-\(i)")
                    }
                }
            }
        }
        .onAppear {
            // CI 截图：全部展开
            if DemoMode.opensContrasts {
                for (g, group) in contrasts.groups.enumerated() {
                    for i in group.items.indices { expanded.insert("\(g)-\(i)") }
                }
            }
        }
    }

    private func groupHeader(_ group: GrammarContrasts.Group) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localized: Self.name(of: group.kind))
                .font(.headline)
                .foregroundStyle(Theme.accentText)
            RubyText(explanation: group.note, style: .init(font: .subheadline, color: .secondary, lineSpacing: 3))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    static func name(of kind: GrammarContrasts.Group.Kind) -> LocalizedStringKey {
        switch kind {
        case .root: "同一个词变来的"
        case .look: "长得像的"
        case .meaning: "意思差不多的"
        }
    }

    private func card(_ item: GrammarContrasts.Item, key: String) -> some View {
        let target = library.point(id: item.id)
        let isOpen = expanded.contains(key)
        return VStack(alignment: .leading, spacing: 8) {
            titleRow(item, target: target)
            RubyText(explanation: item.diff, style: .init(font: .callout, lineSpacing: 4))

            if isOpen {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                    side(item.current, label: Text(localized: "本页") + Text(verbatim: " · \(item.thisTitle ?? currentTitle)"), isCurrent: true)
                    side(item.other, label: Text(verbatim: item.title ?? target?.titleForm ?? item.id), isCurrent: false)
                    if let wrong = item.wrong { wrongLine(wrong) }
                    explainBox(item.explain)
                }
                .transition(.opacity)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isOpen { expanded.remove(key) } else { expanded.insert(key) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(localized: isOpen ? "收起" : "看例句对比")
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .frame(minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("detail.contrast.toggle")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func titleRow(_ item: GrammarContrasts.Item, target: GrammarPoint?) -> some View {
        let row = HStack(alignment: .center, spacing: 4) {
            Text(verbatim: item.title ?? target?.titleForm ?? item.id)
                .font(.headline)
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.leading)
            if let target { LevelBadge(level: target.level) }
            Spacer(minLength: 8)
            if target != nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())

        if let target {
            NavigationLink(value: Route.grammar(target.id)) { row }
                .buttonStyle(RowPressStyle())
                .accessibilityIdentifier("detail.similar")
        } else {
            row
        }
    }

    /// 一侧的例句：通常一句；这一侧有几种用法不同的形式时，名字只写一次，每种形式一句（标签写明是哪种形式）
    @ViewBuilder
    private func side(_ list: [GrammarContrasts.Sentence], label: Text, isCurrent: Bool) -> some View {
        if list.count == 1, let s = list.first {
            sentence(s, label: label, isCurrent: isCurrent)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                label
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(list.enumerated()), id: \.offset) { _, s in
                    sentence(s, label: nil, isCurrent: isCurrent)
                }
            }
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 2)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("detail.contrast.forms")
        }
    }

    private func sentence(_ s: GrammarContrasts.Sentence, label: Text?, isCurrent: Bool) -> some View {
        let color = isCurrent ? Theme.accentText : Theme.contrastText
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let label {
                    label
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(s.tag)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.13), in: Capsule())
            }
            RubyText(segments: s.segments,
                     style: .init(font: .body, rubySize: 9, highlightColor: color, lineSpacing: 6))
            Text(s.tr)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail.contrast.sentence")
    }

    private func wrongLine(_ w: GrammarContrasts.Wrong) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "✗").font(.body.weight(.bold)).foregroundStyle(Color.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: w.ja ?? "").strikethrough(true, color: .red)
                Text(w.why).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private func explainBox(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(localized: "怎么分辨")
            } icon: {
                Image(systemName: "magnifyingglass")
            }
            .font(.footnote.weight(.bold))
            .foregroundStyle(.secondary)
            RubyText(explanation: text, style: .init(font: .callout, lineSpacing: 5))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
