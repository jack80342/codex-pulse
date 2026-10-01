# Codex Pulse

Codex 多账号额度管理工具，计划支持 macOS 桌面小组件、额度监控与自动请求调度。

仓库名：`codex-pulse`；应用显示名称：`Codex Pulse`；Swift 工程名称：`CodexPulse`。

## 当前状态

已实现第一阶段的 Swift 命令行验证程序，支持 app-server 握手、独立账号登录、额度读取、模型目录、单次最小模型请求及重置后对比。尚未创建 Xcode 工程或实现菜单栏、桌面小组件、长期自动请求和 iOS 功能。

已用独立 Plus 账号完成登录、真实额度读取和一次最小请求；已有五小时窗口的重置时间未变化。已安排北京时间 2026-10-02 00:13 做一次重置后验证，五小时窗口触发机制仍待确认。详细观测见 [第一阶段验证说明](docs/phase-1-verification.md)。当前没有配置 GitHub 远程仓库。

## 第一阶段验证

需要 macOS 14 及以上、Swift 6 及以上和已安装的 Codex CLI。本次协议适配依据本机 Codex CLI 0.158.0 生成的 JSON Schema。

```bash
cd /Users/j/github_repo/codex-pulse
swift build
swift test --disable-xctest
swift run codex-pulse-probe handshake
swift run codex-pulse-probe login
swift run codex-pulse-probe status
swift run codex-pulse-probe models
swift run codex-pulse-probe probe
```

`login` 打开浏览器，由用户完成验证账号登录；`probe` 发送一次真实模型请求，会消耗额度。可通过 `--model` 指定模型目录返回的模型，省略时使用目录默认模型，并选择其支持的最低推理档位及 Standard 速度。

首次请求完成后，程序输出报告的绝对路径。到达报告记录的五小时重置时间后，再执行：

```bash
swift run codex-pulse-probe verify-reset --report "<首次报告的绝对路径>"
```

重置后验证沿用原报告模型并核对账号身份。未到重置时间、额度许可未知或已耗尽时停止，不发送模型请求。更多步骤和判定边界见 [第一阶段验证说明](docs/phase-1-verification.md)。

## 第一版目标

- 集中展示三个账号的五小时额度、周额度、重置时间和最后更新时间。
- 提供菜单栏主应用及原生 WidgetKit 桌面小组件；主应用负责登录、查询和调度，小组件读取非敏感额度快照。
- 应用启动时，对满足额度条件的账号发送一次最小模型请求，尝试启动五小时窗口。
- 按服务端返回的五小时窗口重置时间调度后续请求；周额度耗尽时停止对应账号。
- 应用重启或电脑唤醒后重新查询并恢复调度，不补发错过的请求。

最小模型请求能否启动新的五小时窗口，需要先通过真实账号进行请求前后对比验证。额度查询不能视为窗口启动，最小请求自身也会消耗额度。

## 开发顺序

1. 验证 Codex app-server 初始化、额度读取及最小请求的窗口触发行为。
2. 实现三个账号的独立登录和账号管理。
3. 实现菜单栏额度展示、手动刷新及错误状态。
4. 实现共享快照和 macOS 桌面小组件。
5. 实现自动请求调度、后台运行、唤醒恢复和打包。
6. 完成三账号联调、异常处理及与日常 Codex App 并行使用验证。

后续阶段增加 CloudKit 私有数据库同步、iOS App 和 iPhone 小组件。

## 技术方向

- macOS 14 及以上，Swift 6、SwiftUI、WidgetKit 和 App Groups。
- 通过本机 Codex CLI 的 app-server 查询额度和管理独立账号。
- 以服务端返回的窗口时长和重置时间为准，不写死 primary、secondary 对应的窗口类型。
- 自动调度需主应用运行、Mac 处于唤醒状态且网络可用。

## 账号隔离

每个账号使用独立的 `CODEX_HOME`，计划保存于：

```text
~/Library/Application Support/CodexPulse/accounts/<account-id>/
```

主应用使用独立目录重新登录，不读取或修改日常 Codex App 的 `~/.codex` 认证和全局状态。账号令牌、Cookie 和认证文件不得进入 Git 仓库、Widget 共享快照或日志。

## 仓库文件

```text
codex-pulse/
├── README.md
├── Package.swift
├── Sources/
│   ├── CodexPulseCore/
│   └── CodexPulseProbe/
├── Tests/
│   └── CodexPulseCoreTests/
├── docs/
│   ├── design-plan.md
│   └── phase-1-verification.md
├── .gitignore
├── .gitattributes
└── .editorconfig
```

完整设计、技术约束和原工期估算见 [设计方案](docs/design-plan.md)。新增自动请求功能的工期尚未重新估算。

## 上传 GitHub

本地仓库使用 `main` 分支，并包含中文初始提交。请先在 GitHub 创建空的 `codex-pulse` 仓库，再在本地执行：

```bash
cd /Users/j/github_repo/codex-pulse
git remote add origin https://github.com/<你的用户名>/codex-pulse.git
git push -u origin main
```

将示例中的用户名替换为你的 GitHub 用户名。当前仓库没有配置 remote，也没有进行推送。
