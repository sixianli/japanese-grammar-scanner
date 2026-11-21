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
                    scanEntry
                    // 有要复习的语法时，紧跟在扫描按钮下面，是首页最醒目的一块；没有就整块不显示
                    reviewCard
                    if entitlements.showsTrialEndingReminder { trialReminder }
                    if isNewUser {
                        // 新用户：入门引导
                        if let today = todayGrammar { todaySection(today) }
                        starterSection
                    } else {
                        if let last = history.scans.first { continueSection(last) }
                        recentViewedSection
                    }
                    // 反馈入口
                    Button {
                        NotificationCenter.default.post(name: .showFeedback, object: nil)
                    } label: {
                        Label(tr("遇到问题或有建议？反馈给我们"), systemImage: "envelope")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("home.feedback")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            // 搜索框 + 设置固定在顶部，页面往下滑也一直看得到；内容从它下面滑过
            .safeAreaInset(edge: .top, spacing: 0) {
                searchEntry
                    .padding(.horizontal, Theme.margin)
                    .padding(.bottom, 8)
                    .background(alignment: .top) {
                        // 顶部渐隐的背景色：滑上来的内容不会和按钮的字叠在一起看不清
                        LinearGradient(stops: [.init(color: Theme.background, location: 0),
                                               .init(color: Theme.background, location: 0.7),
                                               .init(color: Theme.background.opacity(0), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea(edges: .top)
                            .allowsHitTesting(false)
                    }
            }
            .background(Theme.background)
            // 底部标签栏已标明「首页」，这里不再显示大标题，把空间留给内容
            .navigationTitle(tr("首页"))
            // 用 inline 标题再隐藏导航栏：避免下拉时系统为大标题预留空间而让页面突然跳动
            .navigationBarTitleDisplayMode(.inline)
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
        .environment(\.replaceRoute, { route in
            if path.isEmpty { path.append(route) } else { path[path.count - 1] = route }
        })
    }

    // MARK: 搜索入口（点一下进入搜索标签并直接开始输入）

    private var searchEntry: some View {
        HStack(spacing: 10) {
            searchField
            // 设置入口：外观（主题色、背景色）、反馈等
            Button {
                NotificationCenter.default.post(name: .showSettings, object: nil)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.primary)
                    .frame(width: 46, height: 46)
                    .glassBackground(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(localized: "设置"))
            .accessibilityIdentifier("home.settings")
        }
        .padding(.top, 8)
    }

    private var searchField: some View {
        Button {
            NotificationCenter.default.post(name: .focusSearch, object: nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text(localized: "搜索语法或意思").foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.body)
            .padding(.horizontal, 16)
            .frame(height: 46)
            .contentShape(Capsule())
            .glassBackground(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(localized: "搜索语法或意思"))
        .accessibilityIdentifier("home.search")
    }

    // MARK: 扫描入口

    /// 首页唯一的主操作：一个醒目的主按钮（相机扫描）+ 两个次要按钮（相册、示例）。
    private var scanEntry: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(localized: "扫描日文，找出语法")
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text(localized: "对准书页或选一张截图，句子里的语法会被标出来。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)

            Button(action: openCamera) {
                Label(tr("相机扫描"), systemImage: "camera.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .prominentGlassButton()
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .accessibilityIdentifier("home.camera")

            HStack(spacing: 12) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(tr("从相册识别"), systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .secondaryGlassButton()
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("home.photos")
                Button {
                    if let image = UIImage(named: "SamplePage") {
                        path.append(.scan(ScanImage(image: image.normalizedForOCR(), isSample: true)))
                    }
                } label: {
                    Label(tr("试试示例"), systemImage: "book.pages")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .secondaryGlassButton()
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("home.sample")
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
                        Text(localized: "免费试用还剩 \(days) 天").font(.subheadline.weight(.semibold))
                    } else {
                        Text(localized: "免费试用已结束").font(.subheadline.weight(.semibold))
                    }
                    if let price = entitlements.lifetimeProduct?.displayPrice {
                        Text(localized: "一次性 \(price) 永久解锁，不订阅").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(localized: "一次性购买永久解锁，不订阅").font(.caption).foregroundStyle(.secondary)
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
            NavigationLink(value: Route.allScans) { SeeAllLabel() }
                .accessibilityIdentifier("seeAll.scans")
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
                        Text(localized: "识别到 \(ids.count) 个语法点").font(.body.weight(.semibold)).foregroundStyle(Color.primary)
                        HStack(spacing: 0) {
                            if unseen > 0 {
                                Text(localized: "\(unseen) 个没看过")
                            } else {
                                Text(localized: "全部看过了")
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
            .accessibilityIdentifier("home.continueScan")
        }
    }

    // MARK: 快要忘了（FSRS，没有到期的语法时整块隐藏）

    private var dueItems: [GrammarPoint] {
        // 重要性：在你扫描的材料里出现越多、或已收藏的语法，同样快忘时更优先
        history.dueForReview(limit: 50) { id in
            1 + 0.25 * Double(min(history.scanCount(of: id), 8)) + (favorites.isFavorite(id) ? 0.5 : 0)
        }
        .compactMap { library.point(id: $0.id) }
    }

    @ViewBuilder
    private var reviewCard: some View {
        let items = dueItems
        if !items.isEmpty {
            ReviewCard(items: items, lastReview: { id in history.viewRecords[id].map(HistoryStore.lastReview) })
        }
    }

    // MARK: 最近查看

    @ViewBuilder
    private var recentViewedSection: some View {
        let points = history.recentGrammarIDs.compactMap { library.point(id: $0) }
        if !points.isEmpty {
            HomeSection(title: "最近查看", trailing: points.count > 3 ? AnyView(
                NavigationLink(value: Route.recentViewed) { SeeAllLabel() }
                .accessibilityIdentifier("seeAll.recent")
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
                Text(localized: title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                if let trailing { trailing }
            }
            if let subtitle {
                Text(localized: subtitle).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
    }
}

private struct SeeAllLabel: View {
    var body: some View {
        HStack(spacing: 2) {
            Text(localized: "全部")
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
                            HStack(alignment: .center, spacing: 6) {
                                Text(p.displayTitle).font(.body.weight(.medium)).foregroundStyle(Color.primary).lineLimit(1)
                                LevelBadge(level: p.level)
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
                .accessibilityIdentifier("grammarRow")
                if i < points.count - 1 { Divider().padding(.leading, 16) }
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 完整列表页（「全部」）。
struct GrammarListPage: View {
    @EnvironmentObject private var library: GrammarLibrary
    let title: LocalizedStringKey
    let ids: [String]

    var body: some View {
        let points = ids.compactMap { library.point(id: $0) }
        List(points) { p in
            NavigationLink(value: Route.grammar(p.id)) { GrammarRow(point: p) }
                .accessibilityIdentifier("grammarRow")
        }
        .navigationTitle(title.localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 最近查看的完整列表，可清除。
struct RecentViewedPage: View {
    @EnvironmentObject private var library: GrammarLibrary
    @EnvironmentObject private var history: HistoryStore
    @State private var confirm = false

    var body: some View {
        let points = history.recentGrammarIDs.compactMap { library.point(id: $0) }
        List(points) { p in
            NavigationLink(value: Route.grammar(p.id)) { GrammarRow(point: p) }
                .accessibilityIdentifier("grammarRow")
        }
        .navigationTitle(tr("最近查看"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(tr("清除")) { confirm = true }.disabled(points.isEmpty)
            }
        }
        .confirmationDialog(tr("确定要清除吗？"), isPresented: $confirm, titleVisibility: .visible) {
            Button(tr("清除"), role: .destructive) { history.clearViewed() }
        }
    }
}

/// 全部扫描记录
struct AllScansView: View {
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
                    .accessibilityIdentifier("scanRecord")
                }
            }
            .padding()
        }
        .navigationTitle(tr("全部扫描记录"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(tr("清除")) { confirm = true }.disabled(history.scans.isEmpty)
            }
        }
        .confirmationDialog(tr("确定要清除吗？"), isPresented: $confirm, titleVisibility: .visible) {
            Button(tr("清除"), role: .destructive) { history.clearScans() }
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

/// 首页「快要忘了」卡片：浅主题色底的大卡片，标题直接写数量，列出最该复习的 3 个，下面一个「开始复习」。
/// 点某一条或「开始复习」都进入复习：依次复习，讲解页底部自评后可以直接「下一个」。
struct ReviewCard: View {
    let items: [GrammarPoint]
    let lastReview: (String) -> Date?

    private var ids: [String] { items.map(\.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.accentText, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(localized: "有 \(items.count) 个快要忘了")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Theme.accentText)
                        .accessibilityAddTraits(.isHeader)
                    Text(localized: "趁还记得，花 1 分钟复习一下")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { i, p in
                    NavigationLink(value: Route.review(p.id, ids.filter { $0 != p.id })) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .center, spacing: 6) {
                                    Text(p.displayTitle).font(.body.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(1)
                                    LevelBadge(level: p.level)
                                }
                                Text(p.meaning).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if let date = lastReview(p.id) {
                                Text(verbatim: Self.relative(date))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.review.row")
                    if i < min(items.count, 3) - 1 { Divider().padding(.leading, 14) }
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            NavigationLink(value: Route.review(ids[0], Array(ids.dropFirst()))) {
                HStack(spacing: 6) {
                    Text(localized: "开始复习")
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold))
                }
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.accentText, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.review.start")
        }
        .padding(16)
        .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1))
        .shadow(color: Theme.accent.opacity(0.15), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.review")
    }

    /// 「4 天前」「昨天」这类相对时间（按 App 内所选语言）
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = AppLanguage.selected.locale ?? .current
        f.dateTimeStyle = .named
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: now)
    }
}
