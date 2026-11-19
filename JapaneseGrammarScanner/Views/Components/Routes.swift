import SwiftUI
import UIKit

/// 导航目的地。
enum Route: Hashable {
    case grammar(String)
    case scan(ScanImage)
    /// 打开「最近扫描」中保存的一次扫描
    case scanRecord(UUID)
}

/// 要做识别的一张图片（来自相机定格或相册）。
struct ScanImage: Hashable, Identifiable {
    let id = UUID()
    let image: UIImage
    /// 从「最近扫描」打开时对应的记录（不再重复保存）
    var historyID: UUID? = nil
    /// 内置示例书页（不保存到最近扫描）
    var isSample = false

    static func == (lhs: ScanImage, rhs: ScanImage) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// 把一个页面压入当前标签的导航栈（由各标签的 NavigationStack 提供）。
/// 识别结果页点高亮后用它打开讲解，保证与「相近语法」等普通跳转使用同一套导航，
/// 不会出现新页面被旧页面盖住、看起来“跳回原来那个语法点”的问题。
private struct PushRouteKey: EnvironmentKey {
    static let defaultValue: ((Route) -> Void)? = nil
}

extension EnvironmentValues {
    var pushRoute: ((Route) -> Void)? {
        get { self[PushRouteKey.self] }
        set { self[PushRouteKey.self] = newValue }
    }
}

extension View {
    /// 统一注册所有导航目的地。
    func withAppRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .grammar(let id):
                GrammarDetailView(grammarID: id)
            case .scan(let scanImage):
                ScanResultView(scanImage: scanImage)
            case .scanRecord(let id):
                SavedScanView(recordID: id)
            }
        }
    }
}

extension JLPTLevel {
    /// 统一使用主色（不再按等级区分五种颜色）。
    var color: Color { Theme.accentText }
}

/// 从本地记录加载图片后显示识别结果
struct SavedScanView: View {
    let recordID: UUID
    @EnvironmentObject private var history: HistoryStore
    @State private var scanImage: ScanImage?

    var body: some View {
        Group {
            if let scanImage {
                ScanResultView(scanImage: scanImage)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard scanImage == nil,
                  let record = history.scans.first(where: { $0.id == recordID }),
                  let image = history.image(for: record) else { return }
            scanImage = ScanImage(image: image, historyID: record.id)
        }
    }
}
