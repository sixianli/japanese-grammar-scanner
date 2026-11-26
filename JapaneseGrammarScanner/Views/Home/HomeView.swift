import PhotosUI
import SwiftUI

struct HomeView: View {
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
                    reviewCard
                    if entitlements.showsTrialEndingReminder { trialReminder }
                    if isNewUser {
                        if let today = todayGrammar { todaySection(today) }
                        starterSection
                    } else {
                        if let last = history.scans.first { continueSection(last) }
                        recentViewedSection
                    }
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
            .safeAreaInset(edge: .top, spacing: 0) {
                searchEntry
                    .padding(.horizontal, Theme.margin)
                    .padding(.bottom, 8)
                    .background(alignment: .top) {
                        LinearGradient(stops: [.init(color: Theme.background, location: 0),
                                               .init(color: Theme.background, location: 0.7),
                                               .init(color: Theme.background.opacity(0), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea(edges: .top)
                            .allowsHitTesting(false)
                    }
            }
            .background(Theme.background)
            .navigationTitle(tr("首页"))
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

    private var searchEntry: some View {
        HStack(spacing: 10) {
            searchField
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

    private var scanEntry: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: openCamera) {
                    EntryCard(icon: "camera.viewfinder", title: tr("相机扫描"), subtitle: tr("拍下书页，再选要看的行"), highlighted: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.camera")

                PhotosPicker(selection: $photoItem, matching: .images) {
                    EntryCard(icon: "photo.on.rectangle", title: tr("从相册识别"), subtitle: tr("截图、照片都可以"), highlighted: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.photos")
            }
            .fixedSize(horizontal: false, vertical: true)

            if HomeLayout.showsSampleLink(scanCount: history.scans.count) {
                Button {
                    if let image = UIImage(named: "SamplePage") {
                        path.append(.scan(ScanImage(image: image.normalizedForOCR(), isSample: true)))
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(localized: "没有日文材料？试试示例")
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.accentText)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.sample")
            }
        }
        .padding(.top, 4)
    }

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

    private var dueItems: [GrammarPoint] {
        history.dueForReview(limit: 50) { id in
            1 + 0.25 * Double(min(history.scanCount(of: id), 8)) + (favorites.isFavorite(id) ? 0.5 : 0)
        }
        .compactMap { library.point(id: $0.id) }
    }

    @ViewBuilder
    private var reviewCard: some View {
        let items = dueItems
        if !items.isEmpty {
            ReviewRow(ids: items.map(\.id))
        }
    }

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

private struct EntryCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let highlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.accentText)
                .frame(width: 38, height: 38)
                .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(verbatim: subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(highlighted ? Theme.accent.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

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

struct ReviewRow: View {
    let ids: [String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var playStart: Date?
    @State private var hapticAt: Date?
    @State private var buzz = 0
    @State private var onScreen = false

    private static let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        NavigationLink(value: Route.review(ids[0], Array(ids.dropFirst()))) {
            HStack(spacing: 12) {
                TimelineView(.animation(paused: playStart == nil)) { context in
                    let elapsed = playStart.map { context.date.timeIntervalSince($0) } ?? .infinity
                    Text(Self.sentence(count: ReviewNudge.shownCount(target: ids.count, elapsed: elapsed)))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Theme.card)
            .overlay {
                if let playStart { SakuraDriftOverlay(start: playStart) }
            }
            .clipShape(Self.shape)
            .overlay {
                if let playStart { ReviewGlow(start: playStart, shape: Self.shape) }
            }
            .contentShape(Self.shape)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("home.review")
        .sensoryFeedback(.impact(weight: .light), trigger: buzz)
        .onAppear {
            onScreen = true
            if ReviewNudgeSchedule.shared.takeTurn() { play() }
        }
        .onDisappear {
            onScreen = false
            playStart = nil
            hapticAt = nil
        }
        .onChange(of: scenePhase) { _, phase in
            ReviewNudgeSchedule.shared.sceneChanged(to: phase)
            if phase == .active, onScreen, ReviewNudgeSchedule.shared.takeTurn() { play() }
        }
        .task(id: hapticAt) {
            guard let hapticAt else { return }
            try? await Task.sleep(for: .seconds(max(0, hapticAt.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            buzz += 1
        }
        .task(id: playStart) {
            guard let playStart else { return }
            let remaining = playStart.timeIntervalSinceNow + max(SakuraDrift.duration, ReviewNudge.glowDuration) + 0.1
            try? await Task.sleep(for: .seconds(max(0, remaining)))
            guard !Task.isCancelled else { return }
            self.playStart = nil
        }
    }

    private func play() {
        let start = Date().addingTimeInterval(SakuraDrift.appearDelay)
        let plan = ReviewNudge.plan(reduceMotion: reduceMotion)
        if plan.haptic { hapticAt = start }
        if plan.motion { playStart = start }
    }

    static func sentence(count: Int) -> AttributedString {
        let text = String.localizedStringWithFormat(tr("%lld 个语法可以复习了"), count)
        var out = AttributedString(text)
        out.swiftUI.font = Font.body.weight(.medium)
        if let first = text.firstIndex(where: \.isNumber) {
            let last = text[first...].firstIndex(where: { !$0.isNumber }) ?? text.endIndex
            if let range = out.range(of: String(text[first..<last])) {
                out[range].swiftUI.font = Font.system(size: 28, weight: .bold).monospacedDigit()
                out[range].swiftUI.foregroundColor = Theme.accentText
            }
        }
        return out
    }
}

private struct ReviewGlow: View {
    let start: Date
    let shape: RoundedRectangle

    var body: some View {
        TimelineView(.animation) { context in
            let opacity = ReviewNudge.glowOpacity(elapsed: context.date.timeIntervalSince(start))
            shape
                .strokeBorder(Theme.accent, lineWidth: 2)
                .shadow(color: Theme.accent.opacity(0.45), radius: 12)
                .opacity(opacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum HomeLayout {
    static func showsSampleLink(scanCount: Int) -> Bool { scanCount == 0 }
}
