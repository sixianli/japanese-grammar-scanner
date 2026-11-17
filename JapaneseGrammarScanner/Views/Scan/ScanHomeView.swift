import PhotosUI
import SwiftUI

/// 扫描首页：实时相机取景 + 实时高亮语法点；可以定格拍照或从相册选图做精细识别。
struct ScanHomeView: View {
    @EnvironmentObject private var library: GrammarLibrary
    @StateObject private var camera = CameraController(matcher: GrammarLibrary.shared.matcher)
    @State private var path: [Route] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var tappedCluster: HighlightCluster?
    @State private var isLoadingPhoto = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.black.ignoresSafeArea()
                cameraLayer.ignoresSafeArea()
                VStack(spacing: 0) {
                    livePanel
                    Spacer()
                    controls
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .withAppRoutes()
            .grammarChooser(cluster: $tappedCluster, library: library) { id in
                path.append(.grammar(id))
            }
        }
        .onAppear {
            updateCameraState()
            applyDemoMode()
        }
        .onDisappear { camera.stop() }
        .onChange(of: path) { _, _ in updateCameraState() }
        .onChange(of: scenePhase) { _, _ in updateCameraState() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
    }

    // MARK: - 取景

    @ViewBuilder
    private var cameraLayer: some View {
        switch camera.status {
        case .running, .idle:
            CameraPreview(session: camera.session)
                .overlay {
                    HighlightOverlay(
                        result: camera.liveResult,
                        imageSize: camera.frameSize,
                        fit: .fill,
                        library: library
                    ) { tappedCluster = $0 }
                }
        case .denied:
            messageView(icon: "camera.fill", text: "没有相机权限。\n请在「设置」中允许访问相机，或从相册选择图片。", showSettings: true)
        case .unavailable:
            messageView(icon: "camera.badge.ellipsis", text: "此设备无法使用相机。\n可以从相册选择图片进行识别。", showSettings: false)
        }
    }

    private func messageView(icon: String, text: String, showSettings: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 44))
            Text(text).multilineTextAlignment(.center)
            if showSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("打开设置") { UIApplication.shared.open(url) }
                    .buttonStyle(.borderedProminent)
            }
            Button("试试示例书页", action: openSample)
                .buttonStyle(.bordered)
                .tint(.white)
        }
        .foregroundStyle(.white)
        .padding()
    }

    // MARK: - 顶部：实时识别到的语法点

    private var livePanel: some View {
        let ids = camera.liveResult.orderedGrammarIDs
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.viewfinder")
                Text(ids.isEmpty ? "将相机对准书本上的日文" : "识别到 \(ids.count) 个语法点，点击高亮或下方标签查看")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if ids.isEmpty {
                    Button("试试示例", action: openSample)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.2), in: Capsule())
                }
            }
            if !ids.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ids, id: \.self) { id in
                            if let p = library.point(id: id) {
                                Button {
                                    path.append(.grammar(id))
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(p.title)
                                        Text(p.level.rawValue).font(.caption2.bold())
                                    }
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(p.level.color.opacity(0.9), in: Capsule())
                                    .foregroundStyle(.white)
                                }
                            }
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .environment(\.colorScheme, .dark)
        .padding(.horizontal)
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.2), value: ids)
    }

    // MARK: - 底部按钮

    private var controls: some View {
        HStack {
            PhotosPicker(selection: $photoItem, matching: .images) {
                controlIcon(isLoadingPhoto ? "hourglass" : "photo.on.rectangle", label: "相册")
            }
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
            .accessibilityLabel("定格并精细识别")
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

    private func controlIcon(_ name: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: name)
                .font(.title2)
                .frame(width: 52, height: 52)
                .background(.black.opacity(0.45), in: Circle())
            Text(label).font(.caption)
        }
        .foregroundStyle(.white)
    }

    // MARK: -

    private func updateCameraState() {
        if path.isEmpty && scenePhase == .active {
            camera.start()
        } else {
            camera.stop()
        }
    }

    private func openSample() {
        if let image = UIImage(named: "SamplePage") {
            path.append(.scan(ScanImage(image: image.normalizedForOCR())))
        }
    }

    private func applyDemoMode() {
        guard path.isEmpty else { return }
        switch DemoMode.screen {
        case "result": openSample()
        case "detail": path.append(.grammar(DemoMode.grammarID))
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
    /// 转正方向并限制最大边长，避免超大照片拖慢 OCR。
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
