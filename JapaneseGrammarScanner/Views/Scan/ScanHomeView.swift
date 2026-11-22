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
            .grammarChooser(cluster: $tappedCluster, library: library) { id, matched in
                path.append(.grammarMatch(id, matched ?? ""))
            }
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
                    // 框跟随画面平滑移动、淡入淡出，而不是每次识别都整体闪一下
                    .animation(.easeOut(duration: 0.3), value: camera.liveResult.boxes)
                }
                // 新画面到达前不显示（避免旧画面一闪），到达后快速淡入
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

    // MARK: - 顶部：实时识别到的语法点

    private var livePanel: some View {
        let ids = library.displayableIDs(camera.liveResult.orderedGrammarIDs)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.viewfinder")
                (ids.isEmpty ? Text(localized: "将相机对准书本上的日文") : Text(localized: "识别到 \(ids.count) 个语法点，点击高亮或下方标签查看"))
                    .font(.subheadline.weight(.medium))
                Spacer()
                if ids.isEmpty {
                    Button(tr("试试示例"), action: openSample)
                        .accessibilityIdentifier("scan.trySample")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassBackground(in: Capsule(), interactive: true)
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
                                        Text(p.displayTitle)
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
        .glassBackground(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
            .accessibilityLabel(tr("定格并精细识别"))
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

    // MARK: -

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
        // 复习页（QA 截图）：从「快要忘了」进来的样子，底部自评条、标签栏隐藏
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
