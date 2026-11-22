import SwiftUI

/// 点击高亮块后：只有一个语法点就直接跳转；有多个（重叠）时弹出选择。
struct GrammarChooserModifier: ViewModifier {
    @Binding var cluster: HighlightCluster?
    let library: GrammarLibrary
    /// 选中的语法点 id，以及它在原文里命中的文字（讲解页据此定位到对应的用法）
    let onSelect: (String, String?) -> Void

    func body(content: Content) -> some View {
        content
            .tint(Theme.accent)
            .confirmationDialog(
            tr("这里有多个语法点，请选择"),
            isPresented: Binding(
                get: { (cluster?.grammarIDs.count ?? 0) > 1 },
                set: { if !$0 { cluster = nil } }
            ),
            titleVisibility: .visible,
            presenting: cluster
        ) { c in
            ForEach(c.grammarIDs, id: \.self) { id in
                if let p = library.point(id: id) {
                    // 附上命中的原文，一眼看出这个语法点对应框里的哪几个字
                    Button { onSelect(id, c.matchedTexts[id]) } label: {
                        Text(verbatim: "\(p.displayTitle) (\(p.level.rawValue))" + (c.excerpt(for: id).map { "　「\($0)」" } ?? ""))
                    }
                }
            }
            Button(tr("取消"), role: .cancel) { cluster = nil }
        }
        // 选项文字用主文字色（Build 17 反馈 7），页面本身仍用主题色
        .tint(Color.primary)
        .onChange(of: cluster) { _, newValue in
            if let c = newValue, c.grammarIDs.count == 1 {
                cluster = nil
                onSelect(c.grammarIDs[0], c.matchedTexts[c.grammarIDs[0]])
            }
        }
    }
}

extension View {
    func grammarChooser(cluster: Binding<HighlightCluster?>, library: GrammarLibrary, onSelect: @escaping (String, String?) -> Void) -> some View {
        modifier(GrammarChooserModifier(cluster: cluster, library: library, onSelect: onSelect))
    }
}
