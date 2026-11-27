import SwiftUI
import UIKit

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

    var key: String { "\(accent.rawValue)-\(light.rawValue)-\(dark.rawValue)" }

    private func save() {
        defaults.set(accent.rawValue, forKey: "appearance.accent")
        defaults.set(light.rawValue, forKey: "appearance.light")
        defaults.set(dark.rawValue, forKey: "appearance.dark")
    }
}

enum Theme {
    private static var store: AppearanceStore { AppearanceStore.shared }

    static var accent: Color { dynamic(store.accent.hex.0, store.accent.hex.2) }
    static let scanHighlightHex: UInt32 = 0xF08A24
    static var scanHighlight: Color { Color(uiColor: color(scanHighlightHex)) }
    static var accentText: Color { dynamic(store.accent.hex.1, store.accent.hex.3) }
    static var contrastText: Color {
        switch store.accent {
        case .matcha, .celadon: dynamic(0xA8501F, 0xF0A57E)
        case .kaki, .sakura, .orange: dynamic(0x3D5F99, 0x9DB8E8)
        }
    }
    static var accentFill: Color { accent.opacity(0.18) }
    static var background: Color { dynamic(store.light.hex.0, store.dark.hex.0) }
    static var card: Color { dynamic(store.light.hex.1, store.dark.hex.1) }
    static var fill: Color { dynamic(store.light.hex.2, store.dark.hex.2) }
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
    @ViewBuilder
    func glassBackground<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }

    func themedList() -> some View {
        self.scrollContentBackground(.hidden).background(Theme.background)
    }
}

extension UIApplication {
    static func dismissKeyboard() {
        shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    func dismissesKeyboardOnTapAndScroll() -> some View {
        scrollDismissesKeyboard(.immediately)
    }

    func keyboardDoneButton() -> some View {
        scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(tr("完成")) { UIApplication.dismissKeyboard() }
                        .accessibilityIdentifier("keyboard.done")
                }
            }
    }
}

final class KeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismisser()
    private var installed = Set<ObjectIdentifier>()

    @MainActor
    func install() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where !installed.contains(ObjectIdentifier(window)) {
                let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
                tap.cancelsTouchesInView = false
                tap.delaysTouchesBegan = false
                tap.delaysTouchesEnded = false
                tap.delegate = self
                window.addGestureRecognizer(tap)
                installed.insert(ObjectIdentifier(window))
            }
        }
    }

    @objc private func tapped() {
        UIApplication.dismissKeyboard()
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let v = view {
            if v is UITextField || v is UITextView || v is UISearchBar { return false }
            view = v.superview
        }
        return true
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
