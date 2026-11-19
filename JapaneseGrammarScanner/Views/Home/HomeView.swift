import PhotosUI
import SwiftUI

/// 首页：扫描入口、继续上次、快要忘了、最近查看（新用户：今日语法、从 N5 开始）。打开 App 先来到这里，相机只在用户点击扫描后才启动。
struct HomeView: View {
    /// 切换到「扫描」标签页（打开相机）。
    let openCamera: () -> Void

    @EnvironmentObject private var library: GrammarLibrary
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var entitlements: EntitlementStore
    @State private var path: [Route] = []
    @State private var showPaywall = false
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    searchEntry
                    scanEntry
                    if entitlements.showsTrialEndingReminder { trialReminder }
                    if isNewUser {
                        // 新用户：入门引导
                        if let today = todayGrammar { todaySection(today) }
                        starterSection
                    } else {
                        if let last = history.scans.first { continueSection(last) }
                        forgettingSection
                        recentViewedSection
                    }
                    // 反馈入口
                    Button {
                        NotificationCenter.default.post(name: .showFeedback, object: nil)
                    } label: {
                        Label("遇到问题或有建议？反馈给我们", systemImage: "envelope")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Theme.background)
            // 底部标签栏已标明「首页」，这里不再显示大标题，把空间留给内容
            .navigationTitle("首页")
            .toolbar(.hidden, for: .navigationBar)
            .withAppRoutes()
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .onReceive(NotificationCenter.default.publisher(for: .popToRoot)) { note in
                if note.object as? Int == AppTab.home { path = [] }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    defer { photoItem = nil }
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        path.append(.scan(ScanImage(image: image.normalizedForOCR())))
                    }
                }
            }
        }
        .environment(\.pushRoute, { path.append($0) })
    }

    // MARK: 搜索入口（点一下进入搜索标签并直接开始输入）

    private var searchEntry: some View {
        Button {
            NotificationCenter.default.post(name: .focusSearch, object: nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text("搜索语法或意思").foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.body)
            .padding(.horizontal, 16)
            .frame(height: 46)
            .contentShape(Capsule())
            .glassBackground(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .accessibilityLabel(Text("搜索语法或意思"))
    }

    // MARK: 扫描入口

    /// 首页唯一的主操作：一个醒目的主按钮（相机扫描）+ 两个次要按钮（相册、示例）。
    private var scanEntry: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("扫描日文，找出语法")
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text("对准书页或选一张截图，句子里的语法会被标出来。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)

            Button(action: openCamera) {
                Label("相机扫描", systemImage: "camera.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .prominentGlassButton()
            .controlSize(.large)
            .buttonBorderShape(.capsule)

            HStack(spacing: 12) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("从相册识别", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .secondaryGlassButton()
                .buttonBorderShape(.capsule)
                Button {
                    if let image = UIImage(named: "SamplePage") {
                        path.append(.scan(ScanImage(image: image.normalizedForOCR(), isSample: true)))
                    }
                } label: {
                    Label("试试示例", systemImage: "book.pages")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .secondaryGlassButton()
                .buttonBorderShape(.capsule)
            }
            .controlSize(.large)
        }
    }

    // MARK: 试用提醒（只在最后 2 天和结束后出现）

    private var trialReminder: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "hourglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    if let days = entitlements.trialDaysLeft() {
                        Text("免费试用还剩 \(days) 天").font(.subheadline.weight(.semibold))
                    } else {
                        Text("免费试用已结束").font(.subheadline.weight(.semibold))
                    }
                    if let price = entitlements.lifetimeProduct?.displayPrice {
                        Text("一次性 \(price) 永久解锁，不订阅").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("一次性购买永久解锁，不订阅").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: 今日语法（新用户）

    /// 按日期固定选出一个可扫描的语法点，每天不同。
    private var todayGrammar: GrammarPoint? {
        let candidates = library.points.filter(\.scannable)
        guard !candidates.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return candidates[(day &* 7919) % candidates.count]
    }

    private func todaySection(_ p: GrammarPoint) -> some View {
        HomeSection(title: "今日语法") {
            CompactGrammarList(points: [p], showsMeaning: true)
        }
    }

    private var isNewUser: Bool { history.scans.isEmpty && history.viewRecords.isEmpty }

    private var starterSection: some View {
        let starters = library.points(for: .n5).filter(\.scannable).prefix(3)
        return HomeSection(title: "从 N5 开始") {
            CompactGrammarList(points: Array(starters))
        }
    }

    // MARK: 继续上次

    private func continueSection(_ record: HistoryStore.ScanRecord) -> some View {
        let ids = library.displayableIDs(record.grammarIDs)
        let unseen = ids.filter { !history.learnedIDs.contains($0) }.count
        return HomeSection(title: "继续上次", trailing: history.scans.count > 1 ? AnyView(
            NavigationLink { AllScansView() } label: { SeeAllLabel() }
        ) : nil) {
            NavigationLink(value: Route.scanRecord(record.id)) {
                HStack(spacing: 14) {
                    Group {
                        if let thumb = history.thumbnail(for: record) {
                            Image(uiImage: thumb).resizable().scaledToFill()
                        } else {
                            Theme.fill
                        }
                    }
                    .frame(width: 44, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("识别到 \(ids.count) 个语法点").font(.body.weight(.semibold)).foregroundStyle(Color.primary)
                        HStack(spacing: 0) {
                            if unseen > 0 {
                                Text("\(unseen) 个没看过")
                            } else {
                                Text("全部看过了")
                            }
                            Text(verbatim: " · ")
                            Text(record.date, format: .relative(presentation: .named))
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 快要忘了（按遗忘曲线，没有内容时整块隐藏）

    private var forgettingItems: [GrammarPoint] {
        // 重要性：在你扫描的材料里出现越多、或已收藏的语法，同样快忘时更优先
        history.dueForReview(limit: 20) { id in
            1 + 0.25 * Double(min(history.scanCount(of: id), 8)) + (favorites.isFavorite(id) ? 0.5 : 0)
        }
        .compactMap { library.point(id: $0.id) }
    }

    @ViewBuilder
    private var forgettingSection: some View {
        let items = forgettingItems
        if !items.isEmpty {
            HomeSection(title: "快要忘了", subtitle: "这些语法你看过，按遗忘曲线快要忘了，再看一眼吧。",
                        trailing: items.count > 3 ? AnyView(
                            NavigationLink { GrammarListPage(title: "快要忘了", points: items) } label: { SeeAllLabel() }
                        ) : nil) {
                CompactGrammarList(points: Array(items.prefix(3)))
            }
        }
    }

    // MARK: 最近查看

    @ViewBuilder
    private var recentViewedSection: some View {
        let points = history.recentGrammarIDs.compactMap { library.point(id: $0) }
        if !points.isEmpty {
            HomeSection(title: "最近查看", trailing: points.count > 3 ? AnyView(
                NavigationLink { RecentViewedPage() } label: { SeeAllLabel() }
            ) : nil) {
                CompactGrammarList(points: Array(points.prefix(3)))
            }
        }
    }
}

// MARK: - 首页组件

/// 首页的一个模块：标题（+ 可选说明、右侧「全部」）+ 内容。
private struct HomeSection<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    var trailing: AnyView? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                if let trailing { trailing }
            }
            if let subtitle {
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
    }
}

private struct SeeAllLabel: View {
    var body: some View {
        HStack(spacing: 2) {
            Text("全部")
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
        }
        .font(.subheadline)
        .foregroundStyle(Theme.accentText)
    }
}

/// 紧凑的语法列表：每条一行（语法 + 右上角等级），可选显示一行意思。
struct CompactGrammarList: View {
    let points: [GrammarPoint]
    var showsMeaning = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(points.enumerated()), id: \.element.id) { i, p in
                NavigationLink(value: Route.grammar(p.id)) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .top, spacing: 3) {
                                Text(p.displayTitle).font(.body.weight(.medium)).foregroundStyle(Color.primary).lineLimit(1)
                                LevelBadge(level: p.level, small: true)
                            }
                            if showsMeaning {
                                Text(p.meaning).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < points.count - 1 { Divider().padding(.leading, 16) }
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 完整列表页（「全部」）。
private struct GrammarListPage: View {
    let title: LocalizedStringKey
    let points: [GrammarPoint]

    var body: some View {
        List(points) { p in
            NavigationLink(value: Route.grammar(p.id)) { GrammarRow(point: p) }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 最近查看的完整列表，可清除。
private struct RecentViewedPage: View {
    @EnvironmentObject private var library: GrammarLibrary
    @EnvironmentObject private var history: HistoryStore
    @State private var confirm = false

    var body: some View {
        let points = history.recentGrammarIDs.compactMap { library.point(id: $0) }
        List(points) { p in
            NavigationLink(value: Route.grammar(p.id)) { GrammarRow(point: p) }
        }
        .navigationTitle("最近查看")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("清除") { confirm = true }.disabled(points.isEmpty)
            }
        }
        .confirmationDialog("确定要清除吗？", isPresented: $confirm, titleVisibility: .visible) {
            Button("清除", role: .destructive) { history.clearViewed() }
        }
    }
}

/// 全部扫描记录
private struct AllScansView: View {
    @EnvironmentObject private var history: HistoryStore
    @State private var confirm = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 16) {
                ForEach(history.scans) { record in
                    NavigationLink(value: Route.scanRecord(record.id)) {
                        ScanThumb(record: record, image: history.thumbnail(for: record))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("全部扫描记录")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("清除") { confirm = true }.disabled(history.scans.isEmpty)
            }
        }
        .confirmationDialog("确定要清除吗？", isPresented: $confirm, titleVisibility: .visible) {
            Button("清除", role: .destructive) { history.clearScans() }
        }
    }
}

private struct ScanThumb: View {
    @EnvironmentObject private var library: GrammarLibrary
    let record: HistoryStore.ScanRecord
    let image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Theme.fill
                }
            }
            .frame(width: 120, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                Text(verbatim: "\(library.displayableIDs(record.grammarIDs).count)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.accent, in: Capsule())
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
