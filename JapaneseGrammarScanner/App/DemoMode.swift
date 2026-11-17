import Foundation

/// 用启动参数控制演示状态，供 CI 在模拟器中自动截取 App Store 截图。正常使用时不生效。
///   -demoScreen result | detail | library | favorites
///   -demoGrammar <id>   detail 页显示的语法点
enum DemoMode {
    static var screen: String? { value(for: "-demoScreen") }
    static var grammarID: String { value(for: "-demoGrammar") ?? "te-shimau" }

    private static func value(for key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
