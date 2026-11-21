import MessageUI
import PhotosUI
import SwiftUI
import UIKit

/// 用户反馈：文字描述 + 截图（最多 4 张），自动附上版本、系统、语言等信息。
/// 点「发送」后在后台提交到 iCloud（CloudKit），由云端自动转发到开发者邮箱，用户无需再做任何操作。
/// App 内提交不可用（没登录 iCloud 等）时，再退回写邮件 / 系统分享面板，并明确告诉用户。
struct FeedbackView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case content, bug, suggestion
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .content: "内容：讲解有误或看不懂"
            case .bug: "功能：bug 或用不了"
            case .suggestion: "体验与建议"
            }
        }
        var icon: String {
            switch self {
            case .content: "text.book.closed"
            case .bug: "ladybug"
            case .suggestion: "lightbulb"
            }
        }
        var subjectTag: String {
            switch self {
            case .bug: "Bug"
            case .content: "Content"
            case .suggestion: "Suggestion"
            }
        }
    }

    /// 从某个语法点打开时附带的上下文（如语法点 id）
    var context: String? = nil
    var initialKind: Kind = .bug

    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .bug
    @State private var message = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var showMail = false
    @State private var isSending = false
    @State private var showSent = false
    @State private var sendError: String?

    private var canSend: Bool { !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(tr("类型"), selection: $kind) {
                        ForEach(Kind.allCases) { Text(localized: $0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                .onAppear { kind = initialKind }
                .listRowBackground(Theme.card)

                Section {
                    TextEditor(text: $message)
                        .frame(minHeight: 140)
                        .overlay(alignment: .topLeading) {
                            if message.isEmpty {
                                Text(localized: "请描述遇到的问题：在哪个页面、做了什么、看到了什么。")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text(localized: "描述")
                }
                .listRowBackground(Theme.card)

                Section {
                    if !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(images.enumerated()), id: \.offset) { i, img in
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 128)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                images.remove(at: i)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, .black.opacity(0.6))
                                            }
                                            .padding(4)
                                            .accessibilityLabel(Text(localized: "删除截图"))
                                        }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                        Label(tr(images.isEmpty ? "添加截图" : "重新选择截图"), systemImage: "photo.on.rectangle")
                    }
                } header: {
                    Text(localized: "截图（可选，最多 4 张）")
                } footer: {
                    Text(localized: "会自动附上 App 版本、系统版本、设备型号和语言，方便定位问题。不会附带其他个人信息。")
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
            .keyboardDoneButton()
            .navigationTitle(tr("反馈"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button(tr("发送")) { send() }
                            .disabled(!canSend)
                    }
                }
            }
            .onChange(of: photoItems) { _, items in
                Task {
                    var loaded: [UIImage] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                            loaded.append(img)
                        }
                    }
                    images = loaded
                }
            }
            .sheet(isPresented: $showMail) {
                MailComposer(recipient: AppLinks.feedbackEmail ?? "", subject: subject, body: fullText,
                             images: images) { sent in
                    showMail = false
                    if sent { dismiss() }
                }
                .ignoresSafeArea()
            }
            .disabled(isSending)
            .alert(tr("已收到，谢谢你的反馈"), isPresented: $showSent) {
                Button(tr("好")) { dismiss() }
            } message: {
                Text(localized: "我们会尽快查看并改进。")
            }
            .alert(tr("没能直接发送"), isPresented: Binding(get: { sendError != nil }, set: { if !$0 { sendError = nil } })) {
                if AppLinks.feedbackEmail != nil, MFMailComposeViewController.canSendMail() {
                    Button(tr("用邮件发送")) { showMail = true }
                }
                Button(tr("用其他方式发送")) { SharePresenter.present([fullText] + images) }
                Button(tr("取消"), role: .cancel) {}
            } message: {
                Text(sendError ?? "")
            }
        }
    }

    private func send() {
        guard FeedbackSender.isAvailable else {
            // App 内提交还没开通：有邮箱就写邮件，否则直接用分享面板
            if AppLinks.feedbackEmail != nil, MFMailComposeViewController.canSendMail() {
                showMail = true
            } else {
                SharePresenter.present([fullText] + images)
            }
            return
        }
        isSending = true
        let payload = FeedbackSender.Payload(
            kind: kind.subjectTag,
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            context: context,
            appVersion: appVersion,
            osVersion: UIDevice.current.systemVersion,
            device: deviceModel,
            language: AppLanguage.effectiveIdentifier,
            images: images
        )
        Task {
            do {
                try await FeedbackSender.send(payload)
                isSending = false
                showSent = true
            } catch {
                isSending = false
                sendError = error.localizedDescription
            }
        }
    }

    private var subject: String {
        "[\(kind.subjectTag)] \(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "App") \(appVersion)"
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    /// 反馈正文 + 环境信息
    private var fullText: String {
        var lines = [message.trimmingCharacters(in: .whitespacesAndNewlines), "", "——"]
        lines.append("Type: \(kind.subjectTag)")
        if let context { lines.append("Context: \(context)") }
        lines.append("App: \(appVersion)")
        lines.append("iOS: \(UIDevice.current.systemVersion) · \(deviceModel)")
        lines.append("Language: \(AppLanguage.effectiveIdentifier)")
        return lines.joined(separator: "\n")
    }

    private var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}

/// 系统写邮件界面
private struct MailComposer: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let images: [UIImage]
    let onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        for (i, img) in images.enumerated() {
            if let data = img.jpegData(compressionQuality: 0.8) {
                vc.addAttachmentData(data, mimeType: "image/jpeg", fileName: "screenshot-\(i + 1).jpg")
            }
        }
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result == .sent)
        }
    }
}
