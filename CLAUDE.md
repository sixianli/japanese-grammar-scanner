# 日语语法扫描 App — 协作约定

## 每次改动都要同步改测试（必须遵守）

修 bug、加功能、改行为时，**相关的测试一定要一起改或补上**，不能只改代码：

1. **修 bug**：先补一个能复现这个 bug 的测试（旧代码上会失败，修好后通过），防止以后悄悄回来。
2. **加功能 / 改行为**：
   - 逻辑加单元测试（`JapaneseGrammarScannerTests/`）；
   - 用户能点到的流程加端到端测试（`JapaneseGrammarScannerUITests/`，基类 `E2ETestCase`），覆盖主要路径；
   - 旧测试里写死了旧行为的断言，要同步改掉，不能留着过时的断言。
3. **资源 / 内容**：改了 `Resources/Grammar/` 下的资料，要让 `tools/validate_grammar.py`、`tools/validate_contrasts.py` 通过；
   需要时给校验脚本加新规则。
4. 提交 / PR 说明里列出「这次改动对应改了哪些测试」，方便对照有没有漏测。
5. 新加的界面元素给 `accessibilityIdentifier`，端到端测试按 id 查找。

本地无法运行 Xcode 时，以 CI（`.github/workflows/ios.yml`：validate-data / build-and-test / e2e / screenshots）结果为准。
**同一个提交的 e2e 没有全部跑完并通过，不能发版（打 Build）**；给用户发 Build 前要说明单元测试和 e2e 各自的结果。

## 使用引导随功能同步更新（必须遵守）

加新功能、改了用户看得到的操作方式或界面时，**使用引导要在同一个改动里一起更新**，不能只改代码：

1. 设置里的「使用指南」：新功能要有对应条目（分步骤图文说明）；改了操作方式的，相应步骤和配图要改；删掉的功能要从指南里删掉。
2. 首次打开的引导：核心流程（扫描 → 看讲解 → 相近语法 → 复习）有变化时同步改；不能留过时的说法。
3. 指南文字同样要翻译成全部界面语言。
4. 测试兜底：主要功能清单（`Models/AppFeature.swift`）里的每一项都必须有指南条目（单元测试 GuideAndLegalTests）；
   新增的页面入口（Route、标签页、设置入口）要归到某个功能下，否则编译 / 测试不通过。
5. 提交 / PR 说明里列出「使用引导改了什么」。

## 隐私政策 / 使用条款 / 开源许可 / 界面翻译：硬门槛（必须遵守）

和代码对不上 CI 就不通过（`validate-data` 任务），发版流程也会拦下：
- 隐私政策（`Services/LegalContent.swift`）：`tools/validate_compliance.py` 扫描代码里的框架、权限、iCloud 上报字段、本机存储、网址，
  对照 `tools/compliance/privacy_inventory.json`；多了、少了、政策没写到都报错。清单变了要同步改政策、`privacyUpdated` 和 `privacyInventoryHash`，
  并运行 `python3 tools/validate_compliance.py --write-web` 重新生成网站上的政策（docs/index.html）。
- 使用条款：试用天数、是否购买等事实直接取自代码设置，不手写。
- 开源许可（`Resources/Legal/third_party.json`）：项目里用到的第三方组件（Swift 包、构建工具的 Python 包、字体）必须登记，
  进 App 的写这里，只在开发时用的写 `tools/compliance/dev_only.json`；不用了也要删。
- 界面文字：`tools/check_strings.py` 检查界面上的中文都在 `tools/make_strings.py` 里有全部语言的翻译。

## 内容质量原则

- 质量优先，宁缺毋滥，不凑数。
- 「相近语法」新版资料（`Resources/Grammar/contrasts/`）：
  - 三组：同一个词变来的（root）/ 长得像的（look）/ 意思差不多的（meaning）；没有合格内容的组不写；
  - 没有万能的机械规则，不要一刀切：每组先想「用户看完能学到什么」再判断——
    - root：能讲出真实的、帮助理解的共同源头（词源/词根，可以是助词、助动词）；
    - look：读文章时真会看混、点破后让人惊叹「原来长得这么像，意思却完全不同」；
    - meaning：意思或语法功能一样（逆接、原因、完全否定…）；只是语体不同的也收，意思相反的不收；
  - 对比例句尽量只换语法（最小对比），用线索（原因、时间词、后半句）逼出本质；
  - 差别在接续时配一个确定错误的 ✗ 例；讲解说「看哪里就能分辨」；
  - 挑不出能讲清差别的例句，这一项就不收。
- 日语例句要自然、注音准确；翻译不残留中文。

## 工作方式

- 用户分批反馈问题时，先记下，等用户说「反馈完了」再统一改。
- 涉及较大界面改动，先出设计图给用户确认再写代码。
- 回复用户使用简体中文。
