import ObjectiveC
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
        let selected = AppLanguage.selected
        Bundle.setAppLanguage(selected == .system ? nil : selected.rawValue)
        language = selected
        library = GrammarLibrary.shared
    }

    /// 切换语言后整个界面会按新语言重建（导航标题、标签栏等系统控件只有重建才会换语言），
    /// 重建后自动重新打开设置并停在语言页，用户看到的就是「原地换了语言」
    static var reopenLanguagePage = false

    func select(_ newValue: AppLanguage) {
        guard newValue != language else { return }
        UserDefaults.standard.set(newValue.rawValue, forKey: AppLanguage.storageKey)
        Self.reopenLanguagePage = true
        Bundle.setAppLanguage(newValue == .system ? nil : newValue.rawValue)
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

/// 让 App 内的所有文字（SwiftUI 的 Text、导航标题、按钮等）都从所选语言里取。
/// 只改环境的 locale 不够：运行中切换语言时，SwiftUI 对普通文字仍按启动时的语言查找。
/// 新版 Xcode 把 String Catalog 编译成整包的语言表，单靠「xx.lproj 子包」只能查到带复数规则的那部分文字，
/// 所以查找时直接告诉系统要哪种语言（按语言查整包的语言表），查不到再退回 xx.lproj 子包。
private var languageBundleKey: UInt8 = 0
private var languageCodeKey: UInt8 = 0

private final class LanguageOverrideBundle: Bundle, @unchecked Sendable {
    /// 防止系统实现内部再调回来时无限递归
    private static let resolving = ThreadLocalFlag()

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let code = objc_getAssociatedObject(self, &languageCodeKey) as? String, !Self.resolving.isSet else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return Self.resolving.with { resolve(key: key, value: value, table: tableName, code: code) }
    }

    private func resolve(key: String, value: String?, table: String?, code: String) -> String {
        // 1. 按指定语言查整包的语言表
        if #available(iOS 18.0, *) {
            let viaLanguage = super.localizedString(forKey: key, value: "\u{1}", table: table,
                                                    localizations: [Locale.Language(identifier: code)])
            if viaLanguage != "\u{1}" { return viaLanguage }
        }
        // 2. 旧式的 xx.lproj 子包
        if let bundle = objc_getAssociatedObject(self, &languageBundleKey) as? Bundle {
            let viaLproj = bundle.localizedString(forKey: key, value: "\u{1}", table: table)
            if viaLproj != "\u{1}" { return viaLproj }
        }
        return super.localizedString(forKey: key, value: value, table: table)
    }
}

private final class ThreadLocalFlag: @unchecked Sendable {
    private let key = "LanguageOverrideBundle.resolving"
    var isSet: Bool { Thread.current.threadDictionary[key] != nil }
    func with<T>(_ body: () -> T) -> T {
        Thread.current.threadDictionary[key] = true
        defer { Thread.current.threadDictionary.removeObject(forKey: key) }
        return body()
    }
}

extension Bundle {
    /// 设置 App 内的界面语言；nil 表示跟随系统
    static func setAppLanguage(_ code: String?) {
        if !(Bundle.main is LanguageOverrideBundle) {
            object_setClass(Bundle.main, LanguageOverrideBundle.self)
        }
        let bundle = code
            .flatMap { Bundle.main.path(forResource: $0, ofType: "lproj") }
            .flatMap { Bundle(path: $0) }
        objc_setAssociatedObject(Bundle.main, &languageBundleKey, bundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(Bundle.main, &languageCodeKey, code, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        // 同时记为这个 App 的首选语言：下次启动时系统直接按它加载，所有文字（包括系统控件）都是所选语言
        if let code {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }
}
