import PhotosUI
import SwiftUI

struct ScanHomeView: View {
    @StateObject private var camera = CameraController()
    @State private var path: [Route] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.black.ignoresSafeArea()
                cameraLayer.ignoresSafeArea()
                VStack(spacing: 14) {
                    Spacer()
                    hintCapsule
                    controls
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .withAppRoutes()
        }
        .environment(\.pushRoute, { path.append($0) })
        .onAppear {
            applyDemoMode()
            updateCameraState()
        }
        .onDisappear { camera.stop() }
        .onChange(of: path) { _, _ in updateCameraState() }
        .onChange(of: scenePhase) { _, _ in updateCameraState() }
        .onReceive(NotificationCenter.default.publisher(for: .popToRoot)) { note in
            if note.object as? Int == AppTab.scan { path = [] }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSamplePage)) { _ in
            path = []
            openSample()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
    }

    @ViewBuilder
    private var cameraLayer: some View {
        switch camera.status {
        case .running, .idle:
            CameraPreview(session: camera.session)
                .opacity(camera.hasLiveFrame ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: camera.hasLiveFrame)
        case .denied:
            messageView(icon: "camera.fill", text: "没有相机权限。\n请在「设置」中允许访问相机，或从相册选择图片。", showSettings: true)
        case .unavailable:
            messageView(icon: "camera.badge.ellipsis", text: "此设备无法使用相机。\n可以从相册选择图片进行识别。", showSettings: false)
        }
    }

    private func messageView(icon: String, text: LocalizedStringKey, showSettings: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 44))
            Text(localized: text).multilineTextAlignment(.center)
            if showSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Button(tr("打开设置")) { UIApplication.shared.open(url) }
                    .buttonStyle(.borderedProminent)
            }
            Button(tr("试试示例书页"), action: openSample)
                .accessibilityIdentifier("scan.trySample")
                .buttonStyle(.bordered)
                .tint(.white)
        }
        .foregroundStyle(.white)
        .padding()
    }

    private var hintCapsule: some View {
        HStack(spacing: 10) {
            Text(localized: "对准书页，按快门拍下来")
                .font(.subheadline)
                .lineLimit(2)
                .accessibilityIdentifier("scan.hint")
            Button(tr("试试示例"), action: openSample)
                .accessibilityIdentifier("scan.trySample")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.white.opacity(0.18), in: Capsule())
        }
        .foregroundStyle(.white)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: Capsule())
        .padding(.horizontal)
    }

    private var controls: some View {
        HStack {
            PhotosPicker(selection: $photoItem, matching: .images) {
                controlIcon(isLoadingPhoto ? "hourglass" : "photo.on.rectangle", label: "相册")
            }
            .accessibilityIdentifier("scan.photos")
            Spacer()
            Button {
                if let image = camera.captureStill() {
                    path.append(.scan(ScanImage(image: image)))
                }
            } label: {
                ZStack {
                    Circle().fill(.white).frame(width: 68, height: 68)
                    Circle().stroke(.white, lineWidth: 4).frame(width: 80, height: 80)
                }
            }
            .disabled(camera.status != .running)
            .opacity(camera.status == .running ? 1 : 0.4)
            .accessibilityLabel(tr("拍照"))
            .accessibilityIdentifier("scan.shutter")
            Spacer()
            Button {
                camera.torchOn.toggle()
            } label: {
                controlIcon(camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill", label: "补光")
            }
            .disabled(camera.status != .running)
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 24)
    }

    private func controlIcon(_ name: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Image(systemName: name)
                .font(.title2)
                .frame(width: 52, height: 52)
                .glassBackground(in: Circle(), interactive: true)
            Text(localized: label).font(.caption)
        }
        .foregroundStyle(.white)
    }

    private func updateCameraState() {
        if path.isEmpty && scenePhase == .active && DemoMode.screen != "library" && DemoMode.screen != "favorites" {
            camera.start()
        } else {
            camera.stop()
        }
    }

    private func openSample() {
        if let image = UIImage(named: "SamplePage") {
            path.append(.scan(ScanImage(image: image.normalizedForOCR(), isSample: true)))
        }
    }

    private func applyDemoMode() {
        guard path.isEmpty else { return }
        switch DemoMode.screen {
        case "result": openSample()
        case "detail": path.append(.grammar(DemoMode.grammarID))
        case "review": path.append(.review(DemoMode.grammarID, ["okage-de", "te-shimau"]))
        default: break
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer {
            isLoadingPhoto = false
            photoItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        path.append(.scan(ScanImage(image: image.normalizedForOCR())))
    }
}

extension UIImage {
    func normalizedForOCR(maxDimension: CGFloat = 3000) -> UIImage {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        if imageOrientation == .up && scale == 1 { return self }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
