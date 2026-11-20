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

## 内容质量原则

- 质量优先，宁缺毋滥，不凑数。
- 「相近语法」新版资料（`Resources/Grammar/contrasts/`）：
  - 三组：同一个词变来的（root）/ 长得像的（look）/ 意思差不多的（meaning）；没有合格内容的组不写；
  - 对比例句尽量只换语法（最小对比），用线索（原因、时间词、后半句）逼出本质；
  - 差别在接续时配一个确定错误的 ✗ 例；讲解说「看哪里就能分辨」；
  - 挑不出能讲清差别的例句，这一项就不收。
- 日语例句要自然、注音准确；翻译不残留中文。

## 工作方式

- 用户分批反馈问题时，先记下，等用户说「反馈完了」再统一改。
- 涉及较大界面改动，先出设计图给用户确认再写代码。
- 回复用户使用简体中文。
