# App Store 上架资料

以下内容可直接填写到 App Store Connect。

## 基本信息

| 字段 | 内容 |
| --- | --- |
| App 名称 (30 字以内) | 日语语法速查 |
| 副标题 (30 字以内) | 学日语 JLPT N1-N5 语法拍照识别 |
| 主要类别 | 教育 (Education) |
| 次要类别 | 参考 (Reference) |
| 年龄分级 | 4+（「酒精、烟草或药物的使用或提及」选“偶尔”，例句里约 70 句提到酒或烟；其余选“无”或“否”） |
| 价格 | 免费（全部功能免费，无内购） |
| 主要语言 | 简体中文 |
| Bundle ID | 需改为你自己的，如 `com.<你的名字>.JapaneseGrammarScanner` |
| SKU | japanese-grammar-scanner |
| 版权 | © 2026 <你的名字> |

## 商店文案、网址和截图（各语言）

名称、副标题、宣传文本、描述、关键词、支持网址、营销网址、隐私政策网址和截图，都放在 `docs/appstore/listing/<语言>.json`
和 `docs/appstore/screenshots/<文件夹>/`，简体中文是 `listing/zh-Hans.json`。改了以后用 GitHub Actions 的
「App Store listing」任务上传，说明见 `metadata-localized.md`。

## App 隐私（App Store Connect → App 隐私）

开启 CloudKit（App 内反馈 + 匿名使用统计）之后：“是，我们从此 App 收集数据”，只勾选下面三项，每一项都选
**用于：App 功能 / 分析**（按下面说明）、**不与用户身份关联**、**不用于追踪**：

- **用户内容 → 客户支持**：用户主动提交的反馈描述与截图（用途：App 功能）
- **诊断 → 其他诊断数据**：随反馈附带的 App 版本、系统版本、设备型号、界面语言（用途：App 功能）
- **使用数据 → 产品交互**：匿名使用统计（打开次数与时段、查看的语法点与等级）（用途：分析）

国家 / 地区取自 App Store 店面，不是定位信息，不需要勾选「位置」。
未开启 CloudKit 时：“否，我们不从此 App 中收集数据”。

## 审核备注 (App Review Information → Notes)

审核员不一定看得懂中文，用英文：

```
All features are free. No in-app purchases, no account or sign-in required.
Scanning, explanations and review all run on the device and work offline. When online, the app uploads anonymous usage statistics and feedback the user chooses to send, via CloudKit (not linked to identity).
How to test: the app follows the device language (English, Chinese, Korean, Spanish, Vietnamese, Burmese); labels below are as shown in English. On the Scan tab, point the camera at any printed Japanese text, or tap "Photos" to pick an image containing Japanese. Detected grammar points are highlighted; tap one to see its explanation. Without Japanese text at hand, tap "No Japanese text handy? Try a sample" on the Home tab (shown until the first scan), or "Try Sample" at the top of the Scan tab, to scan a built-in sample page.
The camera is used only for on-device text recognition.
```

## 出口合规

Info.plist 已设置 `ITSAppUsesNonExemptEncryption = NO`，上传后无需额外回答加密问题。

## 截图要求

必填的是「iPhone with Dynamic Island (medium display)」一组（API 里叫 `APP_IPHONE_61`），只收 1206×2622 或 1179×2556，
每种语言 1 到 10 张。CI 的 screenshots 产物是 1320×2868（属于 large display 一组），要先缩放成 1206×2622 再放进
`docs/appstore/screenshots/`。扫描页的截图不要用：模拟器没有相机，画面上是「此设备无法使用相机」。
`tools/appstore_listing.py --check` 会检查尺寸和张数。
