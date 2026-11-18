import SwiftUI

/// 点击高亮块后：只有一个语法点就直接跳转；有多个（重叠）时弹出选择。
struct GrammarChooserModifier: ViewModifier {
    @Binding var cluster: HighlightCluster?
    let library: GrammarLibrary
    let onSelect: (String) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "这里有多个语法点，请选择",
            isPresented: Binding(
                get: { (cluster?.grammarIDs.count ?? 0) > 1 },
                set: { if !$0 { cluster = nil } }
            ),
            titleVisibility: .visible,
            presenting: cluster
        ) { c in
            ForEach(c.grammarIDs, id: \.self) { id in
                if let p = library.point(id: id) {
                    Button { onSelect(id) } label: { Text(verbatim: "\(p.displayTitle) (\(p.level.rawValue))") }
                }
            }
            Button("取消", role: .cancel) { cluster = nil }
        }
        .onChange(of: cluster) { _, newValue in
            if let c = newValue, c.grammarIDs.count == 1 {
                cluster = nil
                onSelect(c.grammarIDs[0])
            }
        }
    }
}

extension View {
    func grammarChooser(cluster: Binding<HighlightCluster?>, library: GrammarLibrary, onSelect: @escaping (String) -> Void) -> some View {
        modifier(GrammarChooserModifier(cluster: cluster, library: library, onSelect: onSelect))
    }
}
