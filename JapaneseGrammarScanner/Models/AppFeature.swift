import SwiftUI

/// App 的主要功能清单 = 使用指南的目录。
///
/// 硬门槛（见 CLAUDE.md「使用引导随功能同步更新」）：
/// - App 里每个能进入的页面（Route）、每个标签页、设置里的每个入口，都要在下面的 `feature` 里归到某个功能；
///   switch 没有 default，新加一个页面却没归类，代码编译不过。
/// - 每个功能都要有指南条目（`guide`），至少两步，所有界面语言都有翻译（单元测试 GuideTests）。
/// 加了新功能 → 在这里加 case 并写好指南；改了操作方式 → 改对应步骤；删了功能 → 删掉 case。
enum AppFeature: String, CaseIterable, Identifiable, Hashable {
    case scan, scanResult, detail, contrast, review, library, search, history, appearance, feedback

    var id: String { rawValue }

    /// 核心功能（使用指南里排在前面；首次打开的引导也讲这几个）
    static let core: [AppFeature] = [.scan, .scanResult, .detail, .contrast, .review]
    static var more: [AppFeature] { allCases.filter { !core.contains($0) } }

    struct Step {
        let symbol: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
        /// 测试用：步骤文字的原文（检查翻译）
        let keys: [String]

        init(_ symbol: String, _ title: String, _ detail: String) {
            self.symbol = symbol
            self.title = LocalizedStringKey(title)
            self.detail = LocalizedStringKey(detail)
            keys = [title, detail]
        }
    }

    struct Guide {
        let symbol: String
        let title: String
        let summary: String
        let steps: [Step]
        var tip: String? = nil
    }

    var guide: Guide {
        switch self {
        case .scan:
            Guide(symbol: "camera.viewfinder", title: "扫描日语", summary: "相机取景、拍照定格、从相册选图", steps: [
                Step("viewfinder", "把相机对准书页", "在「扫描」页对准日语，文中的语法会实时用橙色框框出来，先大致看看这页有哪些语法。"),
                Step("camera.shutter.button", "按快门定格", "按下面的快门，定格这一页做更精细的识别，框得更准。"),
                Step("photo.on.rectangle", "也可以从相册选图", "截图、照片都可以：点「从相册识别」选一张，同样会识别出里面的语法。"),
            ], tip: "手边没有日语书时，在首页点「试试示例」，用内置的示例书页体验一下。")
        case .scanResult:
            Guide(symbol: "rectangle.and.text.magnifyingglass", title: "看扫描结果", summary: "点橙色框、放大原文、修正识别文字", steps: [
                Step("hand.tap", "点橙色框看讲解", "点图上的橙色框，直接打开这个语法的讲解；同一处有几个语法时，会先让你选一个。"),
                Step("list.bullet", "看文中的语法列表", "图片下方列出了这页出现的全部语法，点任意一行也能打开讲解。"),
                Step("arrow.up.left.and.arrow.down.right", "放大看原文", "双指张开或点右下角的放大按钮，全屏看原文；往下滑或双指捏合就回来。"),
                Step("pencil", "识别错了就修正", "点「手动修正文字」改一下文字，再点「重新识别」。"),
            ])
        case .detail:
            Guide(symbol: "book", title: "看语法讲解", summary: "义项跳转、例句注音、「你扫到的」", steps: [
                Step("text.viewfinder", "先看「你扫到的」", "从扫描结果进来时，页面最上面会告诉你扫到的原文对应哪个用法，点一下就跳过去。"),
                Step("list.number", "按用法跳转", "一个语法有几种用法时，顶部列出了每一种，点一下跳到对应的讲解和例句。"),
                Step("character.book.closed", "例句都有注音", "例句里的汉字都标了假名，目标语法用颜色标出来。"),
                Step("star", "收藏", "右上角的星星可以收藏，之后在「收藏」里找到。"),
            ])
        case .contrast:
            Guide(symbol: "arrow.left.arrow.right", title: "相近语法", summary: "三组对比，展开看例句", steps: [
                Step("square.stack.3d.up", "三组相近语法", "讲解页下方的「相近语法」分成三组：同一个词变来的、长得像的、意思差不多的。"),
                Step("text.alignleft", "先看一句话的差别", "每一项收起时就显示一句话的差别，扫一眼就知道区别在哪。"),
                Step("chevron.down", "展开看例句对比", "点「看例句对比」，看两句只换了语法的例句和「怎么分辨」；对方有几种形式时，每种形式各有一句。"),
                Step("arrow.right.circle", "跳到对方的讲解", "点语法名，直接打开那个语法的讲解。"),
            ])
        case .review:
            Guide(symbol: "arrow.counterclockwise", title: "复习「快要忘了」", summary: "自评记得程度，按记忆规律提醒", steps: [
                Step("house", "首页出现「快要忘了」", "看过的语法快要忘记时，首页会出现「有 N 个快要忘了」；没有要复习的就不显示。"),
                Step("play.circle", "开始复习", "点「开始复习」，或者点其中某一个，进入讲解页复习。"),
                Step("hand.thumbsup", "看完自评", "在底部选「忘了」「有点模糊」或「记得」，App 按你的记忆情况安排下次复习的时间。"),
                Step("forward", "下一个，或者先到这里", "评完可以继续下一个，也可以先回首页，剩下的下次再复习。"),
            ], tip: "只有从首页「快要忘了」进去时才会出现复习栏，平时查语法不会打扰你。")
        case .library:
            Guide(symbol: "books.vertical", title: "语法库与收藏", summary: "按等级浏览、收藏需要复习的语法", steps: [
                Step("line.3.horizontal.decrease.circle", "按等级浏览", "在「语法库」选 N5～N1，浏览这个等级的全部语法。"),
                Step("star", "收藏", "在讲解页点星星收藏；「收藏」页可以排序，向左滑动可以取消收藏。"),
            ])
        case .search:
            Guide(symbol: "magnifyingglass", title: "搜索", summary: "用日语、假名或中文意思找语法", steps: [
                Step("magnifyingglass", "输入就能找", "在「搜索」或首页顶部的搜索框里输入语法、假名或中文意思，例句里出现的也能找到。"),
                Step("clock", "最近查看", "搜索框还空着时，下面显示你最近看过的语法。"),
            ])
        case .history:
            Guide(symbol: "clock.arrow.circlepath", title: "扫描记录", summary: "回看以前扫描过的页面", steps: [
                Step("photo.stack", "最近扫描", "拍照或从相册识别过的页面会保存在首页的「最近扫描」里，点开就能再看。"),
                Step("trash", "清除记录", "不需要的扫描记录和浏览记录，可以在首页清除。"),
            ])
        case .appearance:
            Guide(symbol: "paintpalette", title: "外观与语言", summary: "主题色、背景色、界面语言", steps: [
                Step("paintpalette", "主题色与背景色", "在「设置 → 主题色与背景色」里选喜欢的颜色，深色模式也有对应的背景。"),
                Step("globe", "界面语言", "在「设置 → 语言」里切换界面和讲解的语言，切换后立即生效。"),
            ])
        case .feedback:
            Guide(symbol: "envelope", title: "反馈", summary: "讲解有误、bug 或建议", steps: [
                Step("exclamationmark.bubble", "随时告诉我们", "在「设置 → 反馈」选择类型，写下问题，可以附上截图。"),
                Step("text.bubble", "讲解页也能反馈", "讲解页最下面点「讲解有误或看不懂？告诉我们」，会自动带上正在看的语法。"),
            ])
        }
    }
}

// MARK: 每个页面入口都要归到一个功能（switch 没有 default：新加页面不归类就编译不过）

extension Route {
    var feature: AppFeature {
        switch self {
        case .grammar: .detail
        case .grammarMatch: .detail
        case .scan: .scanResult
        case .scanRecord, .allScans, .recentViewed: .history
        case .review: .review
        }
    }
}

extension SettingsPage {
    /// 设置里的入口所属的功能；隐私、条款、许可是说明性页面，不需要使用指南（nil）
    var feature: AppFeature? {
        switch self {
        case .appearance, .language: .appearance
        case .guide, .guideTopic: nil
        case .privacy, .terms, .licenses: nil
        }
    }
}

extension AppTab {
    static let all = [home, scan, library, favorites, search]

    static func feature(of tab: Int) -> AppFeature? {
        switch tab {
        case home: .history
        case scan: .scan
        case library, favorites: .library
        case search: .search
        default: nil
        }
    }
}
