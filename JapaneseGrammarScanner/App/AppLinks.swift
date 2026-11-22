import Foundation

/// 功能开关
enum Features {
    /// 是否开启收费（试用 + 买断）。收集用户反馈阶段暂时关闭：所有内容免费开放，不显示任何付费提示。
    /// 以后重新开启时只需改为 true（付费逻辑与 App Store 商品配置都保留着）。
    static let paymentsEnabled = false
}

enum AppLinks {
    /// 接收用户反馈的邮箱（未设置时，反馈通过系统分享面板发送）
    static let feedbackEmail: String? = nil
    /// 隐私政策（docs/index.html，通过 GitHub Pages 发布）
    static let privacy = URL(string: "https://sixianli.github.io/japanese-grammar-scanner/#privacy")!
    static let support = URL(string: "https://sixianli.github.io/japanese-grammar-scanner/#support")!
    /// Apple 标准最终用户许可协议
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
