import PhotosUI
import SwiftUI

/// 首页：扫描入口、今日语法、最近扫描、最近查看。打开 App 先来到这里，相机只在用户点击扫描后才启动。
struct HomeView: View {
    /// 切换到「扫描」标签页（打开相机）。
    let openCamera: () -> Void

    @EnvironmentObject private var library: GrammarLibrary
    @EnvironmentObject private var history: HistoryStore
    @State private var path: [Route] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var confirmClear: ClearTarget?

    enum ClearTarget: Identifiable {
        case scans, viewed
        var id: Int { self == .scans ? 0 : 1 }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    scanCard
                    if let today = todayGrammar { todayCard(today) }
                    recentScansSection
                    recentViewedSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("首页")
            .withAppRoutes()
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    defer { photoItem = nil }
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        path.append(.scan(ScanImage(image: image.normalizedForOCR())))
                    }
                }
            }
            .confirmationDialog("确定要清除吗？", isPresented: Binding(get: { confirmClear != nil }, set: { if !$0 { confirmClear = nil } }), titleVisibility: .visible, presenting: confirmClear) { target in
                Button("清除", role: .destructive) {
                    if target == .scans { history.clearScans() } else { history.clearViewed() }
                }
            }
        }
    }

    // MARK: 扫描入口

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("扫描日文，找出语法").font(.title2.bold()).foregroundStyle(.white)
                Text("对准书页或选择截图，所有语法点都会被高亮出来。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Button(action: openCamera) {
                Label("相机扫描", systemImage: "camera.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Brand.red)
            }
            HStack(spacing: 12) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("从相册识别", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                Button {
                    if let image = UIImage(named: "SamplePage") {
                        path.append(.scan(ScanImage(image: image.normalizedForOCR(), isSample: true)))
                    }
                } label: {
                    Label("试试示例", systemImage: "book.pages")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Color(red: 0.93, green: 0.36, blue: 0.33), Color(red: 0.72, green: 0.16, blue: 0.24)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    // MARK: 今日语法

    /// 按日期固定选出一个可扫描的语法点，每天不同。
    private var todayGrammar: GrammarPoint? {
        let candidates = library.points.filter(\.scannable)
        guard !candidates.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return candidates[(day &* 7919) % candidates.count]
    }

    private func todayCard(_ p: GrammarPoint) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "sun.max.fill", title: "今日语法", tint: .orange)
            NavigationLink(value: Route.grammar(p.id)) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 6) {
                            Text(p.displayTitle).font(.title3.bold())
                            LevelBadge(level: p.level)
                        }
                        Text(p.meaning).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 最近扫描

    private var recentScansSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(icon: "clock.arrow.circlepath", title: "最近扫描", tint: .blue)
                Spacer()
                if !history.scans.isEmpty {
                    Button("清除") { confirmClear = .scans }.font(.subheadline)
                }
            }
            if history.scans.isEmpty {
                EmptyHint(text: "扫描过的书页会保存在这里，方便回看。")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(history.scans) { record in
                            Button {
                                if let image = history.image(for: record) {
                                    path.append(.scan(ScanImage(image: image, historyID: record.id)))
                                }
                            } label: {
                                ScanThumb(record: record, image: history.thumbnail(for: record))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: 最近查看

    private var recentViewedSection: some View {
        let points = history.recentGrammarIDs.prefix(10).compactMap { library.point(id: $0) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(icon: "eye.fill", title: "最近查看", tint: .purple)
                Spacer()
                if !points.isEmpty {
                    Button("清除") { confirmClear = .viewed }.font(.subheadline)
                }
            }
            if points.isEmpty {
                EmptyHint(text: "看过的语法讲解会出现在这里。")
            } else {
                VStack(spacing: 0) {
                    ForEach(points) { p in
                        NavigationLink(value: Route.grammar(p.id)) {
                            GrammarRow(point: p).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        if p.id != points.last?.id { Divider().padding(.leading, 28) }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

private struct SectionHeader: View {
    let icon: String
    let title: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(title).font(.title3.bold())
        }
    }
}

private struct EmptyHint: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ScanThumb: View {
    let record: HistoryStore.ScanRecord
    let image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color(.tertiarySystemFill)
                }
            }
            .frame(width: 120, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                Text(verbatim: "\(record.grammarIDs.count)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Brand.red, in: Capsule())
                    .padding(6)
            }
            Text(record.date, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
        }
    }
}
