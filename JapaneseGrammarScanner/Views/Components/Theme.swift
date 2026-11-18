import SwiftUI

/// 全 App 配色：一个主色（靛蓝，见 Assets 的 AccentColor，浅色/深色两套）+ 系统黑白灰。
/// 颜色只用来表达含义（重点、可点击、选中），不做装饰。
enum Theme {
    /// 主色：例句里的目标语法、主按钮、选中状态、收藏星。
    static let accent = Color.accentColor
    /// 主色浅底：目标语法底色、「常考」标签底色。
    static let accentFill = Color.accentColor.opacity(0.14)
    /// 内容区左右边距（HIG 标准阅读边距）。
    static let margin: CGFloat = 20
}

extension View {
    /// iOS 26+ 使用 Liquid Glass；更早的系统退回系统材质，外观一致、功能相同。
    @ViewBuilder
    func glassBackground<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }

    /// 主操作按钮：iOS 26+ 为带主色的 Liquid Glass 按钮，旧系统为主色填充按钮。
    @ViewBuilder
    func prominentGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// 次要按钮：iOS 26+ 为 Liquid Glass 按钮，旧系统为浅色描边按钮。
    @ViewBuilder
    func secondaryGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
