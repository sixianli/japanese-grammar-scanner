import Foundation
import UIKit
#if CLOUD_FEEDBACK
import CloudKit
#endif

/// 把用户反馈静默提交到开发者的 iCloud 公共数据库（CloudKit）。
/// 云端每隔一段时间由 GitHub Actions（.github/workflows/feedback-forward.yml）取出新反馈，连同截图转发到开发者邮箱。
///
/// 只有在发布构建打开了 iCloud 能力时才编译 CloudKit 部分（编译条件 CLOUD_FEEDBACK，
/// 见 release.yml 与 docs/feedback/SETUP.md）；否则 `isAvailable == false`，反馈页退回邮件 / 分享。
enum FeedbackSender {
    struct Payload {
        var kind: String
        var message: String
        var context: String?
        var appVersion: String
        var osVersion: String
        var device: String
        var language: String
        var images: [UIImage]
    }

    enum SendError: LocalizedError {
        case notConfigured
        case noAccount
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: tr("暂时无法在 App 内提交反馈")
            case .noAccount: tr("这台设备没有登录 iCloud，无法在 App 内直接提交")
            case .failed(let message): message
            }
        }
    }

    static var isAvailable: Bool {
        #if CLOUD_FEEDBACK
        true
        #else
        false
        #endif
    }

    static let recordType = "Feedback"

    static func send(_ payload: Payload) async throws {
        #if CLOUD_FEEDBACK
        guard let bundleID = Bundle.main.bundleIdentifier else { throw SendError.notConfigured }
        let container = CKContainer(identifier: "iCloud." + bundleID)
        let status = try await container.accountStatus()
        guard status == .available else { throw SendError.noAccount }

        let record = CKRecord(recordType: recordType)
        record["kind"] = payload.kind
        record["message"] = payload.message
        record["context"] = payload.context
        record["appVersion"] = payload.appVersion
        record["osVersion"] = payload.osVersion
        record["device"] = payload.device
        record["language"] = payload.language

        // 截图压缩后作为附件（每张最长边 1600 像素）
        var files: [URL] = []
        defer { for f in files { try? FileManager.default.removeItem(at: f) } }
        var assets: [CKAsset] = []
        for image in payload.images {
            guard let data = image.downscaled(maxSide: 1600).jpegData(compressionQuality: 0.75) else { continue }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            try data.write(to: url)
            files.append(url)
            assets.append(CKAsset(fileURL: url))
        }
        if !assets.isEmpty { record["screenshots"] = assets }

        do {
            _ = try await container.publicCloudDatabase.save(record)
        } catch {
            throw SendError.failed(error.localizedDescription)
        }
        #else
        throw SendError.notConfigured
        #endif
    }
}

private extension UIImage {
    func downscaled(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// 从当前最上层的界面弹出系统分享面板（在弹出页里再用 SwiftUI .sheet 弹分享面板，真机上可能弹不出来）
enum SharePresenter {
    @MainActor
    static func present(_ items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
              var top = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = top.view
        top.present(vc, animated: true)
    }
}
