# 日语语法扫描（Japanese Grammar Scanner）

一款 iOS App：用相机扫描书本上的日文，或从相册选一张图片，App 会找出文中的语法点并全部高亮，点一下高亮就能看讲解。

## 主要功能

- **扫描即高亮**：实时取景时语法点直接标在画面上，颜色对应 JLPT（日本语能力考试）等级；也可以定格画面或选相册图片，做更精确的识别。
- **详细讲解**：每个语法点有意思、接续与用法要点、使用场景、词源、例句，以及和相近语法的对比，可以直接跳到相近语法。
- **语法库**：收录 JLPT N5–N1 常见语法 969 个，按等级浏览，可搜索标题、读音、意思和例句。
- **收藏**：把想复习的语法点收藏起来，随时查看。
- **完全离线**：文字识别用 Apple 设备端的 Vision 框架，语法识别用内置规则，讲解资料打包在 App 里；不联网，不上传图片。
- **多语言**：界面和讲解支持简体中文、繁體中文、English、한국어、Español、Tiếng Việt，跟随系统语言。

## 系统要求

- iPhone，iOS 17 或更高版本（扫描需要相机，模拟器上只能用相册图片）
- 构建需要 Xcode 26 或更高版本

## 从源码构建

```bash
open JapaneseGrammarScanner.xcodeproj
```

在 Signing & Capabilities 里选择自己的开发者 Team，按需修改 Bundle Identifier（App 的唯一标识），然后连接 iPhone 运行。

修改语法资料、多语言文本或识别规则前，请先读 [开发说明](docs/development.md)。

## 项目结构

```
JapaneseGrammarScanner/        App 源码（界面、文字识别、语法识别、本地数据）
  Resources/Grammar/           语法资料和各语言讲解（JSON 数据文件）
JapaneseGrammarScannerTests/   单元测试
tools/                         资料生成与校验脚本
docs/                          开发说明、隐私政策、App Store 资料
```

## 已知限制

- 语法识别基于规则，不做完整的句法分析。少数形式相同、意思不同的语法（例如被动和可能的「られる」、样态和传闻的「そうだ」）会同时列出，由用户判断。
- 竖排文字的识别效果不如横排。

## 版权

© 2026 sixianli. 保留所有权利。本仓库源码仅供在 GitHub 上浏览，未经作者书面许可，禁止复制、修改、分发或用于任何用途（包括上架应用商店）。

© 2026 sixianli. All rights reserved. This source code is published for viewing on GitHub only. No permission is granted to copy, modify, distribute, or use it for any purpose (including publishing to app stores) without the author's prior written consent.

构建时使用的第三方开源组件见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
