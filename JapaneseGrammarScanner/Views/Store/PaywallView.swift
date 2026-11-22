import StoreKit
import SwiftUI

/// 付费页：开始 14 天免费试用 / 一次性买断 / 恢复购买。
/// 按审核要求清楚写明：试用时长、试用包含的内容、到期后不会自动扣费、买断价格。
struct PaywallView: View {
    @EnvironmentObject private var store: EntitlementStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    hero
                    features
                    status
                    buttons
                    footer
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text(localized: "关闭"))
                }
            }
            .alert(
                tr("购买失败"),
                isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })
            ) {
                Button(tr("好")) { store.lastError = nil }
            } message: {
                Text(store.lastError ?? "")
            }
            .onChange(of: store.access) { _, newValue in
                if newValue != .notStarted && newValue != .trialExpired { dismiss() }
            }
            .task { if store.products.isEmpty { await store.loadProducts() } }
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.book.closed.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(localized: "解锁完整讲解").font(.title.bold())
            Text(localized: "扫到不懂的语法，马上看懂。")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureRow(icon: "books.vertical.fill", tint: Theme.accent, text: "全部 N5–N1 语法点的完整讲解")
            FeatureRow(icon: "list.bullet.rectangle.portrait.fill", tint: Theme.accent, text: "按义项分段的用法、接续与例句")
            FeatureRow(icon: "person.2.wave.2.fill", tint: Theme.accent, text: "日常生活与职场的使用场景")
            FeatureRow(icon: "scroll.fill", tint: Theme.accent, text: "来源与构成、相近语法对比")
            FeatureRow(icon: "character.book.closed.fill", tint: Theme.accent, text: "例句汉字全部标注假名")
            FeatureRow(icon: "lock.shield.fill", tint: Theme.accent, text: "完全离线，无广告，无追踪")
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var status: some View {
        switch store.access {
        case .trial:
            Label {
                Text(localized: "免费试用中，还剩 \(store.trialDaysLeft() ?? 0) 天")
            } icon: {
                Image(systemName: "hourglass")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accentText)
        case .trialExpired:
            Label(tr("免费试用已结束"), systemImage: "hourglass.bottomhalf.filled")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            if store.access == .notStarted, let trial = store.trialProduct {
                Button {
                    Task { await store.purchase(trial) }
                } label: {
                    VStack(spacing: 2) {
                        Text(localized: "开始 \(EntitlementStore.trialDays) 天免费试用").font(.headline)
                        Text(localized: "免费 · 到期后不会自动扣费").font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }

            if let lifetime = store.lifetimeProduct {
                Button {
                    Task { await store.purchase(lifetime) }
                } label: {
                    VStack(spacing: 2) {
                        Text(localized: "一次性购买 \(lifetime.displayPrice)").font(.headline)
                        Text(localized: "永久解锁 · 无需订阅").font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            } else {
                ProgressView().padding()
            }

            Button(tr("恢复购买")) { Task { await store.restore() } }
                .font(.subheadline)
        }
        .disabled(store.isPurchasing)
        .overlay { if store.isPurchasing { ProgressView() } }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Text(localized: "免费试用期为 \(EntitlementStore.trialDays) 天，期间可使用全部内容。试用结束后不会自动收费；如需继续查看完整讲解，可一次性购买永久解锁。扫描识别与语法高亮始终免费。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link(tr("隐私政策"), destination: AppLinks.privacy)
                Link(tr("使用条款"), destination: AppLinks.terms)
            }
            .font(.caption)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let tint: Color
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28)
            Text(localized: text).font(.body)
            Spacer(minLength: 0)
        }
    }
}

/// 讲解页中被锁定内容的占位卡片。
struct LockedContentCard: View {
    @State private var showPaywall = false
    @EnvironmentObject private var store: EntitlementStore

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Theme.accent, in: Circle())
            Text(localized: "解锁完整讲解").font(.title3.bold())
            Text(localized: "用法、例句、使用场景、词源、相近语法对比")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showPaywall = true
            } label: {
                Group {
                    if store.access == .notStarted {
                        Text(localized: "开始 \(EntitlementStore.trialDays) 天免费试用")
                    } else {
                        Text(localized: "查看解锁方式")
                    }
                }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }
}
