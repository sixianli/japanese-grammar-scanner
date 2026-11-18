import PhotosUI
import SwiftUI

/// 首页：扫描入口、今日语法、最近扫描、最近查看。打开 App 先来到这里，相机只在用户点击扫描后才启动。
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
                    if entitlements.showsTrialEndingReminder { trialReminder }
                    if isNewUser {
                        // 新用户：入门引导
                        starterSection
                        if let today = todayGrammar { todayCard(today) }
                    } else {
                        if let last = history.scans.first { continueCard(last) }
                        reviewSection
                        frequentSection
                        progressSection
                        recentViewedSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("首页")
            .withAppRoutes()
            .sheet(isPresented: $showPaywall) { PaywallView() }
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

    // MARK: 试用提醒（只在最后 2 天和结束后出现）

    private var trialReminder: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "hourglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 34, height: 34)
                    .background(Color.orange.opacity(0.14), in: Circle())
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
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
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

    private var isNewUser: Bool { history.scans.isEmpty && history.viewRecords.isEmpty }

    // MARK: 新用户入门

    private var starterSection: some View {
        let starters = library.points(for: .n5).filter(\.scannable).prefix(4)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "flag.fill", title: "从 N5 开始", tint: .green)
            GrammarList(points: Array(starters))
        }
    }

    // MARK: 继续上次

    private func continueCard(_ record: HistoryStore.ScanRecord) -> some View {
        let unseen = record.grammarIDs.filter { !history.learnedIDs.contains($0) }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(icon: "arrow.uturn.backward.circle.fill", title: "继续上次", tint: .blue)
                Spacer()
                if history.scans.count > 1 {
                    NavigationLink { AllScansView() } label: {
                        Text("全部扫描记录").font(.subheadline)
                    }
                }
            }
            NavigationLink(value: Route.scanRecord(record.id)) {
                HStack(spacing: 14) {
                    Group {
                        if let thumb = history.thumbnail(for: record) {
                            Image(uiImage: thumb).resizable().scaledToFill()
                        } else {
                            Color(.tertiarySystemFill)
                        }
                    }
                    .frame(width: 64, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("识别到 \(record.grammarIDs.count) 个语法点").font(.headline)
                        if unseen > 0 {
                            Text("还有 \(unseen) 个没看过").font(.subheadline).foregroundStyle(Brand.red)
                        } else {
                            Text("全部看过了").font(.subheadline).foregroundStyle(.green)
                        }
                        Text(record.date, format: .relative(presentation: .named))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 今日复习

    private var reviewSection: some View {
        // 重要性：在你扫描的材料里出现越多、或已收藏的语法，同样快忘时更优先
        let due = history.dueForReview { id in
            1 + 0.25 * Double(min(history.scanCount(of: id), 8)) + (favorites.isFavorite(id) ? 0.5 : 0)
        }
        let items = due.compactMap { item in library.point(id: item.id).map { ($0, item.retention) } }
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "brain.head.profile", title: "今日复习", tint: .orange)
            if items.isEmpty {
                EmptyHint(text: "今天没有需要复习的语法。看过的语法会按遗忘曲线，在快要忘记时提醒你复习。")
            } else {
                Text("按遗忘曲线排序：最快要忘记的排在最前面。点开回顾一遍即完成复习。")
                    .font(.footnote).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(items, id: \.0.id) { p, retention in
                        NavigationLink(value: Route.grammar(p.id)) {
                            HStack(alignment: .top) {
                                GrammarRow(point: p)
                                RetentionBadge(retention: retention).padding(.top, 4)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        if p.id != items.last?.0.id { Divider().padding(.leading, 28) }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: 常见但还没学

    @ViewBuilder
    private var frequentSection: some View {
        let items = history.frequentUnlearned().compactMap { item in library.point(id: item.id).map { ($0, item.count) } }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(icon: "sparkle.magnifyingglass", title: "常出现但还没学", tint: .pink)
                Text("你扫描的材料里经常出现、但还没看过讲解的语法。")
                    .font(.footnote).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(items, id: \.0.id) { p, count in
                        NavigationLink(value: Route.grammar(p.id)) {
                            HStack(alignment: .top) {
                                GrammarRow(point: p)
                                Text("\(count) 次扫描").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        if p.id != items.last?.0.id { Divider().padding(.leading, 28) }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: 学习进度

    private var progressSection: some View {
        let learned = history.learnedIDs
        let levels = JLPTLevel.allCases.filter { !library.points(for: $0).isEmpty }
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(icon: "chart.bar.fill", title: "学习进度", tint: .teal)
            VStack(spacing: 12) {
                ForEach(levels) { level in
                    let all = library.points(for: level)
                    let done = all.filter { learned.contains($0.id) }.count
                    HStack(spacing: 10) {
                        LevelBadge(level: level).frame(width: 34, alignment: .leading)
                        ProgressView(value: Double(done), total: Double(max(all.count, 1)))
                            .tint(level.color)
                        Text(verbatim: "\(done)/\(all.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .trailing)
                    }
                }
                Text("看过讲解的语法计为“已学”。").font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: 最近查看

    @ViewBuilder
    private var recentViewedSection: some View {
        let points = history.recentGrammarIDs.prefix(5).compactMap { library.point(id: $0) }
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(icon: "eye.fill", title: "最近查看", tint: .purple)
                    Spacer()
                    Button("清除") { confirmClear = .viewed }.font(.subheadline)
                }
                GrammarList(points: points)
            }
        }
    }
}

/// 记忆保持率标签：越低越红
private struct RetentionBadge: View {
    let retention: Double

    var body: some View {
        let pct = Int((retention * 100).rounded())
        let color: Color = retention < 0.5 ? .red : (retention < 0.75 ? .orange : .yellow)
        VStack(spacing: 2) {
            Text("记忆约 \(pct)%").font(.caption2.weight(.semibold)).foregroundStyle(color)
            ProgressView(value: retention).tint(color).frame(width: 52)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct GrammarList: View {
    let points: [GrammarPoint]

    var body: some View {
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
