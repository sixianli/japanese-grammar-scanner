import SwiftUI

/// 设置面板：从底部弹出的整页面板（不挂在任何标签下），内部可以推入外观、语言、隐私政策等页面。
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// 切换语言时面板不关闭、导航栈不变（停在语言页），只是文字当场换成新语言
    @EnvironmentObject private var languages: LanguageStore
    @State private var path: [SettingsPage] = []

    var body: some View {
        NavigationStack(path: $path) {
            SettingsView(close: { dismiss() })
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button(tr("完成")) { dismiss() }.accessibilityIdentifier("settings.done") }
                }
                .navigationDestination(for: SettingsPage.self) { page in
                    switch page {
                    case .appearance: AppearanceView()
                    case .language: LanguagePickerView()
                    case .privacy: PrivacyView()
                    case .guide: GuideView(close: { dismiss() })
                    case .guideTopic(let feature): GuideTopicView(feature: feature)
                    case .terms: TermsView()
                    case .licenses: LicensesView()
                    }
                }
        }
    }
}

/// 设置里的子页面（同一导航栈内统一用按值跳转）
enum SettingsPage: Hashable {
    case appearance, language, privacy, terms, licenses, guide
    case guideTopic(AppFeature)
}

/// 设置：外观、语言、反馈、帮助、关于（收费开启时还有购买）。
struct SettingsView: View {
    var close: () -> Void = {}
    @EnvironmentObject private var store: EntitlementStore
    @EnvironmentObject private var languages: LanguageStore
    @State private var showPaywall = false
    @State private var feedbackKind: FeedbackView.Kind?
    var body: some View {
        List {
            if Features.paymentsEnabled {
            Section(tr("购买")) {
                HStack {
                    Text(localized: "状态")
                    Spacer()
                    statusText.foregroundStyle(.secondary)
                }
                if store.access != .unlocked {
                    Button(tr("解锁完整讲解")) { showPaywall = true }
                }
                Button(tr("恢复购买")) { Task { await store.restore() } }
                    .disabled(store.isPurchasing)
            }
            }
            Section(tr("通用")) {
                NavigationLink(value: SettingsPage.appearance) {
                    Label(tr("主题色与背景色"), systemImage: "paintpalette")
                }
                NavigationLink(value: SettingsPage.language) {
                    HStack {
                        Label(tr("语言"), systemImage: "globe")
                        Spacer()
                        if languages.language == .system {
                            Text(localized: "跟随系统").foregroundStyle(.secondary)
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
                        Label(kind.title.localized, systemImage: kind.icon)
                    }
                }
            } header: {
                Text(localized: "反馈")
            } footer: {
                Text(localized: "遇到 bug、讲解有误或有任何建议，都可以附上截图告诉我们。")
            }
            .listRowBackground(Theme.card)
            Section(tr("帮助")) {
                NavigationLink(value: SettingsPage.guide) {
                    Label(tr("使用指南"), systemImage: "book")
                }
                .accessibilityIdentifier("settings.guide")
            }
            .listRowBackground(Theme.card)
            Section(tr("关于")) {
                // 匿名统计开关和隐私政策都在「隐私」二级页里，设置首页不直接出现
                NavigationLink(tr("隐私"), value: SettingsPage.privacy)
                    .accessibilityIdentifier("settings.privacy")
                NavigationLink(tr("使用条款"), value: SettingsPage.terms)
                NavigationLink(tr("开源许可"), value: SettingsPage.licenses)
                HStack {
                    Text(localized: "版本")
                    Spacer()
                    Text(verbatim: appVersion).foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle(tr("设置"))
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
        case .unlocked: Text(localized: "已永久解锁")
        case .trial: Text(localized: "免费试用中，还剩 \(store.trialDaysLeft() ?? 0) 天")
        case .trialExpired: Text(localized: "免费试用已结束")
        case .notStarted: Text(localized: "未开始试用")
        }
    }
}

/// 隐私（二级页）：上面是匿名使用统计开关（只有真的会上报的版本才显示），下面是隐私政策全文。
/// 内容来自 LegalContent，和代码是否一致由 tools/validate_compliance.py 在 CI 中检查。
struct PrivacyView: View {
    @ObservedObject private var usage = UsageStats.shared

    var body: some View {
        List {
            if FeedbackSender.isAvailable {
                Section {
                    Toggle(isOn: $usage.isEnabled) {
                        Label(tr("匿名使用统计"), systemImage: "chart.bar")
                    }
                    .accessibilityIdentifier("settings.usageStats")
                } footer: {
                    Text(localized: "帮助我们了解有多少人在用、来自哪些地区、哪些语法最常被查，以便改进。不包含任何能识别你或你设备的信息。")
                }
                .listRowBackground(Theme.card)
            }
            LegalSections(updated: LegalContent.privacyUpdated, sections: LegalContent.privacySections)
        }
        .themedList()
        .navigationTitle(tr("隐私"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.privacyPage")
    }
}

/// 使用条款：与功能有关的条目由代码里的设置生成（见 LegalContent.termsSections）
struct TermsView: View {
    var body: some View {
        List {
            LegalSections(updated: LegalContent.termsUpdated, sections: LegalContent.termsSections)
            Section {
                Link(destination: AppLinks.terms) {
                    Label(tr("查看 Apple 标准最终用户许可协议"), systemImage: "arrow.up.right.square")
                }
            }
            .listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle(tr("使用条款"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LegalSections: View {
    let updated: String
    let sections: [LegalContent.Section]

    var body: some View {
        Section {
            ForEach(sections) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(localized: item.title).font(.headline)
                    Text(localized: item.body).font(.body).lineSpacing(4)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("legal.\(item.id)")
            }
        } header: {
            Text(localized: "最后更新：\(updated)")
        }
        .listRowBackground(Theme.card)
    }
}

/// 第三方组件致谢与许可（Apache-2.0 等要求保留署名）。列表来自 Resources/Legal/third_party.json，
/// 项目里实际用到的第三方组件是否都列上了，由 tools/validate_compliance.py 在 CI 中检查。
struct LicensesView: View {
    struct Item: Decodable, Identifiable {
        var id: String { name }
        let name: String
        let usage: String
        let license: String
        let url: String
    }

    static let items: [Item] = {
        struct File: Decodable { let components: [Item] }
        for sub in ["Legal", nil] as [String?] {
            if let url = Bundle.main.url(forResource: "third_party", withExtension: "json", subdirectory: sub),
               let data = try? Data(contentsOf: url),
               let file = try? JSONDecoder().decode(File.self, from: data) {
                return file.components
            }
        }
        assertionFailure("缺少 Resources/Legal/third_party.json")
        return []
    }()

    var body: some View {
        List {
            Section {
                Text(localized: "本 App 的语法讲解为原创内容。文字识别使用 Apple Vision 框架在设备上完成。以下第三方开源组件仅在构建阶段用于生成 App 内的静态数据或图片：")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(Self.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: item.name).font(.headline)
                    Text(tr(item.usage)).font(.subheadline)
                    Text(verbatim: item.license).font(.caption).foregroundStyle(.secondary)
                    if let url = URL(string: item.url) {
                        Link(destination: url) { Text(verbatim: item.url).font(.caption) }
                    }
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier("licenses.item")
            }
            Section {
                Text(verbatim: "Licensed under the Apache License, Version 2.0. You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0. Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an \"AS IS\" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(tr("开源许可"))
    }
}
