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

## 修测试、写界面断言、分支（必须遵守）

1. **先只跑失败的用例，通过后再跑整套。** 整套 e2e 约 40–60 分钟，还要和其他分支抢最多 5 台 macOS 机器，不能拿它来试错：
   - 修失败的 e2e（或修 e2e 发现的问题）时，提交信息带 `[skip ci]` 再推送，推送就不会触发整套；
     GitHub 规定 push 和 pull_request 触发的工作流遇到这个标记就不运行（[文档](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-workflow-runs/skipping-workflow-runs)）。
   - 然后手动触发 `iOS Build & Test`（`ios.yml`），分支选当前分支，`e2e_only` 填失败的用例（`类名` 或 `类名/方法名`，逗号分隔）。
     代理用 GitHub 工具 `actions_run_trigger`：`method: run_workflow`、`workflow_id: ios.yml`、`ref: <分支>`、`inputs: {"e2e_only": "..."}`。
     这种运行只编译并跑选中的用例，跳过单元测试和截图，只占 1 台 macOS 机器。整套失败时，`e2e` 汇总任务的日志最后会打印要填的 `e2e_only` 值。
   - 用例时好时坏时，同时填 `e2e_repeat`（例如 `5`），每个选中的用例连跑几遍，任何一遍失败都算失败。
   - 整套和定向运行里，失败的用例会自动重跑一次（CI 机器开跑前后常常满载，偶发超时）；`e2e` 汇总任务会列出「重跑才过」的用例，
     同一个用例反复出现就用 `e2e_repeat` 连跑查清，不能当作没事。填了 `e2e_repeat` 时不重跑。
   - 用例名写错时，`e2e-plan` 任务在一分钟内报错，不会白跑一个「0 个用例、显示通过」的结果。
   - 选中的用例都过了，再跑一次整套：手动触发时 `e2e_only` 留空，或正常推送一个不带 `[skip ci]` 的提交。上面「同一个提交整套通过才能发版」的规定不变，定向运行不算数。
2. **界面断言以被测元素所在的容器为准，不以屏幕为准。** CI 用的模拟器尺寸会变（屏幕更宽、右侧多一列系统按钮），所以：
   - 判断「居中」「在顶部」「被挡住」时，拿被测元素和它所在的容器比（给容器加 `accessibilityIdentifier`，例如讲解页标题栏 `detail.titleBar`），
     不拿 `app.windows.firstMatch.frame`、导航栏或屏幕中线比，也不写死像素（例如 `maxY < 200`）。
   - 不用 `app.coordinate(withNormalizedOffset:)` 去点「屏幕上大概是空白的地方」；要点就点一个具体元素（有 id 的，或按文字找到的）。
     实在没有可点的元素时（例如搜索结果铺满屏幕时收键盘），只点屏幕最顶部的状态栏一带（`dy: 0.03`），那里在任何尺寸上都不会点到内容。
3. **一个 Build 一个分支。** 下一个 Build 的改动从当前 Build 的分支另切新分支去做；当前 Build 发出去之前，不往它的分支上提交下一个 Build 的代码。
   提交前用 `git diff --cached --stat` 核对，只包含这个 Build 的改动。

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
