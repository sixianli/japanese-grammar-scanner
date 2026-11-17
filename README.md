# 日语语法扫描（Japanese Grammar Scanner）

一个 iOS App：用相机扫描书本上的日文（或从相册选图片），自动识别文本中的语法点并**全部高亮**，点击高亮即可查看该语法点的详细讲解。

- **完全离线、不使用任何大模型**：OCR 使用 Apple 端侧 Vision 框架；语法识别使用内置的规则（正则）；全部讲解资料是打包在 App 里的静态 JSON。
- 讲解内容包括：**意思、用法（接续 + 要点）、使用场景、词源、例句、相似/相近语法的扩展对比**（可直接跳转到相近语法）。
- **收藏**：在列表或讲解页点 ☆ 收藏，“收藏”页可查看、排序、删除。
- **多语言**：界面与全部语法讲解支持 English、한국어、Español、Tiếng Việt、简体中文、繁體中文。跟随系统语言（也可在 iOS 设置 → 本 App → 语言 中单独切换），其它语言回退为英语。

## 功能

| 页面 | 说明 |
| --- | --- |
| 扫描 | 实时取景，画面上的语法点实时高亮（颜色按 JLPT 等级），顶部显示识别到的语法点标签。点击高亮/标签进入讲解。快门按钮“定格”当前画面做高精度识别；左下角从相册选图。右下角补光灯。 |
| 识别结果 | 图片上高亮所有语法点 + 下方列出全部语法点（含出现次数）+ 识别文本中高亮。多个语法点重叠时弹出选择。OCR 有错可“编辑文本”后重新识别。 |
| 语法库 | 按 N5–N2 浏览全部内置语法，支持搜索标题、读音、意思、例句。 |
| 收藏 | 收藏的语法点，本地保存（UserDefaults）。 |

## 运行

要求：Xcode 26+（App Store 上传要求 iOS 26 SDK），App 支持 iOS 17+（相机功能需要真机）。

```bash
open JapaneseGrammarScanner.xcodeproj
```

在 Signing & Capabilities 里选择自己的 Team，必要时修改 Bundle Identifier（默认 `com.example.JapaneseGrammarScanner`），连接 iPhone 运行即可。模拟器上没有相机，可以用相册图片测试。

> 工程使用 Xcode 16 的“文件夹同步”格式，`JapaneseGrammarScanner/` 目录下新增的文件会自动加入工程。若使用更旧的 Xcode，可用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 通过 `project.yml` 重新生成工程。

## 目录结构

```
JapaneseGrammarScanner/
  App/                     App 入口、TabView
  Models/                  GrammarPoint（语法点数据模型）、扫描结果模型
  Services/
    GrammarLibrary.swift   加载 Bundle 中的语法 JSON
    GrammarMatcher.swift   基于正则的语法识别 + 重叠合并/抑制
    TextRecognizer.swift   Vision 日文 OCR，拼接多行文本并保留每段子串的位置
    ScanAnalyzer.swift     把语法命中映射回图片坐标，生成高亮框
    CameraController.swift 相机采集 + 节流的实时识别
    FavoritesStore.swift   收藏
  Views/                   扫描、识别结果、讲解、语法库、收藏
  Resources/Grammar/       语法静态资源 grammar_n5/n4/n3/n2.json
tools/
  validate_grammar.py      校验语法资源（字段、引用、正则、例句必须能被识别）
  scan_text.py             命令行模拟识别，用于调试正则
```

## 识别原理

1. **OCR**：`VNRecognizeTextRequest`（`ja-JP`，accurate）。书本排版的换行是任意的，因此各行直接拼接（只在句末标点后换行），这样跨行的语法也能识别。
2. **语法识别**：每个语法点在 JSON 的 `patterns` 中定义若干正则（用前后断言排除常见误判）。同一语法的重叠命中会合并；`subsumes` 用于抑制被更长语法“包含”的命中（如「なければならない」里的「ば」）。
3. **高亮**：重叠的命中合并为一个可点击的高亮块；通过 `VNRecognizedText.boundingBox(for:)` 拿到子串在图片上的位置，跨行的命中会在每一行分别画框。

## 多语言

- 界面文字：`JapaneseGrammarScanner/Localizable.xcstrings`、`InfoPlist.xcstrings`（由 `tools/make_strings.py` 生成）。
- 语法讲解：基础文件 `grammar_*.json` 含日语例句、识别规则与简体中文讲解；`Resources/Grammar/l10n/l10n_<语言>_<等级>.json` 为其它语言的讲解，App 启动时按语言覆盖。
- 繁体中文由 `tools/make_zh_hant.py`（OpenCC，台湾用语）从简体生成，日语片段保持不变；带中文说明的标题由 `tools/l10n_titles.py` 写入。
- `tools/validate_grammar.py` 会检查每种语言的条目、顺序、数组长度，以及译文是否残留中文。

## 扩充语法资料

在 `JapaneseGrammarScanner/Resources/Grammar/` 下编辑或新增 `grammar_*.json`（格式见现有文件），然后运行：

```bash
python3 tools/validate_grammar.py           # 校验：每个例句都必须被本语法的 patterns 命中
python3 tools/scan_text.py "雨が降りそうだから、傘を持っていったほうがいい。"   # 看识别效果
```

## 已知限制

- 规则识别无法真正做句法分析，个别语法存在歧义（如被动与可能形的「られる」、样态与传闻的「そうだ」），App 会同时提示，由用户选择。
- Vision 对竖排（縦書き）文本的支持有限，横排效果最好。
