import Foundation

/// 用启动参数控制演示状态，供 CI 在模拟器中自动截取 App Store 截图。正常使用时不生效。
///   -demoScreen result | detail | library | favorites
///   -demoGrammar <id>   detail 页显示的语法点
///   -demoSearch <词>    语法库搜索词
///   -demoHistory 1      预置浏览记录
enum DemoMode {
    static var screen: String? { value(for: "-demoScreen") }
    static var grammarID: String { value(for: "-demoGrammar") ?? "te-shimau" }
    /// 语法库截图时预先填入的搜索词
    static var search: String? { value(for: "-demoSearch") }
    /// 详情页截图时滚动到的位置（如 sense-0、section-notes）
    static var scrollAnchor: String? { value(for: "-demoScroll") }
    /// 预置浏览记录（让首页出现「快要忘了」「最近查看」）
    static var seedsHistory: Bool { value(for: "-demoHistory") != nil }

    private static func value(for key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
