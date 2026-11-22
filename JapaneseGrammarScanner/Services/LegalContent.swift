import SwiftUI

enum LegalContent {
    struct Section: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey
        var when: Condition = .always
    }

    enum Condition {
        case always
        case cloud
        case noCloud
        case payments

        var isActive: Bool {
            switch self {
            case .always: true
            case .cloud: FeedbackSender.isAvailable
            case .noCloud: !FeedbackSender.isAvailable
            case .payments: Features.paymentsEnabled
            }
        }
    }

    // MARK: 隐私政策

    static let privacyUpdated = "2026-11-22"
    static let privacyInventoryHash = "a390007f6007"

    static let privacyAll: [Section] = [
        Section(id: "summary", title: "一句话说明",
                body: "本 App 不需要注册账号，不包含广告或任何第三方 SDK。文字识别全部在你的设备上完成。"),
        Section(id: "camera", title: "相机与照片",
                body: "相机画面和你从相册选择的图片，只在你的设备上由 Apple Vision 识别文字，不会上传。拍照或从相册识别的图片保存在本机的「最近扫描」中，方便回看，可以随时删除。"),
        Section(id: "local", title: "收藏、浏览与复习记录",
                body: "收藏、浏览记录、复习记录（每个语法的记忆状态和下次复习时间）和设置只保存在本机，删除 App 即一并删除。"),
        Section(id: "usage-stats", title: "匿名使用统计",
                body: "为了解有多少人在用、来自哪些国家或地区、在什么时段使用、哪些语法点最常被查，App 每天会匿名上报一条使用汇总：日期、是否新安装、是否本周或本月第一次使用、当天打开次数、按小时的使用分布、查看过的语法点及其等级、App Store 所在的国家或地区、界面语言和 App 版本。不包含姓名、账号、设备编号或任何能识别你的信息，通过 Apple 的 iCloud（CloudKit）保存，只用于改进 App。可以随时在「设置 → 隐私」中关闭。",
                when: .cloud),
        Section(id: "feedback", title: "反馈",
                body: "只有当你在反馈页主动点击「发送」时，你选择的反馈类型、填写的描述、附上的截图、提交时所在的页面（例如正在看的语法），以及 App 版本、系统版本、设备型号和界面语言，才会通过 Apple 的 iCloud（CloudKit）发送给开发者。如果没能直接发送，你也可以改用邮件或其他方式发送。这些信息只用于排查问题和改进 App，不会提供给任何第三方。",
                when: .cloud),
        Section(id: "feedback-offline", title: "反馈",
                body: "在反馈页点「发送」后，会打开系统的邮件或分享面板，由你决定用哪个 App、发给谁；内容是你选择的反馈类型、填写的描述、附上的截图、所在的页面，以及 App 版本、系统版本、设备型号和界面语言。App 本身不会上传任何内容。",
                when: .noCloud),
        Section(id: "purchase", title: "购买",
                body: "购买和恢复购买由 Apple 的 App Store 处理，App 不会接触你的付款信息，只会向 Apple 查询是否已经购买。",
                when: .payments),
        Section(id: "contact", title: "联系我们",
                body: "对本隐私政策有任何疑问，可以在「设置 → 反馈」中告诉我们。"),
    ]

    static var privacySections: [Section] { privacyAll.filter(\.when.isActive) }

    // MARK: 使用条款

    static let termsUpdated = "2026-11-20"

    static var termsSections: [Section] {
        var list: [Section] = [
            Section(id: "eula", title: "许可协议", body: "本 App 的使用适用 Apple 标准最终用户许可协议（EULA）。"),
            Section(id: "content", title: "内容说明", body: "App 内的语法讲解为原创内容，仅供学习参考；文字识别结果可能有误，请以原文为准。"),
        ]
        if Features.paymentsEnabled {
            list.append(Section(id: "purchase", title: "购买",
                                body: "前 \(EntitlementStore.trialDays) 天免费使用全部功能。之后可一次性购买，永久解锁完整讲解；不是订阅，不会自动扣费。购买在同一 Apple ID 的设备间通用，可以在「设置 → 购买」中恢复。"))
        }
        return list
    }
}
