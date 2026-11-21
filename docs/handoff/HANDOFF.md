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

---

## 3. 待用户确认 / 后续

1. **iCloud 反馈验证**：用户在 TestFlight 装 Build 17 后提交一条反馈，然后到 CloudKit Console → **Production** → Records → Feedback 确认能看到。这是验证权限收紧后（见 §5）开发者本人仍能读到反馈。
2. **缅甸语翻译**：建议找母语者审一遍相近语法的缅甸语翻译（`Resources/Grammar/contrasts/contrasts_my.json`）。有一部分把「ます形 / て形」写成 `ます ပုံစံ / て ပုံစံ`，和其它部分术语不统一。术语表：被动=ခံရပုံစံ、尊敬语=ရိုသေစကား、谦让语=နှိမ့်ချစကား、使役=ခိုင်းစေပုံစံ、可能形=နိုင်ပုံစံ。
3. PR #6 还是草稿，是否合并到 main 由用户决定。

---

## 4. CI 与发版流程（务必遵守 CLAUDE.md：同一提交 e2e 全绿才能发版）

### CI：`.github/workflows/ios.yml`（push 到 main / pull_request / 手动）
- 任务：`validate-data`、`build-and-test`、`e2e`、`screenshots`。`e2e` 约 80–90 分钟（上限 150 分钟），整套约 1.5 小时。
- 并发组 `${{ github.workflow }}-${{ github.ref }}`，新提交会取消同一 PR 上正在跑的 CI。
- 提交信息带 `[skip ci]` 不触发 CI（只改文档/资料时可用，但**发版用的提交必须有完整的绿色 CI**）。
- e2e 稳定性措施：模拟器启动后 sleep 30 秒；先跑一个预热用例（`SearchTests/testNoResults`，结果忽略）；结束后 `tools/check_e2e_ran_all.py e2e.log` 核对 UITests 里声明的每个测试都出现 `passed`（模拟器头几分钟会出现启动超时、测试进程崩溃导致用例被静默跳过）。
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
- Schema：`cloudkit/schema.ckdb`，已由用户部署到 Production。Feedback、UsageDay 只给 `_creator` 写、`_icloud` 创建，**不对 `_world` 开放读取**（用户数据只给提交者本人）。`tools/validate_compliance.py` 有规则拦截给 `_world` 开权限。
- GitHub Secrets 里有 CloudKit 管理令牌（用于 `cktool` 导入 schema）和 ASC API Key（`ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8`）。变量：`APPLE_TEAM_ID`、`BUNDLE_ID`、`CLOUD_FEEDBACK=true`。
- 「把反馈转发到邮箱」（SETUP.md 第 3、4 步，需要 Server-to-Server Key）**用户已同意不启用**：避免让 GitHub 读到用户数据。不要再提议启用，除非用户主动要求。
- 令牌、密钥只放 GitHub Secrets，不要让用户贴到聊天里。

---

## 6. 内容资料备忘

- 相近语法：`JapaneseGrammarScanner/Resources/Grammar/contrasts/contrasts.json`（简中原稿）+ `contrasts_{zh-Hant,en,ko,es,vi,my}.json`。繁体用 `tools/make_contrasts_zh_hant.py` 由简中生成。改了原稿后，其它语言要同步重译对应条目，`tools/validate_contrasts.py` 会检查句子数、标题等是否和原稿对得上。
- 之前批量翻译用的临时脚本在旧会话的临时目录里，已不可用；以后少量修改直接手改各语言 JSON 即可。
