# App Store 多语言商店页

## 放在哪里

- 文案：`docs/appstore/listing/<语言>.json`，每个文件一种 App Store 语言，字段是
  `name`（名称）、`subtitle`（副标题）、`privacyPolicyUrl`（隐私政策网址）、`promotionalText`（宣传文本）、
  `description`（描述）、`keywords`（关键词）、`supportUrl`（支持网址）、`marketingUrl`（营销网址）、
  `screenshots`（用 `docs/appstore/screenshots/` 下哪个文件夹的截图）。
- 截图：`docs/appstore/screenshots/<文件夹>/`，按文件名顺序就是商店里的顺序。

## 有哪些语言

主要语言是简体中文（`zh-Hans`）。另外是 English (U.S.)（`en-US`）、English (U.K.)（`en-GB`）、한국어（`ko`）、
Español (México)（`es-MX`）、Español (España)（`es-ES`）、Tiếng Việt（`vi`）、繁體中文（`zh-Hant`），
和 App 界面的语言一一对应；两种英文、两种西班牙文用同一份文案。

App 界面另有缅甸语，但 App Store 没有缅甸语商店页。缅甸店面的默认语言是 English (U.K.)，所以必须有 `en-GB`，
否则缅甸用户会看到简体中文页（来源：https://developer.apple.com/help/app-store-connect/reference/app-store-localizations/ ）。

博客上的 App 主页只有中文、英文、日文三种，所以繁体中文用中文主页，其余语言用英文主页（`/en/`）。

## 规则（`python3 tools/appstore_listing.py --check` 会检查，CI 的 validate-data 也会跑）

- 名称、副标题不超过 30 个字符，宣传文本不超过 170，关键词不超过 100，描述不超过 4000。
- 关键词里不要放名称、副标题里已有的词：Apple 会把名称和副标题一起用来搜索，重复不加权重
  （来源：https://developer.apple.com/app-store/search/ ）。副标题写了「N1-N5」，所以关键词只补 N2、N3、N4。
- 语法数量写实数（878），不写「全部」。
- 每种语言 1 到 10 张截图，尺寸 1206×2622 或 1179×2556。

## 怎样上传到 App Store Connect

GitHub 仓库 → Actions → 「App Store listing」→ Run workflow：

- `version` 填 App Store Connect 里待提交的版本号（例如 1.4）。
- 不勾 `upload`：只连上 App Store Connect 列出会改什么，不写入。
- 勾上 `upload`：写入。只改有变化的字段；截图和后台不一样时，删掉后台那一组再按顺序重传。

这个任务用的是发版也在用的 App Store Connect API 密钥（仓库 Secrets 里的 `ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_P8`），
不会把密钥写进日志。改了 `listing/`、`screenshots/` 或上传工具的 PR 会自动跑一次只读的检查，在日志里列出会改什么。
已经提交审核的版本不能再改，工具会直接停下。审核联系人信息和审核备注不归这个工具管，在网页上填。
