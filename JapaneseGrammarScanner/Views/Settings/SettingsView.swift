import SwiftUI

/// 设置：外观、反馈、帮助、关于（收费开启时还有购买）。
struct SettingsView: View {
    @EnvironmentObject private var store: EntitlementStore
    @State private var showPaywall = false

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
            Section("外观") {
                Button {
                    NotificationCenter.default.post(name: .showAppearance, object: nil)
                } label: {
                    Label("主题色与背景色", systemImage: "paintpalette")
                }
            }
            .listRowBackground(Theme.card)
            Section {
                ForEach(FeedbackView.Kind.allCases) { kind in
                    Button {
                        NotificationCenter.default.post(name: .showFeedback, object: kind)
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
            Section("帮助") {
                Button("使用引导") {
                    NotificationCenter.default.post(name: .showOnboarding, object: nil)
                }
            }
            Section("关于") {
                Link("隐私政策", destination: AppLinks.privacy)
                Link("使用条款", destination: AppLinks.terms)
                Link("支持与反馈", destination: AppLinks.support)
                NavigationLink("开源许可") { LicensesView() }
                HStack {
                    Text("版本")
                    Spacer()
                    Text(verbatim: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .themedList()
        .navigationTitle("设置")
        .sheet(isPresented: $showPaywall) { PaywallView() }
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
