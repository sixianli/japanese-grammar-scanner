import SwiftUI

/// 设置 → 使用指南：功能列表（核心功能在前），点进去是分步说明。内容来自 AppFeature.guide。
struct GuideView: View {
    /// 关闭设置面板（入门引导是全屏的，要先关掉面板再打开）
    var close: () -> Void = {}

    var body: some View {
        List {
            Section(tr("核心功能")) {
                ForEach(Array(AppFeature.core.enumerated()), id: \.element) { i, f in
                    NavigationLink(value: SettingsPage.guideTopic(f)) {
                        HStack(spacing: 12) {
                            Text(verbatim: "\(i + 1)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.accentText)
                                .frame(width: 32, height: 32)
                                .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            row(f)
                        }
                    }
                    .accessibilityIdentifier("guide.topic.\(f.rawValue)")
                }
            }
            .listRowBackground(Theme.card)
            Section(tr("更多功能")) {
                ForEach(AppFeature.more) { f in
                    NavigationLink(value: SettingsPage.guideTopic(f)) {
                        Label { row(f) } icon: { Image(systemName: f.guide.symbol).foregroundStyle(Theme.accentText) }
                    }
                    .accessibilityIdentifier("guide.topic.\(f.rawValue)")
                }
            }
            .listRowBackground(Theme.card)
            Section {
                Button(tr("再看一遍入门引导")) {
                    close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        NotificationCenter.default.post(name: .showOnboarding, object: nil)
                    }
                }
                .accessibilityIdentifier("guide.onboarding")
            }
            .listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle(tr("使用指南"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ f: AppFeature) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tr(f.guide.title)).font(.body.weight(.semibold))
            Text(tr(f.guide.summary)).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// 某个功能的分步说明
struct GuideTopicView: View {
    let feature: AppFeature

    var body: some View {
        let guide = feature.guide
        List {
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: step.symbol)
                        .font(.title2)
                        .foregroundStyle(Theme.accentText)
                        .frame(width: 52, height: 52)
                        .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localized: "第 \(i + 1) 步").font(.caption.weight(.bold)).foregroundStyle(Theme.accentText)
                        Text(localized: step.title).font(.body.weight(.semibold))
                        Text(localized: step.detail).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("guide.step")
            }
            .listRowBackground(Theme.card)
            if let tip = guide.tip {
                Section {
                    Label { Text(tr(tip)).font(.subheadline) } icon: { Image(systemName: "lightbulb").foregroundStyle(Theme.accentText) }
                }
                .listRowBackground(Theme.card)
            }
        }
        .themedList()
        .navigationTitle(tr(guide.title))
        .navigationBarTitleDisplayMode(.inline)
    }
}
