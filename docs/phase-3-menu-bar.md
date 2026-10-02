# 第三阶段：菜单栏应用

2026-10-02 更新：本页保留当时的实现和验证记录；当前已取消三个账号的数量上限，并提供应用内添加、登录重试、取消、重新登录和删除。最新使用方式见[首次使用与账号管理说明](phase-5-account-management.md)。

## 实现范围

新增原生 SwiftUI `MenuBarExtra` 应用，最低 macOS 14。应用启动时并发读取本地三个账号，面板显示套餐、登录状态、五小时/周剩余额度、服务端重置时间及最后更新时间。支持“立即刷新”、刷新中的禁用状态和退出；重新打开面板不会重复自动查询。

复用 `AccountStore`、`AccountService` 和既有协议客户端，不增加认证目录或改变账号 ID。CLI、验证程序和菜单栏共用 Codex 可执行文件查找及重复身份检测。公开数据类型新增初始化方法，原有命令和存储字段保持兼容。

服务端未返回的窗口保持未知。正常卡片隐藏额度更新时间，统一查看面板底部的查询完成时间。一个账号失败时其他账号正常更新；失败账号保留上次成功数据并灰显，仅这类卡片显示“上次成功更新”及旧数据时间。删除的账号不保留卡片，相同 ID 被重新创建时不复用之前的额度缓存。运行时缓存不写入磁盘。

## 构建与运行

```bash
cd /Users/j/github_repo/codex-pulse
./scripts/test.sh
./scripts/build-app.sh
open ".build/app/Codex Pulse.app"
```

构建脚本生成 `.build/app/Codex Pulse.app`，配置 `LSUIElement`，仅显示菜单栏入口。使用本地 ad-hoc 签名，尚未公证或打包 DMG。可执行文件通过临时文件替换，避免构建时直接覆盖正在运行的二进制。

## 验证记录

2026-10-01，macOS / Apple Silicon / Swift 6.4 / Codex CLI 0.158.0：

- 应用构建、Info.plist 校验及本地签名校验通过。
- `./scripts/test.sh`：核心 35 项、菜单栏状态模型 12 项，共 47 项测试通过。
- 状态模型验证 Free 未知窗口、部分及整体查询失败保留缓存、删除及重建账号缓存隔离、忙时不重复刷新、启动只查询一次、缺少 CLI 提示和重复身份提示；新增资料接口请求、真实用户名解析、凭据校验、错误脱敏、资料失败不丢失额度、名称动态更新和跨身份缓存隔离验证。
- 用户确认三个账号和刷新按钮可见；提供的实际截图显示两个 Plus 额度及重置时间、一个 Free 的未知窗口、刷新及退出按钮。
- 桌面控制工具无法读取该菜单栏应用，未完成自动点击刷新按钮的 GUI 端到端验证。刷新编排由状态模型测试覆盖；基本显示由用户确认和截图验证。
- 本阶段登录状态及额度读取不发送模型请求。截图中的额度是当时快照，不能作为后续实时额度。

## 资料用户名需求与接口限制

用户要求卡片标题动态显示 Codex 个人资料页中的真实用户名，不能写死三个名字，也不能将邮箱前缀视为资料用户名。

已检查本机 CLI 0.158.0 的完整协议 Schema，并实际读取三个独立账号：`account/read` 的账号对象均仅含 `email`、`planType`、`type`。[官方 App Server 文档](https://learn.chatgpt.com/docs/app-server)给出的字段也一致；`account/usage/read` 提供 Token 统计，不提供资料用户名。

用户已明确允许接入只读内部资料接口。通过只读检查本机 Codex App 随包代码定位后，实现 `AccountProfileClient`，请求固定的 `GET https://chatgpt.com/backend-api/profiles/me`，解析 `profile_details.username`。不以 `display_name`、邮箱前缀或固定字符串代替该字段。

资料查询在现有账号租约内运行，读取所选账号独立目录中的 `auth.json`，不读取日常 `~/.codex`。拒绝凭据符号链接、硬链接、无效字段和过大的文件；请求使用系统 TLS 校验，无 Cookie 或磁盘响应缓存，禁止跟随重定向。令牌和原始响应不会进入错误文本、日志、报告或 Git。

每次启动查询或手动刷新都会重新读取用户名；资料失败单独显示错误，保留内存中的最近名称，首次失败使用现有别名。额度查询继续独立更新。服务端身份变化或账号重建时不会复用旧身份的名称缓存。CLI 默认维持原查询行为，只有菜单栏显式启用资料查询。

真实三账号资料请求均返回 HTTP 200；完整 `AccountService` 并发调用再次验证三个账号均有接口用户名、成功额度快照且无资料错误，名称与用户给出的三个资料用户名一致。应用代码和配置未写入这三个固定名字。

## 本阶段修改文件

- `Package.swift`
- `Sources/CodexPulseCore/CodexExecutable.swift`
- `Sources/CodexPulseCore/AccountProfileClient.swift`
- `Sources/CodexPulseCore/AccountService.swift`
- `Sources/CodexPulseCore/AccountStore.swift`
- `Sources/CodexPulseCore/AppServerClient.swift`
- `Sources/CodexPulseCLI/main.swift`
- `Sources/CodexPulseProbe/main.swift`
- `Sources/CodexPulseUI/MenuBarModel.swift`
- `Sources/CodexPulseUI/MenuBarPanel.swift`
- `Sources/CodexPulseApp/CodexPulseApp.swift`
- `Resources/Info.plist`
- `Tests/CodexPulseUITests/MenuBarModelTests.swift`
- `Tests/CodexPulseCoreTests/AccountProfileTests.swift`
- `Tests/CodexPulseCoreTests/AccountServiceTests.swift`
- `scripts/build-app.sh`
- `README.md`
- `docs/design-plan.md`
- `docs/phase-2-account-management.md`
- `docs/phase-3-menu-bar.md`
- 原方案 `/Users/j/Desktop/work/Codex多账号额度小组件推荐方案.md` 同步进度与用户名需求。

## 剩余工作与风险

资料用户名已完成动态读取，所用内部接口无公开稳定性承诺，升级后可能需要适配。自动最小请求、按服务端重置时间查询及唤醒恢复已在[第四阶段](phase-4-automatic-requests.md)实现；本阶段“只查询额度”的验证记录是第三阶段历史行为。2026-10-02 的[安装步骤](phase-4-installation.md)已提供登录时启动开关、安装及 DMG 打包。菜单栏账号管理页面和额外分钟级额度轮询仍未实现。当前仅适配已验证的 CLI 版本，升级后需检查协议兼容性；Free 账号缺少额度窗口时保持未知，不具备自动模型请求条件。当前签名用于本地开发，不代表可直接分发的公证版本。
