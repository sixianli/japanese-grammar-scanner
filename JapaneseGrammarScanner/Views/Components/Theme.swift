import SwiftUI
import UIKit

/// 外观设置：主题色 + 浅色 / 深色模式各自的护眼背景色。保存在本机，在「设置 → 外观」中修改。
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()

    enum AccentOption: String, CaseIterable, Identifiable {
        case matcha, kaki, sakura, orange, celadon
        var id: String { rawValue }
        var name: LocalizedStringKey {
            switch self {
            case .matcha: "抹茶绿"
            case .kaki: "柿子橙"
            case .sakura: "樱花粉"
            case .orange: "橙黄"
            case .celadon: "青磁绿"
            }
        }
        /// (浅色填充, 浅色文字, 深色填充, 深色文字)
        var hex: (UInt32, UInt32, UInt32, UInt32) {
            switch self {
            case .matcha: (0x7A9E5C, 0x587D3E, 0x9CBF7E, 0xAACB8E)
            case .kaki: (0xE07B53, 0xBF5A33, 0xEE9572, 0xF2A587)
            case .sakura: (0xE58FA8, 0xC45C7B, 0xF0A8BD, 0xF4B8CA)
            case .orange: (0xF2A541, 0xB97412, 0xF5B65E, 0xF7C47C)
            case .celadon: (0x5E9E96, 0x427C75, 0x82BDB5, 0x95CAC2)
            }
        }
    }

    enum LightBackground: String, CaseIterable, Identifiable {
        case paper, cream, mint, gray
        var id: String { rawValue }
        var name: LocalizedStringKey {
            switch self {
            case .paper: "纸白"
            case .cream: "米黄"
            case .mint: "豆沙绿"
            case .gray: "浅灰"
            }
        }
        /// (页面背景, 卡片, 填充)
        var hex: (UInt32, UInt32, UInt32) {
            switch self {
            case .paper: (0xF6F1E6, 0xFFFCF6, 0xECE5D6)
            case .cream: (0xF1E7D0, 0xFAF4E6, 0xE6DABF)
            case .mint: (0xE5EEDF, 0xF4F8F1, 0xD8E4D0)
            case .gray: (0xF2F2F7, 0xFFFFFF, 0xE9E9EE)
            }
        }
    }

    enum DarkBackground: String, CaseIterable, Identifiable {
        case charcoal, ink, umber, black
        var id: String { rawValue }
        var name: LocalizedStringKey {
            switch self {
            case .charcoal: "暖炭灰"
            case .ink: "深墨蓝"
            case .umber: "深棕褐"
            case .black: "纯黑"
            }
        }
        var hex: (UInt32, UInt32, UInt32) {
            switch self {
            case .charcoal: (0x1C1A18, 0x282522, 0x312D29)
            case .ink: (0x121821, 0x1C2430, 0x253042)
            case .umber: (0x1E1915, 0x2A231D, 0x342B23)
            case .black: (0x000000, 0x1C1C1E, 0x2C2C2E)
            }
        }
    }

    @Published var accent: AccentOption { didSet { save() } }
    @Published var light: LightBackground { didSet { save() } }
    @Published var dark: DarkBackground { didSet { save() } }

    private let defaults = UserDefaults.standard

    private init() {
        accent = AccentOption(rawValue: defaults.string(forKey: "appearance.accent") ?? "") ?? .matcha
        light = LightBackground(rawValue: defaults.string(forKey: "appearance.light") ?? "") ?? .paper
        dark = DarkBackground(rawValue: defaults.string(forKey: "appearance.dark") ?? "") ?? .charcoal
    }

    /// 外观变化的标识：根视图用它整体刷新配色。
    var key: String { "\(accent.rawValue)-\(light.rawValue)-\(dark.rawValue)" }

    private func save() {
        defaults.set(accent.rawValue, forKey: "appearance.accent")
        defaults.set(light.rawValue, forKey: "appearance.light")
        defaults.set(dark.rawValue, forKey: "appearance.dark")
    }
}

/// 全 App 配色：一个主题色 + 护眼背景 + 系统文字色。颜色只用来表达含义（重点、可点击、选中），不做装饰。
enum Theme {
    private static var store: AppearanceStore { AppearanceStore.shared }

    /// 主题色（按钮、选中状态、底色）。
    static var accent: Color { dynamic(store.accent.hex.0, store.accent.hex.2) }
    /// 用在文字上的主题色（加深一档，保证对比度）：例句里的目标语法、链接。
    /// 照片 / 取景画面上高亮框的颜色：主题色深一档，固定不随深浅色模式变化（照片里的纸面总是浅色）
    static var photoHighlight: Color { Color(uiColor: color(store.accent.hex.1)) }
    /// 深一档的照片高亮色：相邻的两段语法交替使用，好分清
    static var photoHighlightDeep: Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let c = color(store.accent.hex.1)
        guard c.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return photoHighlight }
        return Color(uiColor: UIColor(hue: h, saturation: min(s * 1.1, 1), brightness: b * 0.62, alpha: a))
    }
    static var accentText: Color { dynamic(store.accent.hex.1, store.accent.hex.3) }
    /// 主题色浅底：目标语法底色、「常考」标签底色。
    static var accentFill: Color { accent.opacity(0.18) }
    /// 页面背景
    static var background: Color { dynamic(store.light.hex.0, store.dark.hex.0) }
    /// 卡片、列表行
    static var card: Color { dynamic(store.light.hex.1, store.dark.hex.1) }
    /// 输入框、接续框等浅填充
    static var fill: Color { dynamic(store.light.hex.2, store.dark.hex.2) }
    /// 内容区左右边距（HIG 标准阅读边距）。
    static let margin: CGFloat = 20

    static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        let l = color(light), d = color(dark)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? d : l })
    }
}

extension JLPTLevel {
    /// 等级标签的淡彩色：N5 绿、N4 蓝、N3 黄、N2 橙、N1 红（低饱和，一眼区分等级）。
    var badgeColor: Color {
        switch self {
        case .n5: Theme.dynamic(0x3F8F5E, 0x7FC79A)
        case .n4: Theme.dynamic(0x3C7DB0, 0x84B8E3)
        case .n3: Theme.dynamic(0xA6781A, 0xE2B95E)
        case .n2: Theme.dynamic(0xC0622F, 0xF0A07A)
        case .n1: Theme.dynamic(0xB8475A, 0xEE8C9C)
        }
    }
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

    /// 列表页统一使用护眼背景。
    func themedList() -> some View {
        self.scrollContentBackground(.hidden).background(Theme.background)
    }
}

// MARK: - 收起键盘

extension UIApplication {
    static func dismissKeyboard() {
        shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    /// 列表 + 搜索框：拖动列表或点键盘以外的地方就收起键盘（输入的文字保留）
    func dismissesKeyboardOnTapAndScroll() -> some View {
        scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(TapGesture().onEnded { UIApplication.dismissKeyboard() })
    }

    /// 多行输入：键盘上方加「完成」，下拉表单也能收起（点输入框内部仍是继续编辑）
    func keyboardDoneButton() -> some View {
        scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { UIApplication.dismissKeyboard() }
                        .accessibilityIdentifier("keyboard.done")
                }
            }
    }
}
