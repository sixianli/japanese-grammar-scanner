# 交接：Build 17 之后（2026-11-21）

> **注意：Build 14–17 的全部代码还在分支 `claude/ecstatic-ptolemy-i3xbbp`（PR #6，未合并），main 上没有。**
> 接手后先切到这个分支（`git fetch origin claude/ecstatic-ptolemy-i3xbbp && git checkout claude/ecstatic-ptolemy-i3xbbp`）再继续，
> 或者由用户决定先合并 PR #6 到 main。下文提到的文件、工作流改动都以该分支为准。

接手前先读仓库根目录的 `CLAUDE.md`（测试、使用引导、合规硬门槛、内容质量、工作方式），本文只写当前进度和需要知道的上下文。
回复用户用简体中文；网页搜索用英文查询、优先英文一手资料。

---

## 1. 当前状态

| 项目 | 状态 |
|---|---|
| 分支 | `claude/ecstatic-ptolemy-i3xbbp`（只在这个分支开发、推送） |
| PR | #6（草稿）「Build 14–17：反馈修复 + 相近语法全量（N5–N1，6 语）+ FSRS 复习 + 硬门槛」，尚未合并到 main |
| 最新已发版提交 | `160f139` |
| Build 17 | 版本 1.3，Build 17，`CLOUD_FEEDBACK=true`；App Store Connect 处理完成（VALID），内部测试 `IN_BETA_TESTING`，外部测试 `READY_FOR_BETA_SUBMISSION`（要发给外部测试员需在 ASC 提交 Beta 审核） |
| 160f139 的 CI | validate-data ✅ / build-and-test ✅（92 个单元测试 0 失败，1 个 OCR 评测按设计跳过；另按发版配置跑 GuideAndLegalTests 7 个 ✅）/ e2e ✅（64 个全过，`check_e2e_ran_all.py` 核对无漏跑）/ screenshots ✅ |

Build 17 包含的内容（详见 PR #6 描述）：Build 16 的全部反馈修复（复习流程、详情页飞行标题、语言切换就地生效、高亮框等）、FSRS 复习、相近语法 N5–N1 全量（878 个语法点 / 2374 项）+ 6 种语言翻译、隐私政策/条款/开源许可/使用指南硬门槛、CloudKit 反馈。

---

## 2. 正在进行：Build 17 用户反馈（批次未结束）

**用户还在陆续反馈这一批问题。按约定：只记录，不改；等用户说「反馈完了」再统一改。** 涉及较大界面改动要先出设计图给用户确认，再写代码。

### 反馈 1：详情页滚动后的顶部标题栏（截图 `docs/handoff/b17_fb01_detail_title.png`，语法「〜のではないか・〜んじゃない」N3）

1. 标题栏文字太小。
2. 标题栏是透明的，正文往上滑时和标题重叠，看不清标题。
3. 排版不稳，JLPT 等级标签（N1–N5）摆放位置不固定（截图里 N3 跟在第一行末尾，标题折成两行，第二行超出了标题栏）。
4. 语法标题长短不一，长的、短的都要兼容好。

相关代码（供分析，未改动）：
- `JapaneseGrammarScanner/Views/Detail/GrammarDetailView.swift`
  - iOS 26+ 走「飞行标题」`flyingHeader(_:)`：页面里的大标题透明占位，可见标题叠在上面，用 `visualEffect` 按滚动位置变换飞进导航栏；导航栏底色也是自己画的，按进度淡入（`FlyingTitleLayout.barTransform`）。截图里底色看起来没有起作用 / 不够不透明，要查。
  - iOS 26 以下走 `LegacyNavTitle`（`ToolbarItem(.principal)` 里 `.headline`、单行、`minimumScaleFactor(0.75)`）。
  - `enum FlyingTitleLayout`（同文件约 673 行）：`titleTransform` / `endScale` / `barTransform` / `topPadding` / `barHeight`。长标题飞进导航栏后折成两行、缩得过小，都和这里有关。
- 单元测试：`JapaneseGrammarScannerTests/FlyingTitleLayoutTests.swift`（改布局规则时要同步改断言、补长标题/短标题用例）。
- 端到端：`JapaneseGrammarScannerUITests/DetailLibraryFavoritesSearchTests.swift`（详情页相关）；页面顶部标记 id 是 `detail.title`。

改的时候要补的测试：长/短标题在导航栏里的字号下限、行数、等级标签位置固定；导航栏底色在标题进入后不透明（单元测试测 `FlyingTitleLayout`；e2e 至少滚动后检查标题元素可见、不被遮挡）。如果改了用户看得到的操作或界面，按 CLAUDE.md 同步更新使用指南。

#### 反馈 1 补充（2026-11-21 第二次，截图 `docs/handoff/b17_fb01b_detail_title.png`，语法「〜について」N3）

截图里滚动后标题「〜について」偏右（不在正中），N3 标签很小，标题栏下面有一条细线，标题栏看起来没有底色。用户明确的要求（原话整理）：
1. 标题放在**正中央**；无论标题多长，JLPT 等级小标签（N1–N5）都要放清楚。
2. **字号不能缩小**（现在的 `minimumScaleFactor` / 飞进导航栏时的缩放都要去掉或保证不小于正常导航栏标题字号）。
3. 标题栏用 Apple 的**毛玻璃效果，但基本不透明**（正文滚过去时看不出底下的内容）。
4. 往上滑时标题**跟手**地慢慢移到正中央（滚动多少、移动多少；往回滑时反向）。

待用户确认的细节（已在线程里问）：
- 长标题怎么放：字号不缩，较长的标题（878 个里有 78 个超过 12 个字，最长约 24 个字，例如「〜(よ)うが〜まいが／〜(よ)うと〜まいと」）在两个按钮之间一行放不下。方案 A：换成两行，标题栏跟着变高；方案 B：标题栏只放第一个写法（「／」「・」前的部分），完整标题仍在页面里。
- 等级标签放哪：标题后面（多行时跟在最后一行末尾），还是固定在标题下方居中。

另一个问题：「常考 / 不常考」标签看不到。
- 代码：`GrammarDetailView.swift` 的 `header(_:)` 里，`if let f = p.frequency, f != .low { FrequencyBadge(frequency: f) }`；`LevelBadge.swift` 的 `FrequencyBadge`：`high` 显示「常考」，`medium` 显示「考过」，`low` 不显示。没有「不常考」这个标签。
- 数据：`Resources/Grammar/frequency.json` 里「〜について」（id `ni-tsuite`）被标成 `low`，所以这一页本来就不显示。全部 878 个语法点里 high 294 / medium 389 / low 195，有 195 个都不显示标签。「〜について」是很常用的语法，标成 low 本身可疑，需要复核频率数据。
- 另外，标签只在页面顶部标题下方，往上滑之后就跟着滚走了，标题栏里没有。
- 待用户确认：要不要显示「不常考」；频率标签要不要也放进标题栏。

#### 反馈 1、4 用户已定的细节（2026-11-21）

- 长标题放不下就**换成两行**，标题栏跟着变高；字号不缩小。
- JLPT 等级标签放在**标题下方正中**（标题栏里和页面里都这样；不再贴在标题右上角）。反馈 4 的方向 C「跟在标题后面的小方块」因此不用。
- 频率标签**不放进标题栏**（空间有限），只在页面里显示。
- 频率标签（用户 08:04 改定，取代之前「加不常考」的说法）：**只保留一个标签，「常考」改名「必考」**；「考过」「不常考」都不要，不是必考的语法不显示标签。目的只是告诉用户这个语法点很重要。改之前先复核 `frequency.json` 的 `high` 名单（现在 294 / 878 个，约三分之一），确保「必考」落在真正重要的语法上；同时复核被错标成 `low` 的常用语法（如「〜について」）。点开标签时的数据来源说明（「根据公开资料整理，仅供参考」）保留。

### 反馈 4：「常考」标签和 JLPT 等级标签很丑（截图 `docs/handoff/b17_fb04_tags.png`，语法「〜ている」N5，2026-11-21）

用户原话：这两个标签很丑，不知道什么叫美就去参考别的 iOS 应用怎么做。和反馈 1（标题栏）一起出设计图。

现状（`Views/Components/LevelBadge.swift`）：
- `LevelBadge`：`caption2` 粗体（默认约 11pt；`small` 版写死 9pt），彩色字 + 同色 14% 透明度的胶囊底，贴在标题右上角当上标。字太小，Apple 人机界面指南规定 iOS 文字最小 11pt（https://developer.apple.com/design/human-interface-guidelines/typography ），9pt 的版本低于这个下限。
- `FrequencyBadge`：「常考」主色浅底胶囊 / 「考过」灰底，单独一行放在标题下方靠左；标题本身居中，两者不对齐，看起来是散落的两个小块。
- 两个标签字号、高度、圆角、颜色规则都不一样，放在一起不像一套。

参考方向（设计图里各出一版给用户选；参考的是 Apple 自带 App 的界面，属于观察，不是文档规定）：
- A. 信息行（App Store 应用详情页、Apple Music 专辑页标题下那行灰色小字的做法）：标题下居中一行普通文字「JLPT N3 · 常考」，次要文字颜色，`subheadline` 字号，不用胶囊底。最安静、最好读，长标题也不受影响。
- B. 同一套小标签并排：等级和频率做成同高、同字号（不小于 12pt）、同圆角的标签，居中放在标题下方一行；等级用颜色区分，频率用中性灰。
- C. 行内小方块（Apple Music「E」限制级标记的做法）：等级做成和标题文字等高的小圆角方块，紧跟在标题后面、和文字垂直居中对齐；频率放到下方信息行。标题栏里也用同一个小方块，保证居中时等级清楚可见。
- 倾向：页面里用 A（或 A + C 的等级方块），标题栏里用 C。最终由用户看设计图决定。
- 改的时候所有用到 `LevelBadge` / `FrequencyBadge` 的地方（语法列表行、搜索、收藏等）一起统一，不要只改详情页。

### 反馈 5：相近语法「意思差不多的」里混进了意思不同的语法（截图 `docs/handoff/b17_fb05_contrast_meaning.png`，2026-11-21）

用户原话：这不是界面问题，是内容质量问题；「〜ている」和「〜た」真的是意思差不多吗？

判断：用户说得对。`contrasts.json` 里 `te-iru` 的 meaning 组写着「都能表示『……着／……了』这类正在进行或状态持续、完成的意思」，收了 `ta-form`、`tokoro-da`、`mama-unchanged`。ている（现在的状态、正在进行）和 た（过去发生、完成）意思不同，只是中文都可能译成「了」，学习者容易用混（兄は結婚している／去年結婚した）。这违反 CLAUDE.md「meaning：意思或语法功能一样……意思相反的不收」。

范围不只这一处：
- 全部资料共 800 个 meaning 组、1597 项。按说明文字粗筛（说明里出现「都和……有关」「……或……」「这类」等笼统说法），命中 90 组、224 项，例如：`tame-ni` 组「都表示『为了』或『因为』」收了 `you-na-example`（像……）、`kara-from`；`bakari-only` 组「『只、光』或『大约』」收了 `kurai-approximately`；`de-yuumei` 收 `to-shite`；`wo-shite-iru-appearance` 收 `wa-ga-double-subject`；`mama-unchanged` 收 `te-iru`、`naide-without`。
- 这个粗筛既会误报（例如 `zenzen-nai` / `mattaku-nai` 是真近义），也会漏掉说明写得很具体、但收的语法其实不同的组。准确范围要逐组人工复核。

修法候选（待用户定）：
1. 逐组复核全部 800 个 meaning 组：意思真一样的留下；不一样的，能归到 root / look 的就移过去，不能的删掉（宁缺毋滥）。改了简中原稿后 6 种语言同步改（`tools/validate_contrasts.py` 会检查对齐）。
2. 像「ている／た」这种意思不同、但学习者确实常用混的对比，有教学价值。两个选择：(a) 按现有三组规则直接删掉；(b) 新增第四组「容易用混的」（要改 CLAUDE.md 的三组规则、App 里的组名和 6 种语言翻译、校验脚本）。需要用户决定；这个问题和三组的质量标准一起，在单独的「相近语法内容质量标准」线程里定，复核按定下来的标准做。
3. 门槛：`tools/validate_contrasts.py` 加规则，meaning 组说明里出现「有关」「……或……」「这类」这种笼统说法就报错，迫使说明写出唯一的共同意思。这只能挡住笼统的说明，挡不住「说明写得对、收错了语法」，所以复核本身仍要人工（或用模型辅助复核，会花钱，先报价问用户）。

### 反馈 6：义项编号小圆圈不够显眼（截图 `docs/handoff/b17_fb06_sense_numbers.png`，语法「か」，2026-11-21）

用户要求二选一：给编号加主题色；或者圆圈线条和数字都改成黑色。

现状：`GrammarDetailView.swift` 的 `NumberBadge`：`caption` 半粗、`.secondary` 灰色数字，22×22 圆圈，描边是 `secondary` 50% 透明度、1pt。用在义项目录（`SenseOutline`）和下面「用法」里每个义项的标题前，两处一起改。

建议：用主题色（数字 `Theme.accentText`、圆圈 `Theme.accentFill` 浅底或主题色描边），和使用指南里的编号块、各段的绿色小标题是同一套颜色。黑色的话会和旁边加粗的黑色义项名抢视线。设计图里两种都画出来给用户选。

### 反馈 7：「这里有多个语法点，请选择」弹窗里选项文字用黑色（截图 `docs/handoff/b17_fb07_chooser_color.png`，2026-11-21）

用户要求：扫描结果页点重叠的高亮块后弹出的选择框，选项文字（如「〜れる・〜られる (N4)　「れて」」）改成黑色，不用主题色。

现状：`Views/Components/GrammarChooser.swift` 用系统的 `confirmationDialog`，按钮文字颜色跟着 App 的全局主题色（tint）走，代码里没单独设颜色。
改法：在这个弹窗上把颜色设成主文字色（例如 `.tint(.primary)`）。系统弹窗不一定都认这个设置（iOS 26 上这个弹窗是气泡样式），真机上不生效的话，就改成自己画的选择框。深色模式下「黑色」应是白色（用系统主文字色，不写死黑色）。改完补一个界面测试或截图核对。

### 反馈 8：详情页文字灰色、黑色用得乱（截图 `docs/handoff/b17_fb08_text_colors.png`，相近语法卡片，2026-11-21）

用户要求：给一条清晰的规则，说明哪些字用灰、哪些用黑。

现状（`Views/Detail/GrammarDetailView.swift`、`ContrastSection.swift`）：
- 灰色有两种深浅（`.secondary`、`.tertiary`），混着用；灰色既用于小标签（「本页 · …」「接续」「怎么分辨」），也用于必须读的内容：义项目录里的接续公式、相近语法的组说明（「都来自指示词『こ・そ・あ・ど』」）、✗ 错误例句的理由、例句翻译。
- 黑色：标题、讲解、日语例句、对比要点（diff）、「怎么分辨」正文。
- 主题绿：组名、「看例句对比 / 收起」、高亮、各段图标。
- 结果是同等重要的内容有的黑有的灰，读者看不出颜色代表什么。

拟定规则（对应系统的 label / secondaryLabel / tertiaryLabel 和 tint 语义色；待用户确认，确认后写进 CLAUDE.md 或设计说明，改动时全 App 统一）：
1. **黑色（系统主文字色）= 要读懂这条语法必须读的字**：标题、讲解、日语例句、接续公式、组说明（每组的共同点）、对比要点、「怎么分辨」正文、✗ 错误理由。
2. **灰色（只用一种：`.secondary`）= 不读也不影响理解的辅助信息**：例句的中文翻译、小节标签（接续、怎么分辨）、例句上方的出处标签（「本页 · …」）、页脚提示。
3. **主题绿 = 只给能点的东西**：展开/收起、链接文字；以及例句里的语法高亮。组名（同一个词变来的 / 长得像的 / 意思差不多的）不能点，不用绿色，改成黑色粗体（或像系统「设置」分组标题那样的灰色小字），待用户选。依据：Apple 人机界面指南 Color 一节，主题色（tint）用来表示可交互的元素，不要同一个颜色既表示可点又表示不可点（https://developer.apple.com/design/human-interface-guidelines/color ）。各段标题前的绿色图标同理，要一起考虑。
4. 更浅的灰（`.tertiary`）只用于右侧箭头「›」等图标，不用于文字。
- 按这条规则要改的：义项目录接续公式 灰→黑；相近语法组说明 灰→黑；✗ 理由 灰→黑；其余基本已符合。
- 门槛：可在单元测试或脚本里检查 Detail 目录下文字不用 `.tertiary`（只允许图标），其余靠设计图对照。

### 反馈 9：相近语法例句里的虚线下划线是什么、规则是什么（截图 `docs/handoff/b17_fb09_clue_underline.png`，「いつかこんなかばんがほしいなあ」，2026-11-21）

用户问：为什么要打虚线、目的是什么、规则要说清楚。

现在的规则（代码和资料）：
- 资料 `contrasts*.json` 的例句写法里，以 `~` 开头的片段是「线索」，`RubyText.swift` 在它下面画灰色虚线（`DashedLine`，约 208 行）。用意来自 CLAUDE.md「用线索（原因、时间词、后半句）逼出本质」：标出句子里「决定该用哪个语法」的那几个词，配合下面「怎么分辨」的说明。虚线不能点。
- 4873 个对比例句里 4239 个带线索。

问题：
1. App 里没有任何地方说明虚线的意思，用户看不懂（用户本人就没看懂）。
2. 线索和「怎么分辨」经常对不上：粗查 2253 个带线索的对比项里，约 454 个的「怎么分辨」一个线索词都没提到（按字面匹配，有误差）。截图这条就是：虚线标在「いつか」，但说明讲的是「想要一个和它差不多的」，いつか 并不是分辨 こんな / この 的关键。
3. 虚线是灰色细点线，和注音、翻译挤在一起，不显眼。

修法候选（待用户定）：
- A. 保留，但补规则：线索必须是「怎么分辨」里点名的词（`tools/validate_contrasts.py` 加检查：每个带线索的例句，线索词要出现在该项的 explain 里），选不出真正起决定作用的词就不标；并在「怎么分辨」里把线索词用同样的虚线样式标出来，让两边对应起来，或首次出现时给一句说明。
- B. 去掉虚线，只靠「怎么分辨」的文字说明。
- **用户已同意 A（2026-11-21）**：保留虚线；虚线标的词必须是「怎么分辨」里点名的那个起决定作用的词，找不出就不标；「怎么分辨」正文里用同样的虚线样式标出这个词，两边对应；`tools/validate_contrasts.py` 自动检查线索词出现在该项的 explain 里。资料复核和相近语法内容质量标准一起做。

### 反馈 2：CloudKit 后台下载反馈截图报错（2026-11-21）

现象：Build 17（1.3 (17)，iPhone15,2，iOS 27.2.1）在 App 里提交「体验与建议」反馈，CloudKit Console → Production → Public Database → Feedback 能看到记录，`screenshots`（Asset 列表）显示 `Binary file (922.05KB)`，但点下载按钮打开的 `cvws.icloud-content.com/...` 页面只返回 `Internal Server Error`。

已排查：
- 上传这一侧看不出问题。`JapaneseGrammarScanner/Services/FeedbackSender.swift` 先把 JPEG 写到临时目录，再 `await container.publicCloudDatabase.save(record)`，临时文件在 `defer` 里删除，也就是保存完成之后才删。CloudKit 先传完附件才保存记录，记录里能看到 922KB 的大小，说明附件已经存进服务器。
- 时间上吻合的改动：提交 `697c727` 把 `cloudkit/schema.ckdb` 里 Feedback、UsageDay 的 `GRANT READ TO "_world"` 去掉了（只给提交者本人读写）。之前的 CloudKit 反馈验证都发生在这次收紧之前。
- Apple 开发者论坛没有找到「控制台下载附件报 Internal Server Error」的确定答案，所以还不能断定是控制台自身的故障。

推测（未核实）：控制台以开发者身份能列出记录字段，但下载附件时文件服务器按「当前查看的 iCloud 账号对这条记录有没有读取权限」放行；开发者账号不是这条记录的创建者，又没有 `_world` 读取权限，于是下载失败（服务器给的是 500 而不是 403）。如果成立，影响是：开发者看不到任何用户反馈里的截图，只能看到文字。

验证结果（2026-11-21）：用户在控制台用「Act As iCloud Account」登录提交这条反馈的 Apple ID 后，查询 Feedback 直接报 `User does not have READ access`。也就是说任何 iCloud 账号都没有 Feedback 的读取权限，原因基本确认是权限设置，不是上传或控制台故障。开发者因此看不到任何用户的截图，修复优先级高。

原先的验证办法（已做）：
1. 在 Records 页左下角点「Act As iCloud Account...」，登录提交这条反馈时 iPhone 上用的 Apple ID（也就是记录的创建者），再查询 Feedback、下载截图。能下载 → 推测成立；仍然报错 → 不是权限问题，改为提交 Apple Feedback（附上记录名和时间）。
2. 也可以在 Development 环境用开发版提交一条带截图的反馈，对照下载结果。

用户的决定（2026-11-21）：**Feedback 和 UsageDay 都恢复成所有人可读（`GRANT READ TO "_world"`）**，让开发者在 CloudKit 后台直接看到文字和截图、读到使用统计，不需要每次用「Act As iCloud Account」登录。用户已知道风险：越狱后往 App 里注入代码的人能读到全部反馈，用户表示不考虑这种情况。之前提过的「自定义开发者角色」方案，用户不想多做一步，**不采用，不要再提**。等用户说「反馈完了」再和其它反馈一起改。

要一起改的地方：
1. `cloudkit/schema.ckdb`：Feedback、UsageDay 各加回 `GRANT READ TO "_world"`（保留 `GRANT WRITE TO "_creator"`、`GRANT CREATE TO "_icloud"`）。写入权限仍然不对 `_world` 开放。
2. `tools/validate_compliance.py` 约 214–218 行：现在的规则拦截对 `_world` 开放任何权限。改成只拦 `_world` 的 WRITE / CREATE，允许 READ；并要求 Feedback、UsageDay 必须有 `_world` READ（防止以后又被收紧、开发者再次看不到截图）。按 CLAUDE.md，旧规则对应的测试/断言一起改。
3. `docs/feedback/SETUP.md` 第 85 行「不对所有人（`_world`）开放」的说明，以及本文 §5 同样的说法，改成新设定。
4. 隐私政策（`LegalContent.swift` 的 feedback 段）写的是「发送给开发者……不会提供给任何第三方」，放开读取后仍成立，按用户意见可不改；改的时候再核对一次 `validate_compliance.py` 是否要求更新 `privacyUpdated` / `privacyInventoryHash`。
5. 部署：schema 改动推上 PR 后由 `cloudkit-schema.yml` 自动导入 Development；先在 Development 用开发版提交一条带截图的反馈，确认后台（不用 Act As）能直接下载截图、能查询 UsageDay；然后在 CloudKit Console 把 schema 部署到 Production（不可撤销的生产变更，部署前问用户）。不涉及 App 代码，不需要新 Build。

### 反馈 3：使用指南文字太多、入口太多（截图 `docs/handoff/b17_fb03_guide.png`，2026-11-21）

用户原话要点：
1. 指南里文字太多，用户读着是负担。每个功能用图文并茂的方式展示，能用图讲清楚的就用图。
2. 不要在使用指南里搞这么多入口。现在是一个列表：「核心功能」5 个、「更多功能」5 个（语法库与收藏、搜索、扫描记录、外观与语言、反馈），每个再点进去看分步文字，加上「再看一遍入门引导」，一共 11 个入口。
3. 系统设置类的内容（外观与语言、反馈等）不用教，用户不是傻子。只把核心功能怎么用讲清楚。

相关代码（未改动）：
- `JapaneseGrammarScanner/Views/Settings/GuideView.swift`：目录列表 + 每个功能的分步说明页（内容来自 `AppFeature.guide`）。
- `JapaneseGrammarScanner/Models/AppFeature.swift`：功能清单，`core` = 扫描、看扫描结果、看语法讲解、相近语法、复习；其余归 `more`。
- `JapaneseGrammarScanner/Views/Onboarding/OnboardingView.swift`：首次打开的入门引导，和指南内容有重叠，改的时候考虑合并或共用图片。
- 单元测试 `JapaneseGrammarScannerTests/GuideAndLegalTests.swift`（`testEveryFeatureHasGuide`、`testGuideIsTranslatedIntoEveryLanguage`、`testEveryTabBelongsToAFeature`）。

要注意的冲突：`CLAUDE.md`「使用引导随功能同步更新」第 4 条要求 `AppFeature` 里**每一项**都有指南条目，测试也按这条把关。按用户这次的意见，非核心功能（外观与语言、反馈，可能还有搜索、扫描记录、语法库）不再写指南，所以改的时候要同步改 CLAUDE.md 这条规则和对应测试（例如改成「每个核心功能必须有图文指南、每张图都存在且有全部语言的说明」），并先和用户确认哪些算核心功能。

改法方向（较大界面改动，按约定先出设计图给用户确认再写代码）：
- 一个入口：使用指南只有一页，按核心流程（扫描 → 看结果 → 看讲解 → 相近语法 → 复习）往下排或左右翻页，不再是两级列表。
- 每一步以一张带标注的真实界面截图为主，配一句话说明，去掉长段文字。截图可以由 CI 的 `screenshots` 任务自动生成（已有截图流程），保证界面改了图也跟着更新。
- 删掉外观与语言、反馈这类设置说明。
- 文字仍要翻译成全部界面语言（`tools/check_strings.py` 把关）；如果图里带文字，要按语言分别截图。

---

## 3. 待用户确认 / 后续

1. **iCloud 反馈验证**：用户在 TestFlight 装 Build 17 后提交一条反馈，然后到 CloudKit Console → **Production** → Records → Feedback 确认能看到。这是验证权限收紧后（见 §5）开发者本人仍能读到反馈。
2. **缅甸语翻译**：建议找母语者审一遍相近语法的缅甸语翻译（`Resources/Grammar/contrasts/contrasts_my.json`）。有一部分把「ます形 / て形」写成 `ます ပုံစံ / て ပုံစံ`，和其它部分术语不统一。术语表：被动=ခံရပုံစံ、尊敬语=ရိုသေစကား、谦让语=နှိမ့်ချစကား、使役=ခိုင်းစေပုံစံ、可能形=နိုင်ပုံစံ。
3. PR #6 还是草稿，是否合并到 main 由用户决定。

---

## 4. CI 与发版流程（务必遵守 CLAUDE.md：同一提交 e2e 全绿才能发版）

### CI：`.github/workflows/ios.yml`（push 到 main / pull_request / 手动）
- 任务：`validate-data`、`build-and-test`、`e2e-plan`、`e2e-shard-1`…`e2e-shard-4`、`e2e`、`screenshots`。端到端测试（e2e）按测试类分成 4 组在 4 台机器上同时跑，分组写在 `tools/e2e_shards.py` 的 `SHARDS` 里；新加的测试类没分组时 `e2e-plan` 会失败并提示。`e2e` 是汇总任务（发版门槛认的就是这个名字）：4 组都通过、并且合并后的日志里每个用例都有通过记录才算通过。`screenshots` 等 4 组跑完才开始，因为免费账号最多同时跑 5 个 macOS 任务。
- 并发组 `${{ github.workflow }}-${{ github.ref }}`，新提交会取消同一 PR 上正在跑的 CI。
- 提交信息带 `[skip ci]` 不触发 CI（只改文档/资料时可用，但**发版用的提交必须有完整的绿色 CI**）。
- e2e 稳定性措施：模拟器启动后 sleep 30 秒；先跑一个预热用例（`SearchTests/testNoResults`，结果忽略）；汇总任务用 `tools/check_e2e_ran_all.py` 对 4 组合并后的日志核对 UITests 里声明的每个测试都出现 `passed`（模拟器头几分钟会出现启动超时、测试进程崩溃导致用例被静默跳过）。
- `build-and-test` 里另有一步按发版配置（`CLOUD_FEEDBACK`）编译并跑 `GuideAndLegalTests`，因为 iCloud 反馈代码只在这个编译条件下编译。

### 发版：`.github/workflows/release.yml`（手动触发，`ref` 选本分支，输入 `version`）
- 门槛：`tools/require_ci_green.py` 检查该提交的 validate-data / build-and-test / e2e 全部成功，否则拒绝。
- **Build 号 = 这个工作流的 `run_number`**（Build 17 = 第 17 次运行；dry run 也会占号）。下一次发版会是 Build 18。
- `CLOUD_FEEDBACK` 读仓库变量（当前为 `true`），打开时会检查归档里有 iCloud 权限，否则停止上传。
- 发版前要把单元测试和 e2e 的结果告诉用户。

### 确认 TestFlight 可测：`.github/workflows/testflight.yml`
- 手动触发，输入 `version`（如 1.3）、`build`（如 17）。脚本 `tools/testflight_status.py` 用 ASC API 等到构建 `VALID`，补出口合规，加入内部测试群组，打印 TestFlight 状态。
- 加入群组返回 HTTP 422 一般是已经自动加入了，看最后的 `internalBuildState` 是否为 `IN_BETA_TESTING`。

### 其它坑
- `workflow_dispatch` 只对 main 上已存在的工作流文件可用（否则 404）。`cloudkit-schema.yml` 不在 main 上，所以加了 `pull_request` 触发（`cloudkit/schema.ckdb` 或该工作流文件变动时自动导入开发环境）。
- 本地（Linux 容器）跑不了 Xcode，以 CI 结果为准；Python 校验脚本可以本地跑：
  `python3 tools/validate_grammar.py && python3 tools/validate_contrasts.py && python3 tools/validate_compliance.py && python3 tools/check_strings.py`

---

## 5. CloudKit 反馈（已配置完成）

- 说明文档：`docs/feedback/SETUP.md`。
- Schema：`cloudkit/schema.ckdb`，已由用户部署到 Production。Feedback、UsageDay 只给 `_creator` 写、`_icloud` 创建，**对 `_world` 开放读取**（Build 17 反馈 2，用户决定，便于开发者在后台直接看截图）。`tools/validate_compliance.py` 要求这两类必须 `_world` 可读、任何记录不能对 `_world` 开放写入或创建。
- GitHub Secrets 里有 CloudKit 管理令牌（用于 `cktool` 导入 schema）和 ASC API Key（`ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8`）。变量：`APPLE_TEAM_ID`、`BUNDLE_ID`、`CLOUD_FEEDBACK=true`。
- 「把反馈转发到邮箱」（SETUP.md 第 3、4 步，需要 Server-to-Server Key）**用户已同意不启用**：避免让 GitHub 读到用户数据。不要再提议启用，除非用户主动要求。
- 令牌、密钥只放 GitHub Secrets，不要让用户贴到聊天里。

---

## 6. 内容资料备忘

- 相近语法：`JapaneseGrammarScanner/Resources/Grammar/contrasts/contrasts.json`（简中原稿）+ `contrasts_{zh-Hant,en,ko,es,vi,my}.json`。繁体用 `tools/make_contrasts_zh_hant.py` 由简中生成。改了原稿后，其它语言要同步重译对应条目，`tools/validate_contrasts.py` 会检查句子数、标题等是否和原稿对得上。
- 之前批量翻译用的临时脚本在旧会话的临时目录里，已不可用；以后少量修改直接手改各语言 JSON 即可。

### Build 17 反馈处理进度（2026-11-21，Build 18）

- 已改：反馈 1、2、3、4、6、7、8 全部；反馈 5、9 先改了截图里指出的条目：
  - 反馈 5：`te-iru` ↔ `ta-form` 互相从「意思差不多的」移出，原文（7 种语言）存到 `docs/content/parked_contrasts.json`（待用清单）；两组说明改成唯一的共同意思。
  - 反馈 9：`kosoado-konna` ↔ `kosoado-determiners` 的线索改为 いつか、ください，「怎么分辨」点名这两个词；App 里「怎么分辨」正文出现线索词时画同样的虚线（`RubyText.cueRanges`）。
  - `tools/validate_contrasts.py` 新规则：线索词必须出现在 explain 里。还没改好的旧条目（1685 条）记在 `tools/contrast_cue_debt.json`，只能删不能加。
- 必考：`frequency.json` 里 ni-tsuite、kara-ni-kakete、wo-chuushin-ni、dake-de-naku 由 low 改 high；kke、tatte、ttara 由 low 改 medium。
- 留到 Build 19（等「相近语法内容质量标准」定稿）：逐组复核 800 个 meaning 组；按标准重写 1685 条线索 / 讲解，清空 cue debt；全面复核出题频率。

## Build 18 / Build 19 进度（2026-11-21）

- Build 18：版本号 1.0（Andy 决定首发改回 1.0），提交 `e3acedc`，单元测试和 e2e 4 组全绿后上传 App Store Connect 成功。
- Build 19（分支 `claude/project-thread-93x500`，PR #8）：Build 18 反馈 1、2 已实现（首页复习一行 + 铃铛 + 樱花飘过；收藏樱花 + 巾着标签 + 飘进收藏）；商店文案去掉「完全离线」、补复习、写明免费；合入相近语法按质量规范全量重做（PR #12，`fac9984`，两道内容门槛通过）。
- 发现并修好：CI 宽屏模拟器上导航栏按钮挪到右侧竖排时，自绘的樱花按钮留在页面右上角、往下滑就消失；改成图片资源 SakuraOutline / SakuraFilled 做按钮标签（定向 e2e 已通过）。
- Build 19：1.0 (19)，提交 `9245e28`，单元测试和 e2e 全绿（2 组因 CI 机器故障重跑后通过）后上传成功。
- 2026-11-22 事故：1.0 的构建在 TestFlight 首页看不到（首页只显示版本号最高的 1.3，1.0 的在「以前のビルド」里）。Andy 改定**上架版本用 1.4**。门槛：`release.yml` 新增 `version-check` 任务（`tools/require_version_not_lower.py`），版本号低于 TestFlight 上已有的最高版本就拦下；单元测试 `tools/tests/test_require_version_not_lower.py`。
- PR #8 已改为直接合进 main（本分支已包含 #5、#6、#10、#12 的全部提交并合并了 main），Andy 已同意测试全绿后合。

## Build 18 体验反馈清单（等用户说「反馈完了」再统一改）

### 反馈 1：首页「快要忘了」太显眼，App 要克制（截图 `docs/handoff/b18_fb01_review_card.png`，2026-11-21）

用户原话：可以提醒用户，但不要过多抢注意力、不刻意制造压力。想做成一行；前面一个小铃铛，进首页时铃铛摇一下，然后一束光像水波一样从那行字上划过去，光用主题色。

约定的做法（待「反馈完了」后实现，先出设计图）：
- 首页「快要忘了」卡片改成普通卡片样式的一行：「🔔 N 个语法可以复习了 ›」，不要绿色底板、不要列表、不要大按钮；没有到期的就整行不显示。
- 铃铛用线条版（SF Symbol `bell` 那种，用户选 A）。
- 每次来到首页：铃铛摇一下，接着粉色樱花从这一行左边飘到右边、一边旋转（约 4 朵完整的五瓣樱花，大小不一，夹着约 4 片散落的花瓣，约 4 秒），只播一次。原来的「主题色光扫过」作废（用户改成樱花，2026-11-21）。系统「减弱动态效果」打开时不播。
- 不加触感（震动）：用户 2026-11-21 决定不要。
- 点这一行进入复习。要同步改：首页的 e2e（ReviewTests 等）、使用指南「复习」卡片的文字和插图、首次引导里的复习页。

### 反馈 2：收藏改成「收集樱花」（2026-11-21，用户确认按推荐方案）

- 详情页右上角的收藏图标从五角星改成樱花：未收藏 = 线条五瓣樱花；已收藏 = 实心粉色樱花（花瓣 #F6B3C6，花心 #E87A9A）。
- 底部标签栏「收藏」图标改成巾着袋（日式抽绳小布袋）线条图标。
- 点收藏时：右上角的樱花化作约 2 朵小樱花 + 约 3 片花瓣，沿一条连续的弧线（不要先炸开再飞，只一段）飘进底部「收藏」标签，彼此稍微错开像一串，约 1.2 秒；到达时小布袋轻轻鼓一下、短暂变粉；右上角变成实心粉色樱花。
- 取消收藏不播动画；「减弱动态效果」打开时不播；不加震动。
- 要同步改：列表行里的收藏星标（row.star）是否也换成樱花（实现前在设计图里一起给用户看）、收藏相关 e2e、使用指南和首次引导里出现星标的插图。

## Build 19（1.4 (21)）体验反馈清单（等用户说「反馈完了」再统一改）

用户 2026-11-22 13:16（日本时间）在设计图里选定：图标 A（线条版，和系统标签图标一样高 28pt）；详情页收藏动效 A（大樱花带三片花瓣慢慢飘进「收藏」标签，袋子变粉）；复习页 R2（樱花飘走 + 顶部提示「已收进收藏」）；收藏后右上角按钮消失，标题下显示「已收藏」可点取消（U2），收藏页左滑「取消收藏」（U1）；详情页顶栏 D1（大标题跟着滑动移进顶栏正中并缩小，柔和毛玻璃边缘）；语法库 L1（系统大标题滑动时缩小，搜索框和等级筛选固定在顶部，背后一块毛玻璃）；首页 H2（去掉大标题，说明放进相机按钮，「试试示例」只在还没扫描过时显示为小链接）。设计图：https://claude.ai/artifact/Fp2Y8E6dDoCRgjPxRtwzo4

### 反馈 1：标签栏「收藏」的巾着小布袋图标（截图 `docs/handoff/b19_fb01_kinchaku_tab.png`，2026-11-22）

用户原话：(a) 必须设计得和其他图标一样大；(b) 图标样式多设计几个，让用户从中选一个。

现状：标签栏图标是 `Assets.xcassets/Kinchaku.imageset/kinchaku.svg`（25×25 模板图），其它 4 个标签用 SF Symbols。截图里巾着明显比「首页」「语法库」「搜索」小、线条细。
做法：出 4–6 个巾着样式（例如：线条版 / 实心版 / 带樱花结扣 / 圆润版等），每个都按 SF Symbols 标签栏图标的视觉大小和线宽画，做成**并排预览图**（放在真实标签栏里，和其它 4 个图标一起，浅色 + 深色）给用户选；选定后再改资源。`FavoriteFlight.swift` 的 `KinchakuShape` 与 SVG 是同一形状，要一起改。

### 反馈 2：樱花飞进收藏的动效（2026-11-22）

用户原话：现在的动效是在小布袋旁边闪了一个粉红色的小布袋，太 low、太随意、太敷衍，必须重新设计。

现状：`FavoriteFlight.swift` 的 `FavoriteFlightOverlay`：樱花飞到标签栏后，在标签图标位置叠一个粉色填充的 `KinchakuShape` 闪一下。
做法：先出动效方案（参考 Apple 自带 App 的「加入」反馈动效，附来源），用分镜图或录屏给用户确认后再写代码；e2e `SakuraAnimationTests` 跟着改。

### 反馈 3：详情页顶部标题栏要毛玻璃、标题要跟手（截图 `docs/handoff/b19_fb03_title_bar.png`，语法「〜を兼ねて」N2，2026-11-22）

用户原话：这一整块标题栏要的是毛玻璃效果，现在全部是一层实心遮盖；要 iOS 27 那种、符合苹果 iOS 27 设计的毛玻璃。还有跟手：往上滑的时候，标题要渐渐放到顶上，渐进式的感觉。不确定的话先做一组设计给他挑。

现状：`GrammarDetailView.swift` 的 `DetailTitleBar`：标题栏底色基本不透明（Build 17 反馈 1 时按「毛玻璃但基本不透明」做的），截图里像一整块实心底；标题在滚过一定位置后才出现在顶栏，不是随滚动距离渐进移动。
做法：先查 Apple 文档里 iOS 26/27 的 Liquid Glass 和滚动边缘效果（`scrollEdgeEffectStyle` 等）以及系统大标题收进导航栏的标准做法（附来源），出 3–4 个方案（不同毛玻璃强度 / 系统原生大标题收起 / 自绘跟手过渡），做成静态对比图加滚动录屏给用户挑；选定后再改代码，e2e 里标题居中、可见的断言跟着改。

### 反馈 4：详情页点收藏时的樱花太小、落得太快（2026-11-22）

用户原话：详情页点右上角收藏按钮时，樱花和花瓣太小，用户根本看不清是不是樱花，要放大；下落速度也太快，同样看不清。这块效果重新做一版给他选。

现状：`FavoriteFlight.swift` 的 `FavoriteFlightOverlay` 负责樱花从按钮飞向「收藏」标签以及飘落的花瓣，大小和时长都写在这个文件里。
做法：和反馈 2（收藏动效）合在一起出方案：樱花和花瓣放大、放慢，做 2–3 个版本的录屏给用户挑；选定后改代码，`SakuraAnimationTests` 跟着改。

### 反馈 5：语法库的 JLPT 分段筛选上滑时要吸顶（截图 `docs/handoff/b19_fb05_library_filter.png`，2026-11-22）

用户原话：用户往上滑时，JLPT 分段筛选（全部 / N5–N1）不要滑走；固定停在搜索框下面，同样用毛玻璃，让列表从下面滑过去，要丝滑。截图里「语法库」标题和分段条都圈了。

现状：语法库页里分段条是列表内容的一部分，上滑就跟着滚走。
做法：和反馈 3 的毛玻璃顶栏一起出方案：标题、搜索框、分段条组成吸顶区域，背后用同一种毛玻璃，列表从下面滑过；在设计图和滚动录屏里一起给用户看。补 e2e：上滑后分段条仍可见、可点。

### 反馈 6：详情页已收藏后，右上角不再显示收藏按钮（截图 `docs/handoff/b19_fb06_favorited_button.png`，语法「〜が欲しい」N5，2026-11-22）

用户原话：已经点了收藏，右上角就不要再显示收藏按钮；要那种感觉：点收藏之后，樱花被收进小袋子里，那它自然就没有了。

现状：已收藏时右上角显示实心粉色樱花（`FavoriteSakuraButton`，`SakuraFilled`），再点就是取消收藏。
要一起定的：按钮消失后，用户在详情页怎么取消收藏、怎么知道已收藏。候选：只在收藏页里左滑取消；或右上角换成一个很小的「已收藏」状态（不是按钮）；或长按标题取消。方案里给用户看，和反馈 2、4 的收藏动效（樱花飞进巾着）一起设计。
测试要改：`FavoritesTests`、`SakuraAnimationTests` 和 `DetailTests.testDetailFeedbackLink` 里依赖 `detail.favorite` 在收藏后仍存在、可再点取消的断言；新增 e2e：收藏后 `detail.favorite` 消失，收藏页里能取消，取消后回到详情页按钮重新出现。

### 反馈 7：首页「扫描日文，找出语法」标题和说明太占地方（截图 `docs/handoff/b19_fb07_home_headline.png`，2026-11-22）

用户原话：这段说明文本占了这么大的空间，能不能删掉，或者做到相机扫描这个模块的某个地方；出 UI 给他选。

现状：首页搜索框下面是大标题「扫描日文，找出语法」和一行灰色说明「对准书页或选一张截图，句子里的语法会被标出来。」，再下面是「相机扫描」大按钮和「从相册识别 / 试试示例」。
做法：出 3 个方案的首页设计图给用户选，例如：A 直接删掉标题和说明；B 把一句短说明放进「相机扫描」按钮里（按钮下方一行小字或按钮内副标题）；C 标题和按钮合成一张扫描卡片。选定后改代码；首次引导和使用指南如果引用了这句话要同步改；首页 e2e 里依赖这段文字的断言跟着改。

### 反馈 8：打开 App 时没看到铃铛摇和樱花飘过（截图 `docs/handoff/b19_fb08_review_motion.png`，2026-11-22）

用户问：打开 App 时，复习那一行的铃铛抖一抖、樱花飘过的动效没看到，是不是 bug。

代码（`HomeView.swift` 的 `ReviewRow`、`Sakura.swift` 的 `SakuraDrift` / `DecorativeMotion`）：只在这一行 `onAppear` 时播一次（铃铛 0–0.7 秒，樱花 0.45 秒起约 4 秒）；系统「减弱动态效果」打开时不播。
推断的原因（未在真机复现）：
1. App 从后台切回来时，SwiftUI 不会再触发 `onAppear`，所以不播；只有冷启动或从别的标签切回首页时才播。和 Build 18 反馈 1 约定的「进首页时摇一下」不符，算 bug。
2. 冷启动时 `onAppear` 发生在系统的启动过渡动画期间，铃铛那 0.7 秒基本被盖住。
修法：App 回到前台（`scenePhase` 变成 `.active`）且停在首页时也播；首次出现时等启动过渡结束（或首页真正可见）再开始计时。补测试：单元测试覆盖「回到前台会触发播放」的判断；e2e `SakuraAnimationTests` 加一条「切到后台再回来，铃铛和樱花重新出现」（XCUIDevice home + activate）。

### 反馈 9：复习页的收藏和详情页保持一致（截图 `docs/handoff/b19_fb09_review_favorite.png`，「〜だけに」N2，2026-11-22）

用户原话：复习页的收藏行为也要和详情页的收藏按钮一致。只是这里点收藏之后，怎么收进小布袋里，要重新好好设计；设计好的 UI 拿给他选。

现状：复习页（底部是「忘了 / 有点模糊 / 记得」，没有标签栏）右上角也是樱花收藏按钮，和详情页同一个 `FavoriteSakuraButton`。
做法：按反馈 6，收藏后按钮消失。复习页看不到标签栏里的巾着，所以收进袋子的动效要单独设计（例如在按钮位置出现一个小巾着，樱花落进去后袋口收紧再淡出），出 2–3 版 UI / 录屏给用户选，和反馈 2、4、6 一起出方案。e2e 补复习页收藏后按钮消失、收藏页里出现该语法。

### 反馈 10：首页「试试示例」按钮太大，要想想还要不要（截图 `docs/handoff/b19_fb10_sample_button.png`，2026-11-22）

用户原话：想一下这个按钮还有没有存在的必要；即使有，也不要做得那么大，它没那么重要，用户只用一次。

现状：首页「从相册识别」旁边和它一样大的「试试示例」（`HomeView.swift` 约 175 行）；扫描页（`ScanHomeView.swift` 87、107 行）也有「试试示例书页」入口。
建议（待用户在设计图里选）：A 首页去掉，只留扫描页里的入口；B 只在还没有任何扫描记录时显示，并改成一行小链接；C 并进反馈 7 的扫描卡片，做成卡片里的一行小字链接。「从相册识别」随之变成整行或和相机按钮并排。和反馈 7 的首页方案一起出图。若删除，检查首次引导、使用指南和 e2e（`HomeTests` 等）里对「试试示例」的引用。

### 反馈 11：CloudKit 后台下载的反馈截图没有扩展名，打不开（2026-11-22）

用户发来两张截图：Production → Feedback 里 1.0 (19) 的反馈，`screenshots` 有两个文件（151KB、166KB），下载后文件名是一串字符（如 `AV8bxSobtBhhoNU8UhnMI62jhQgk`），没有扩展名，Finder 显示「Document」，打不开。
（说明：Build 17 反馈 2 的下载报错已经解决，现在能下载了。）

原因：`FeedbackSender.swift` 上传前把截图存成 `<UUID>.jpg`（JPEG，最长边 1600），但 CloudKit 的 Asset 只存文件内容、不保存文件名，控制台下载时用服务器给的 ID 当文件名，所以没有 `.jpg`。文件内容本身就是 JPEG。
现在的办法：下载后把文件名后面加上 `.jpg`，或者把文件拖到「预览」上打开。
App 这边改不了下载时的文件名。要彻底省掉这一步，只能另做一个查看工具（例如 GitHub Actions 定时把截图取出来存成 .jpg）；用户之前说过不要邮件转发，也不要 Server-to-Server 密钥方案，所以先不做，等用户决定要不要。
