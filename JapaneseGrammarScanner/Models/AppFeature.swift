import SwiftUI

/// App 的主要功能清单。使用指南只讲核心功能（Build 17 反馈 3：一页图文，不教设置类操作）。
///
/// 硬门槛（见 CLAUDE.md「使用引导随功能同步更新」）：
/// - App 里每个能进入的页面（Route）、每个标签页、设置里的每个入口，都要在下面的 `feature` 里归到某个功能；
///   switch 没有 default，新加一个页面却没归类，代码编译不过。
/// - 每个核心功能都要有指南卡片（`card`：一张插图 + 标题 + 一句话），所有界面语言都有翻译（单元测试 GuideAndLegalTests）。
/// 核心流程变了 → 改 `core` 和对应卡片、插图；非核心功能不写指南。
enum AppFeature: String, CaseIterable, Identifiable, Hashable {
    case scan, scanResult, detail, contrast, review, library, search, history, appearance, feedback

    var id: String { rawValue }

    /// 核心功能：使用指南按这个顺序讲；首次打开的引导也讲这几个
    static let core: [AppFeature] = [.scan, .scanResult, .detail, .contrast, .review]

    struct GuideCard {
        let title: String
        let line: String
    }

    /// 使用指南里的一张卡片；非核心功能没有
    var card: GuideCard? {
        switch self {
        case .scan: GuideCard(title: "扫描日语", line: "对准书页按快门，或从相册选一张截图。")
        case .scanResult: GuideCard(title: "点橙色框", line: "橙色框里就是语法，点一下打开讲解。")
        case .detail: GuideCard(title: "看语法讲解", line: "每种用法都有讲解、接续和带注音的例句。")
        case .contrast: GuideCard(title: "相近语法", line: "点「看例句对比」，看清和相近语法的差别。")
        case .review: GuideCard(title: "到时间就复习", line: "首页出现「N 个语法可以复习了」时点一下，看完自评。")
        case .library, .search, .history, .appearance, .feedback: nil
        }
    }
}

// MARK: 每个页面入口都要归到一个功能（switch 没有 default：新加页面不归类就编译不过）

extension Route {
    var feature: AppFeature {
        switch self {
        case .grammar: .detail
        case .grammarMatch: .detail
        case .scan: .scanResult
        case .scanRecord, .allScans, .recentViewed: .history
        case .review: .review
        }
    }
}

extension SettingsPage {
    /// 设置里的入口所属的功能；隐私、条款、许可是说明性页面，不需要使用指南（nil）
    var feature: AppFeature? {
        switch self {
        case .appearance, .language: .appearance
        case .guide: nil
        case .privacy, .terms, .licenses: nil
        }
    }
}

extension AppTab {
    static let all = [home, scan, library, favorites, search]

    static func feature(of tab: Int) -> AppFeature? {
        switch tab {
        case home: .history
        case scan: .scan
        case library, favorites: .library
        case search: .search
        default: nil
        }
    }
}
