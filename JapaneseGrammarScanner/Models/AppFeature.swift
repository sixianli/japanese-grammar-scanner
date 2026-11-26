import SwiftUI

enum AppFeature: String, CaseIterable, Identifiable, Hashable {
    case scan, scanResult, detail, contrast, review, library, search, history, appearance, feedback

    var id: String { rawValue }

    static let core: [AppFeature] = [.scan, .scanResult, .detail, .contrast, .review]

    struct GuideCard {
        let title: String
        let line: String
    }

    var card: GuideCard? {
        switch self {
        case .scan: GuideCard(title: "扫描日语", line: "拍下书页或选一张截图，再点一下要看的行。")
        case .scanResult: GuideCard(title: "点橙色框", line: "橙色框里就是语法，点一下打开讲解。")
        case .detail: GuideCard(title: "看语法讲解", line: "每种用法都有讲解、接续和带注音的例句。")
        case .contrast: GuideCard(title: "相近语法", line: "点「看例句对比」，看清和相近语法的差别。")
        case .review: GuideCard(title: "到时间就复习", line: "首页出现「N 个语法可以复习了」时点一下，看完自评。")
        case .library, .search, .history, .appearance, .feedback: nil
        }
    }
}

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
