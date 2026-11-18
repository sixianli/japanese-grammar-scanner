import Foundation
import StoreKit

/// 内购与试用状态（StoreKit 2，无需服务器）。
///
/// 收费方式：
/// - `trial`：免费（价格 0）的非消耗型项目「14 天免费试用」。按 App Review Guideline 3.1.1，
///   非订阅 App 通过价格为 0 的非消耗型内购提供限时试用。试用开始时间 = 该交易的购买时间，绑定 Apple ID，重装不会重置。
/// - `lifetime`：一次性买断，永久解锁全部讲解。
@MainActor
final class EntitlementStore: ObservableObject {
    enum ProductID {
        static let trial = "jgs.trial.14day"
        static let lifetime = "jgs.unlock.lifetime"
        static let all = [trial, lifetime]
    }

    static let trialDays = 14

    enum Access: Equatable {
        /// 已买断
        case unlocked
        /// 试用中，到期时间
        case trial(until: Date)
        /// 试用已结束
        case trialExpired
        /// 还没开始试用
        case notStarted
    }

    @Published private(set) var access: Access = .notStarted
    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var isPurchasing = false
    /// 已完成第一次状态读取（避免在读取完成前误判为“未开始试用”）。
    @Published private(set) var isLoaded = false
    @Published var lastError: String?

    private var updatesTask: Task<Void, Never>?

    /// TestFlight / 沙盒环境下，若 App Store Connect 尚未配置内购商品（加载不到），临时开放全部内容，
    /// 避免测试者无法体验讲解。正式 App Store 版本不受影响。
    @Published private(set) var testFlightFallbackUnlock = false

    var hasFullAccess: Bool {
        if testFlightFallbackUnlock { return true }
        switch access {
        case .unlocked, .trial: return true
        case .trialExpired, .notStarted: return false
        }
    }

    var trialProduct: Product? { products[ProductID.trial] }
    var lifetimeProduct: Product? { products[ProductID.lifetime] }

    init() {
        if ProcessInfo.processInfo.arguments.contains("-demoUnlocked") {
            access = .unlocked
            isLoaded = true
            return
        }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let tx) = update { await tx.finish() }
                await self?.refresh()
            }
        }
        Task {
            await loadProducts()
            await refresh()
            await applyTestFlightFallbackIfNeeded()
        }
    }

    deinit { updatesTask?.cancel() }

    private func applyTestFlightFallbackIfNeeded() async {
        guard products.isEmpty, access != .unlocked else { return }
        if case .verified(let appTx)? = try? await AppTransaction.shared, appTx.environment == .sandbox {
            testFlightFallbackUnlock = true
        }
    }

    func loadProducts() async {
        do {
            let list = try await Product.products(for: ProductID.all)
            products = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 根据当前有效的交易计算访问权限。
    func refresh() async {
        guard !ProcessInfo.processInfo.arguments.contains("-demoUnlocked") else { return }
        var purchases: [String: Date] = [:]
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result, tx.revocationDate == nil else { continue }
            purchases[tx.productID] = tx.originalPurchaseDate
        }
        access = Self.access(purchases: purchases, now: Date())
        isLoaded = true
    }

    /// 纯函数，便于测试：由已购项目（及其首次购买时间）计算访问权限。
    nonisolated static func access(purchases: [String: Date], now: Date) -> Access {
        if purchases[ProductID.lifetime] != nil { return .unlocked }
        guard let start = purchases[ProductID.trial] else { return .notStarted }
        let end = Calendar.current.date(byAdding: .day, value: trialDays, to: start) ?? start.addingTimeInterval(Double(trialDays) * 86_400)
        return now < end ? .trial(until: end) : .trialExpired
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    await tx.finish()
                }
                await refresh()
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refresh()
    }

    /// 试用快结束（最后 2 天）或已结束，首页给一次温和提醒。
    var showsTrialEndingReminder: Bool {
        if testFlightFallbackUnlock { return false }
        switch access {
        case .trial: return (trialDaysLeft() ?? 99) <= 2
        case .trialExpired: return true
        default: return false
        }
    }

    /// 新手引导结束时开始试用（价格 0 的内购；用户已在引导最后一页看到试用时长与到期后的价格）。
    func startTrialIfNeeded() async {
        guard access == .notStarted, !testFlightFallbackUnlock else { return }
        if products.isEmpty { await loadProducts() }
        guard let trial = trialProduct else { return }
        await purchase(trial)
    }

    /// 试用剩余天数（向上取整）。
    func trialDaysLeft(now: Date = Date()) -> Int? {
        guard case .trial(let until) = access else { return nil }
        return max(1, Int(ceil(until.timeIntervalSince(now) / 86_400)))
    }
}
