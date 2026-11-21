# 开发说明

这份文档写给修改本项目代码和语法资料的人。App 的介绍和构建步骤见根目录的 [README](../README.md)。

## 工程格式

工程使用 Xcode 16 起支持的“文件夹同步”格式：`JapaneseGrammarScanner/` 目录下新增的文件会自动加入工程，不用手动拖进 Xcode。用更旧的 Xcode 时，可以用 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（一个按配置文件生成 Xcode 工程的工具）通过 `project.yml` 重新生成工程。

## 目录结构

```
JapaneseGrammarScanner/
  App/                     App 入口、TabView（底部标签栏）
  Models/                  GrammarPoint（语法点数据模型）、扫描结果模型
  Services/
    GrammarLibrary.swift   加载 App 里打包的语法 JSON
    GrammarMatcher.swift   用正则表达式识别语法，并合并、抑制重叠的命中
    TextRecognizer.swift   用 Vision 识别日文，拼接多行文本并保留每段文字在图片上的位置
    ScanAnalyzer.swift     把语法命中映射回图片坐标，生成高亮框
    CameraController.swift 相机采集，并限制实时识别的频率
    FavoritesStore.swift   收藏
  Views/                   扫描、识别结果、讲解、语法库、收藏
  Resources/Grammar/       语法资料 grammar_*.json、l10n/（其它语言讲解）、furigana.json（注音）
tools/
  validate_grammar.py      校验语法资料（字段、引用、正则、例句必须能被识别）
  scan_text.py             在命令行模拟识别，用来调试正则
```

## 识别原理

1. **文字识别（OCR，把图片里的文字转成文本）**：用 Vision 的 `VNRecognizeTextRequest`，语言 `ja-JP`，精度 accurate。书本排版的换行位置是任意的，所以各行直接拼接，只在句末标点后换行，这样跨行的语法也能识别。
2. **语法识别**：每个语法点在 JSON 的 `patterns` 里定义若干正则表达式（一种描述文字模式的写法），用前后断言排除常见误判。同一语法的重叠命中会合并；`subsumes` 用来抑制被更长语法包含的命中，例如「なければならない」里的「ば」。
3. **高亮**：重叠的命中合并成一个可点击的高亮块；用 `VNRecognizedText.boundingBox(for:)` 拿到文字在图片上的位置，跨行的命中在每一行分别画框。

## 多语言

- 界面文字：`JapaneseGrammarScanner/Localizable.xcstrings`、`InfoPlist.xcstrings`，由 `tools/make_strings.py` 生成。
- 语法讲解：基础文件 `grammar_*.json` 含日语例句、识别规则和简体中文讲解；`Resources/Grammar/l10n/l10n_<语言>_<等级>.json` 是其它语言的讲解，App 启动时按系统语言覆盖。
- 繁体中文由 `tools/make_zh_hant.py` 用 OpenCC（一个简繁转换库，这里用台湾用语）从简体生成，日语片段保持不变；带中文说明的标题由 `tools/l10n_titles.py` 写入。
- `tools/validate_grammar.py` 会检查每种语言的条目、顺序、数组长度，以及译文里是否残留中文。

## 修改语法资料

在 `JapaneseGrammarScanner/Resources/Grammar/` 下编辑或新增 `grammar_*.json`（格式参考现有文件），然后运行：

```bash
python3 tools/validate_grammar.py
python3 tools/scan_text.py "雨が降りそうだから、傘を持っていったほうがいい。"
```

第一条校验资料，要求每个例句都能被本语法的 `patterns` 识别出来；第二条显示一句话的识别结果。
