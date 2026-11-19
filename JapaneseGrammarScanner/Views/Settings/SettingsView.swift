import SwiftUI

/// 设置面板：从底部弹出的整页面板（不挂在任何标签下），内部可以推入外观、语言、隐私政策等页面。
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// 切换语言后重建界面时，直接回到语言页
    @State private var path: [SettingsPage] = {
        defer { LanguageStore.reopenLanguagePage = false }
        return LanguageStore.reopenLanguagePage ? [.language] : []
    }()

    var body: some View {
        NavigationStack(path: $path) {
            SettingsView(close: { dismiss() })
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                }
                .navigationDestination(for: SettingsPage.self) { page in
                    switch page {
                    case .appearance: AppearanceView()
                    case .language: LanguagePickerView()
                    case .privacy: PrivacyPolicyView()
                    case .terms: TermsView()
                    case .licenses: LicensesView()
                    }
                }
        }
    }
}

/// 设置里的子页面（同一导航栈内统一用按值跳转）
enum SettingsPage: Hashable {
    case appearance, language, privacy, terms, licenses
}

/// 设置：外观、语言、反馈、帮助、关于（收费开启时还有购买）。
struct SettingsView: View {
    var close: () -> Void = {}
    @EnvironmentObject private var store: EntitlementStore
    @EnvironmentObject private var languages: LanguageStore
    @State private var showPaywall = false
    @State private var feedbackKind: FeedbackView.Kind?
    @ObservedObject private var usage = UsageStats.shared

    var body: some View {
        List {
            if Features.paymentsEnabled {
            Section("购买") {
                HStack {
                    Text("状态")
                    Spacer()
                    statusText.foregroundStyle(.secondary)
                }
                if store.access != .unlocked {
                    Button("解锁完整讲解") { showPaywall = true }
                }
                Button("恢复购买") { Task { await store.restore() } }
                    .disabled(store.isPurchasing)
            }
            }
            Section("通用") {
                NavigationLink(value: SettingsPage.appearance) {
                    Label("主题色与背景色", systemImage: "paintpalette")
                }
                NavigationLink(value: SettingsPage.language) {
                    HStack {
                        Label("语言", systemImage: "globe")
                        Spacer()
                        if languages.language == .system {
                            Text("跟随系统").foregroundStyle(.secondary)
                        } else {
                            Text(verbatim: languages.language.nativeName).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listRowBackground(Theme.card)
            Section {
                ForEach(FeedbackView.Kind.allCases) { kind in
                    Button {
                        feedbackKind = kind
                    } label: {
                        Label(kind.title, systemImage: kind.icon)
                    }
                }
            } header: {
                Text("反馈")
            } footer: {
                Text("遇到 bug、讲解有误或有任何建议，都可以附上截图告诉我们。")
            }
            .listRowBackground(Theme.card)
            Section {
                Toggle(isOn: $usage.isEnabled) {
                    Label("匿名使用统计", systemImage: "chart.bar")
                }
                .accessibilityIdentifier("settings.usageStats")
            } header: {
                Text("隐私")
            } footer: {
                Text("帮助我们了解有多少人在用、来自哪些地区、哪些语法最常被查，以便改进。不包含任何能识别你或你设备的信息。")
            }
            .listRowBackground(Theme.card)
            Section("帮助") {
                Button("使用引导") {
                    // 引导页是全屏的，先关掉设置面板再打开
                    close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        NotificationCenter.default.post(name: .showOnboarding, object: nil)
                    }
                }
            }
            .listRowBackground(Theme.card)
            Section("关于") {
                NavigationLink("隐私政策", value: SettingsPage.privacy)
                NavigationLink("使用条款", value: SettingsPage.terms)
                NavigationLink("开源许可", value: SettingsPage.licenses)
                HStack {
                    Text("版本")
                    Spacer()
                    Text(verbatim: appVersion).foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(item: $feedbackKind) { kind in
            FeedbackView(initialKind: kind).tint(Theme.accent)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    private var statusText: Text {
        switch store.access {
        case .unlocked: Text("已永久解锁")
        case .trial: Text("免费试用中，还剩 \(store.trialDaysLeft() ?? 0) 天")
        case .trialExpired: Text("免费试用已结束")
        case .notStarted: Text("未开始试用")
        }
    }
}

/// 隐私政策（随 App 打包，离线可看，跟随所选语言）
struct PrivacyPolicyView: View {
    var body: some View {
        LegalPage(title: "隐私政策", updated: "2026-11-19", paragraphs: [
            ("一句话说明", "本 App 不需要注册账号，不包含广告或任何第三方 SDK。文字识别全部在你的设备上完成。匿名使用统计可以在设置中随时关闭。"),
            ("相机与照片", "相机画面和你从相册选择的图片，只在你的设备上由 Apple Vision 识别文字，不会上传。拍照或从相册识别的图片保存在本机的「最近扫描」中，方便回看，可以随时删除。"),
            ("收藏与浏览记录", "收藏、浏览记录和设置只保存在本机，删除 App 即一并删除。"),
            ("匿名使用统计", "为了解有多少人在用、来自哪些国家或地区、在什么时段使用、哪些语法点最常被查，App 每天会匿名上报一条使用汇总：当天打开次数、按小时的使用分布、查看过的语法点及其等级、App Store 所在的国家或地区、界面语言和 App 版本。不包含姓名、账号、设备编号或任何能识别你的信息，通过 Apple 的 iCloud（CloudKit）保存，只用于改进 App。可以随时在「设置 → 匿名使用统计」中关闭。"),
            ("反馈", "只有当你在反馈页主动点击「发送」时，你填写的描述、附上的截图，以及 App 版本、系统版本、设备型号和界面语言，才会通过 Apple 的 iCloud（CloudKit）发送给开发者。这些信息只用于排查问题和改进 App，不会用于其他用途，也不会提供给任何第三方。"),
            ("联系我们", "对本隐私政策有任何疑问，可以在「设置 → 反馈」中告诉我们。"),
        ])
    }
}

/// 使用条款
struct TermsView: View {
    var body: some View {
        LegalPage(title: "使用条款", updated: "2026-11-19", paragraphs: [
            ("许可协议", "本 App 的使用适用 Apple 标准最终用户许可协议（EULA）。"),
            ("内容说明", "App 内的语法讲解为原创内容，仅供学习参考；文字识别结果可能有误，请以原文为准。"),
        ], link: ("查看 Apple 标准最终用户许可协议", AppLinks.terms))
    }
}

private struct LegalPage: View {
    let title: LocalizedStringKey
    let updated: String
    let paragraphs: [(LocalizedStringKey, LocalizedStringKey)]
    var link: (LocalizedStringKey, URL)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("最后更新：\(updated)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.0).font(.headline)
                        Text(item.1).font(.body).lineSpacing(4)
                    }
                }
                if let link {
                    Link(destination: link.1) {
                        Label(link.0, systemImage: "arrow.up.right.square")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.margin)
        }
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 第三方组件致谢与许可（Apache-2.0 等要求保留署名）。
struct LicensesView: View {
    private struct Item: Identifiable {
        let id = UUID()
        let name: String
        let usage: LocalizedStringKey
        let license: String
        let url: String
    }

    private let items: [Item] = [
        Item(name: "SudachiPy / SudachiDict", usage: "用于离线生成例句的假名注音数据", license: "Apache License 2.0 · © Works Applications Co., Ltd.", url: "https://github.com/WorksApplications/sudachi.rs"),
        Item(name: "OpenCC", usage: "用于把讲解转换为繁体中文", license: "Apache License 2.0 · © Carbo Kuo and contributors", url: "https://github.com/BYVoid/OpenCC"),
        Item(name: "Noto Serif JP", usage: "用于绘制 App 图标", license: "SIL Open Font License 1.1 · © Google LLC / Adobe", url: "https://fonts.google.com/noto/specimen/Noto+Serif+JP"),
        Item(name: "IPA Font", usage: "用于绘制示例书页图片", license: "IPA Font License Agreement v1.0 · © IPA", url: "https://moji.or.jp/ipafont/"),
    ]

    var body: some View {
        List {
            Section {
                Text("本 App 的语法讲解为原创内容。文字识别使用 Apple Vision 框架在设备上完成。以下第三方开源组件仅在构建阶段用于生成 App 内的静态数据或图片：")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: item.name).font(.headline)
                    Text(item.usage).font(.subheadline)
                    Text(verbatim: item.license).font(.caption).foregroundStyle(.secondary)
                    if let url = URL(string: item.url) {
                        Link(destination: url) { Text(verbatim: item.url).font(.caption) }
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                Text(verbatim: "Licensed under the Apache License, Version 2.0. You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0. Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an \"AS IS\" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("开源许可")
    }
}
