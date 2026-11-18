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
    /// 高亮颜色按 JLPT 等级区分。
    var color: Color {
        switch self {
        case .n5: Color(red: 0.20, green: 0.70, blue: 0.40)
        case .n4: Color(red: 0.15, green: 0.55, blue: 0.95)
        case .n3: Color(red: 0.98, green: 0.60, blue: 0.10)
        case .n2: Color(red: 0.65, green: 0.35, blue: 0.90)
        case .n1: Color(red: 0.92, green: 0.25, blue: 0.30)
        }
    }
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
