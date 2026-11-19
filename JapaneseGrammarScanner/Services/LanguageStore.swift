import SwiftUI

/// App 内界面与讲解内容使用的语言。可以在「设置 → 语言」里单独选择，不依赖手机系统语言
/// （例如 iOS 没有缅甸语系统界面，缅甸用户只能在这里切换）。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, zhHans = "zh-Hans", zhHant = "zh-Hant", en, ko, es, vi, my

    var id: String { rawValue }

    /// 各语言用自己的文字显示名称（「跟随系统」除外，随当前界面语言翻译）
    var nativeName: String {
        switch self {
        case .system: ""
        case .zhHans: "简体中文"
        case .zhHant: "繁體中文"
        case .en: "English"
        case .ko: "한국어"
        case .es: "Español"
        case .vi: "Tiếng Việt"
        case .my: "မြန်မာဘာသာ"
        }
    }

    static let storageKey = "appLanguage"

    /// 用户选择的语言（未选择时跟随系统）。截图测试可用启动参数 -demoAppLanguage 指定。
    static var selected: AppLanguage {
        if let demo = DemoMode.appLanguage, let lang = AppLanguage(rawValue: demo) { return lang }
        return AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    /// 实际生效的语言标识：选了具体语言就用它，否则用系统为本 App 选定的本地化语言
    static var effectiveIdentifier: String {
        let s = selected
        if s != .system { return s.rawValue }
        return Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en"
    }

    /// 选了具体语言时，界面文字按这个 locale 查找翻译；跟随系统时为 nil（不覆盖）
    var locale: Locale? { self == .system ? nil : Locale(identifier: rawValue) }
}

/// 持有当前语言和对应语言的语法库。切换语言时在后台重新加载讲解内容，加载完再整体替换，界面即时更新，无需重启。
@MainActor
final class LanguageStore: ObservableObject {
    @Published private(set) var language: AppLanguage
    @Published private(set) var library: GrammarLibrary

    init() {
        // 端到端测试每次从「跟随系统」开始
        if DemoMode.e2e { UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey) }
        language = AppLanguage.selected
        library = GrammarLibrary.shared
    }

    /// 切换语言后整个界面会按新语言重建（导航标题、标签栏等系统控件只有重建才会换语言），
    /// 重建后自动重新打开设置并停在语言页，用户看到的就是「原地换了语言」
    static var reopenLanguagePage = false

    func select(_ newValue: AppLanguage) {
        guard newValue != language else { return }
        UserDefaults.standard.set(newValue.rawValue, forKey: AppLanguage.storageKey)
        Self.reopenLanguagePage = true
        language = newValue
        let content = ContentLanguage.from(identifier: AppLanguage.effectiveIdentifier)
        guard content != library.language else { return }
        Task.detached(priority: .userInitiated) {
            let reloaded = GrammarLibrary(language: content)
            await MainActor.run {
                GrammarLibrary.shared = reloaded
                self.library = reloaded
            }
        }
    }
}

/// 设置 → 语言
struct LanguagePickerView: View {
    @EnvironmentObject private var languages: LanguageStore

    var body: some View {
        List {
            Section {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        languages.select(lang)
                    } label: {
                        HStack {
                            if lang == .system {
                                Text("跟随系统")
                            } else {
                                Text(verbatim: lang.nativeName)
                            }
                            Spacer()
                            if lang == languages.language {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("界面文字和语法讲解会一起切换。")
            }
            .listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle("语言")
        .navigationBarTitleDisplayMode(.inline)
    }
}
