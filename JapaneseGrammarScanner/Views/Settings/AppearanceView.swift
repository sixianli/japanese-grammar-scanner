import SwiftUI

/// 外观：主题色、浅色模式背景、深色模式背景。只提供对眼睛友好、温和的颜色。（在设置面板中推入显示）
struct AppearanceView: View {
    @EnvironmentObject private var appearance: AppearanceStore
    var body: some View {
            List {
                Section {
                    swatches(AppearanceStore.AccentOption.allCases, selected: appearance.accent,
                             color: { Theme.color($0.hex.0) }, name: { $0.name }) { appearance.accent = $0 }
                } header: {
                    Text("主题色")
                }
                Section {
                    swatches(AppearanceStore.LightBackground.allCases, selected: appearance.light,
                             color: { Theme.color($0.hex.0) }, name: { $0.name }) { appearance.light = $0 }
                } header: {
                    Text("浅色模式背景")
                }
                Section {
                    swatches(AppearanceStore.DarkBackground.allCases, selected: appearance.dark,
                             color: { Theme.color($0.hex.0) }, name: { $0.name }) { appearance.dark = $0 }
                } header: {
                    Text("深色模式背景")
                } footer: {
                    Text("浅色、深色背景分别生效，随系统的深浅模式自动切换。")
                }
            }
            .themedList()
            .navigationTitle("外观")
            .navigationBarTitleDisplayMode(.inline)
    }

    private func swatches<T: Identifiable & Equatable>(_ items: [T], selected: T, color: @escaping (T) -> UIColor,
                                                       name: @escaping (T) -> LocalizedStringKey,
                                                       onSelect: @escaping (T) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 14) {
            ForEach(items) { item in
                Button { withAnimation(.easeOut(duration: 0.2)) { onSelect(item) } } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(Color(uiColor: color(item)))
                            .frame(width: 40, height: 40)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                            .overlay(
                                Circle().strokeBorder(Theme.accent, lineWidth: item == selected ? 3 : 0)
                                    .padding(-4)
                            )
                            .overlay {
                                if item == selected {
                                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.secondary)
                                }
                            }
                        Text(name(item)).font(.caption).foregroundStyle(Color.primary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item == selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(Theme.card)
    }
}
