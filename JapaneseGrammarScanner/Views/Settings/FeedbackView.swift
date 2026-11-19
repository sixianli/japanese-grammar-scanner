import MessageUI
import PhotosUI
import SwiftUI
import UIKit

/// 用户反馈：文字描述 + 截图（最多 4 张），自动附上版本、系统、语言等信息。
/// 设置了反馈邮箱且本机可发邮件时，直接打开写邮件界面；否则通过系统分享面板发送（邮件、微信等）。
struct FeedbackView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case bug, content, suggestion
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .bug: "功能问题 / bug"
            case .content: "讲解内容有误"
            case .suggestion: "建议"
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

    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .bug
    @State private var message = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var showMail = false
    @State private var showShare = false

    private var canSend: Bool { !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                .listRowBackground(Theme.card)

                Section {
                    TextEditor(text: $message)
                        .frame(minHeight: 140)
                        .overlay(alignment: .topLeading) {
                            if message.isEmpty {
                                Text("请描述遇到的问题：在哪个页面、做了什么、看到了什么。")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("描述")
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
                                            .accessibilityLabel(Text("删除截图"))
                                        }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                        Label(images.isEmpty ? "添加截图" : "重新选择截图", systemImage: "photo.on.rectangle")
                    }
                } header: {
                    Text("截图（可选，最多 4 张）")
                } footer: {
                    Text("会自动附上 App 版本、系统版本和语言，方便定位问题。不会附带其他个人信息。")
                }
                .listRowBackground(Theme.card)
            }
            .themedList()
            .navigationTitle("反馈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") {
                        if AppLinks.feedbackEmail != nil, MFMailComposeViewController.canSendMail() {
                            showMail = true
                        } else {
                            showShare = true
                        }
                    }
                    .disabled(!canSend)
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
            .sheet(isPresented: $showShare) {
                ShareSheet(items: [fullText] + images)
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
        lines.append("Language: \(Bundle.main.preferredLocalizations.first ?? "?")")
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

/// 系统分享面板（没有设置反馈邮箱或本机未配置邮件时使用）
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
