import Foundation

enum DemoMode {
    static var screen: String? { value(for: "-demoScreen") }
    static var grammarID: String { value(for: "-demoGrammar") ?? "te-shimau" }
    static var search: String? { value(for: "-demoSearch") }
    static var scrollAnchor: String? { value(for: "-demoScroll") }
    static var scrollY: CGFloat? { value(for: "-demoScrollY").flatMap(Double.init).map { CGFloat($0) } }
    static var seedsHistory: Bool { value(for: "-demoHistory") != nil }
    static var e2e: Bool { e2eFresh || ProcessInfo.processInfo.arguments.contains("-e2e") }
    static var e2eFresh: Bool { ProcessInfo.processInfo.arguments.contains("-e2eFresh") }
    static var opensZoom: Bool { value(for: "-demoZoom") != nil }
    static var staysOnLineSelection: Bool { value(for: "-demoSelectStep") != nil }
    static var lines: Set<Int>? {
        value(for: "-demoLines").map { Set($0.split(separator: ",").compactMap { Int($0) }) }
    }
    static var opensContrasts: Bool { value(for: "-demoContrastOpen") != nil }
    static var appLanguage: String? { value(for: "-demoAppLanguage") }

    private static func value(for key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
