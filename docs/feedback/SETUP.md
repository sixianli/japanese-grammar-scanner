# 开通「App 内一键提交反馈 → 自动转发到邮箱」

用户在 App 里点「发送」后，反馈（描述、截图、App 版本、系统版本、设备型号、语言）会静默存进你的 iCloud 公共数据库（CloudKit）。
GitHub 上的定时任务每 15 分钟检查一次，把新反馈连同截图发到你的邮箱。

没开通之前，App 的「发送」会退回到系统分享面板（不会闪退）。

所有密钥、密码都**只填在 GitHub 仓库的 Secrets 里**，不要发到聊天中。

---

## 第 1 步：建 iCloud 容器，并给 App 打开 iCloud（约 3 分钟）

1. 打开 <https://developer.apple.com/account/resources/identifiers/list/cloudContainer>
   （Certificates, Identifiers & Profiles → Identifiers → 右上角筛选选 **iCloud Containers**）
2. 点 **＋** → 选 **iCloud Containers** → Continue
3. Description 随便填（例如 `Grammar Feedback`）；Identifier 填 `iCloud.` 加上你的 Bundle ID，
   也就是 GitHub 变量 `BUNDLE_ID` 的值，例如 `iCloud.com.yourname.grammarscanner` → Continue → Register
4. 回到 Identifiers 列表，筛选改回 **App IDs**，点开这个 App 的 Bundle ID
5. 在 Capabilities 里勾选 **iCloud** → 选 **Include CloudKit support** → 点旁边的 **Configure**（或 Edit），
   勾选刚才建的容器 → Continue → 右上角 **Save**（会提示已有描述文件失效，点 Confirm）

## 第 2 步：导入反馈的数据结构，并发布（约 3 分钟）

1. 打开 <https://icloud.developer.apple.com>（CloudKit Console），登录同一个开发者账号
2. 管理令牌（Management Token）**不在**容器的 Settings → Tokens & Keys 里（那里只有 API Tokens 和 Server-to-Server Keys，第 3 步才用）。
   点 CloudKit Console **右上角的头像（你的名字）** → **Settings**（账号设置）→ 里面的 **Tokens**（Management Tokens）→ **＋** 新建一个，复制 token（只显示一次，有效期一年）
3. GitHub 仓库 → Settings → Secrets and variables → Actions → **New repository secret**：
   名称 `CLOUDKIT_MANAGEMENT_TOKEN`，值粘贴上一步的 token
4. 告诉我「token 填好了」，我来运行导入任务（也可以自己在 Actions → **CloudKit Schema** → Run workflow）
5. 导入成功后，在 CloudKit Console → 这个容器 → **Schema** → 右上角 **Deploy Schema Changes…** → Deploy
   （把数据结构发布到正式环境；TestFlight 和 App Store 版本用的都是正式环境）

## 第 3 步：生成「服务器访问密钥」，让 GitHub 能读取反馈（约 3 分钟）

1. 在 Mac 上打开「终端」，依次粘贴运行（会在桌面生成两个文件）：

   ```
   cd ~/Desktop
   openssl ecparam -name prime256v1 -genkey -noout -out cloudkit_private.pem
   openssl ec -in cloudkit_private.pem -pubout -out cloudkit_public.pem
   ```

2. CloudKit Console → 这个容器 → **Settings** → **Tokens & Keys** → **Server-to-Server Keys** → **＋**
   - Name 随便填（例如 `feedback-forward`）
   - Public Key：用「文本编辑」打开桌面上的 `cloudkit_public.pem`，复制全部内容粘贴进去（含 BEGIN / END 两行）
   - 保存后页面会显示 **Key ID**
3. GitHub 仓库 → Secrets 中新建两个：
   - `CLOUDKIT_KEY_ID`：上一步的 Key ID
   - `CLOUDKIT_PRIVATE_KEY`：用「文本编辑」打开 `cloudkit_private.pem`，复制全部内容（含 BEGIN / END 两行）
4. 填好后可以删掉桌面上这两个文件

## 第 4 步：设置发信邮箱（约 3 分钟）

转发任务需要一个邮箱来「发」邮件（可以就是你自己的邮箱，发给你自己）。邮箱要使用**应用专用密码 / 授权码**，不是登录密码：

| 邮箱 | 在哪里生成 | SMTP 服务器 | 端口 |
|---|---|---|---|
| Gmail | Google 账号 → 安全性 → 两步验证（需先开启）→ 应用专用密码 | `smtp.gmail.com` | 465 |
| QQ 邮箱 | 设置 → 账户 → POP3/IMAP/SMTP 服务 → 开启 → 生成授权码 | `smtp.qq.com` | 465 |
| 163 邮箱 | 设置 → POP3/SMTP/IMAP → 开启 SMTP → 授权密码 | `smtp.163.com` | 465 |

GitHub 仓库 → Secrets 中新建：

| 名称 | 值 |
|---|---|
| `FEEDBACK_SMTP_HOST` | 上表中的 SMTP 服务器 |
| `FEEDBACK_SMTP_PORT` | `465` |
| `FEEDBACK_SMTP_USER` | 发信邮箱地址 |
| `FEEDBACK_SMTP_PASSWORD` | 应用专用密码 / 授权码 |
| `FEEDBACK_TO` | 收反馈的邮箱地址（和上面相同也可以） |

填好后告诉我，我会运行一次「测试邮件」，你收到就说明邮箱配置好了。

## 第 5 步：打开开关

GitHub 仓库 → Settings → Secrets and variables → Actions → **Variables** → New repository variable：
名称 `CLOUD_FEEDBACK`，值 `true`。

之后上传的 TestFlight 版本，「发送」就会直接在 App 内提交。

---

## 说明

- 定时转发任务只在默认分支（main）上自动运行。代码合并到 main 之前，可以在 Actions → **Feedback Forward** → Run workflow 手动运行。
- 反馈也一直保存在 CloudKit Console → Records → Public Database → `Feedback` 里，邮件漏看了可以回去查。
- 用户需要登录 iCloud 才能在 App 内提交；没登录时 App 会提示，并提供「用其他方式发送」。
- **匿名使用统计**也走同一个 CloudKit 容器（记录类型 `UsageDay`，已包含在第 2 步导入的数据结构里），不需要额外配置。
  配好第 3、4 步后，每周一早上会收到一封「使用统计周报」（用户数、日活 / 周活 / 月活、国家 / 地区、使用时段、
  查得最多的语法点、N5–N1 分布）；也可以在 Actions → **Usage Report** → Run workflow 随时手动生成。
  如果在加入 `UsageDay` 之前已经导入过数据结构，需要重新运行一次 Actions → **CloudKit Schema**，再 Deploy Schema Changes。
- 隐私：只有用户主动点「发送」时才会上传上述信息，App 内的隐私政策已写明。上架时 App Store 隐私标签的填法见
  `docs/appstore/metadata.md` →「App 隐私」。
