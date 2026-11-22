# 上架步骤（GitHub Actions 自动上传）

整个流程中只有下面这些需要你本人在 Apple 和 GitHub 网站上操作，其余由仓库中的 `Release to App Store Connect` 工作流自动完成（归档 → 签名 → 上传 TestFlight）。

## 1. 在 App Store Connect 创建 App（约 5 分钟）

1. 打开 <https://appstoreconnect.apple.com> → **App** → 左上角 **＋** → **新建 App**
2. 平台：iOS；名称：`语法扫描 - 日语语法拍照识别`（被占用就换一个）；主要语言：简体中文
3. **套装 ID (Bundle ID)**：如果下拉框里没有，先到 <https://developer.apple.com/account/resources/identifiers/list> 点 **＋** → App IDs → App，填写例如 `com.你的名字.grammarscanner`（不需要勾选任何 Capability），再回来选择它
4. SKU：`japanese-grammar-scanner`

## 2. 创建 App Store Connect API Key

1. App Store Connect → **用户和访问** → **集成** → **App Store Connect API** → **团队密钥** → **＋**
2. 名称随意，访问权限选 **App 管理 (App Manager)**
3. 下载 `AuthKey_XXXXXXXXXX.p8`（只能下载一次，请妥善保存），记下页面上的 **Key ID** 和 **Issuer ID**
4. Team ID：<https://developer.apple.com/account> → 会员资格详细信息 → **团队 ID**（10 位）

## 3. 配置 GitHub 仓库

仓库页面 → **Settings** → **Secrets and variables** → **Actions**：

| 类型 | 名称 | 值 |
| --- | --- | --- |
| Secret | `ASC_KEY_ID` | Key ID |
| Secret | `ASC_ISSUER_ID` | Issuer ID |
| Secret | `ASC_KEY_P8` | 用文本编辑器打开 .p8 文件，复制**全部内容**（含 BEGIN/END 行） |
| Variable | `APPLE_TEAM_ID` | Team ID |
| Variable | `BUNDLE_ID` | 第 1 步中的 Bundle ID |

## 4. 发布隐私政策页面（GitHub Pages）

仓库 **Settings** → **Pages** → Source 选 **Deploy from a branch** → Branch 选 `main`、目录 `/docs` → Save。
几分钟后隐私政策网址为：`https://<你的 GitHub 用户名>.github.io/japanese-grammar-scanner/#privacy`
（仓库需为公开仓库，或账号支持私有仓库 Pages。也可以把 `docs/index.html` 放到任何你自己的网站上。）

## 5. 上传构建

先把 PR 合并到 `main`，然后：仓库 → **Actions** → **Release to App Store Connect** → **Run workflow** → 填版本号 `1.4`（不能低于 TestFlight 上已有的版本，否则发版会被拦下） → Run。
成功后 10–30 分钟，App Store Connect → 你的 App → **TestFlight** 会出现该构建；可先用 TestFlight 在自己 iPhone 上试用。

## 5.5 配置内购（免费试用 + 一次性买断）

1. App Store Connect → **商务**（协议、税务和银行业务）→ 签署 **付费 App 协议**，填写银行与税务信息。
2. 你的 App → **App 内购买项目** → 新建两个 **非消耗型项目**：

| 产品 ID | 参考名称 | 价格 | 显示名称 / 描述 |
|---|---|---|---|
| `jgs.trial.14day` | 14-day Trial | 免费（0） | 14 天免费试用 / 免费使用全部讲解 14 天，到期后不会自动扣费 |
| `jgs.unlock.lifetime` | Lifetime Unlock | 基准 $1.99 | 永久解锁 / 一次性购买，永久解锁全部讲解 |

3. 买断项目 → **价格时间表**：基准国家选美国 $1.99，再手动调整重点地区（见下表），其余地区沿用 Apple 自动换算。
4. 两个项目都要上传一张审核截图（付费页截图即可），并在提交 App 版本时一起勾选提交审核。

地区价格（买断）：

| 地区 | 价格 |
|---|---|
| 美国（基准）、欧洲、日本、香港、台湾及其他地区 | $1.99（其他地区沿用 Apple 自动换算） |
| 中国大陆 | ¥12 |
| 韩国 | ₩4,000（若无此档位，选最接近的一档） |
| 越南 | 与 $0.99 最接近的越南盾档位 |
| 缅甸 | $0.99（约一杯珍珠奶茶） |

> 在中国大陆上架需要在 App Store Connect 填写 ICP 备案号；未备案时可先不勾选中国大陆。

## 6. 填写商店信息并提交审核

App Store Connect → 你的 App → **App Store** 标签页 → 1.4 版本：

- 截图：从 CI 的 **iOS Build & Test** → **screenshots** 产物下载（6.9 英寸 iPhone 尺寸，可直接上传）
- 宣传文本、描述、关键词、支持网址、隐私政策网址：复制 `docs/appstore/metadata.md`
- **App 隐私** → 选择「不收集数据」
- **年龄分级**：问卷全部选“无” → 4+
- **构建版本**：选择第 5 步上传的构建
- **审核信息** → 备注：复制 `metadata.md` 中的“审核备注”；不需要登录账号
- 点击 **添加以供审核** → **提交审核**

审核通常 1–3 天。通过后即可在 App Store 搜索下载。

## 之后更新版本

修改代码 → 合并到 main → 再次运行 Release 工作流并填写新版本号（如 `1.1`）→ 在 App Store Connect 新建版本并提交审核。构建号自动递增。
