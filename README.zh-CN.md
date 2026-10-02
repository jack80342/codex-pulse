# Codex Pulse

[English](README.md) | 简体中文

Codex 多账号额度管理工具，提供 macOS 菜单栏额度监控和按服务端重置时间运行的自动最小请求。

仓库名：`codex-pulse`；应用显示名称：`Codex Pulse`；Swift 工程名称：`CodexPulse`。

## 当前状态

已实现协议验证、三账号管理命令行工具和第三阶段的原生菜单栏应用。菜单栏支持账号列表、五小时/周额度、服务端重置时间、手动刷新和错误状态。已接入启动请求、重置后自动请求、窗口去重和唤醒恢复；已提供安装脚本、登录时启动开关和 DMG 打包；iOS 功能仍为后续规划。账号标题动态显示资料接口返回的真实用户名，刷新时同步更新。

第一阶段协议验证已完成：独立 Plus 账号登录、真实额度读取和一次最小请求均成功。官方已明确新五小时窗口由上一窗口结束后的首条消息启动，无需等待额外窗口实验；原定重置后验证任务已取消。详细观测见 [第一阶段验证说明](docs/phase-1-verification.md)。仓库已配置 GitHub `origin`；按用户 2026-10-02 的最新要求，后续完成修改和验证后使用中文提交并自动推送。

## 第一阶段验证

需要 macOS 14 及以上、Swift 6 及以上和已安装的 Codex CLI。本次协议适配依据本机 Codex CLI 0.158.0 生成的 JSON Schema。

```bash
cd /Users/j/github_repo/codex-pulse
swift build
./scripts/test.sh
swift run codex-pulse-probe handshake
swift run codex-pulse-probe login
swift run codex-pulse-probe status
swift run codex-pulse-probe models
swift run codex-pulse-probe probe
```

`login` 打开浏览器，由用户完成验证账号登录；`probe` 发送一次真实模型请求，会消耗额度。可通过 `--model` 指定模型目录返回的模型，省略时使用目录默认模型，并选择其支持的最低推理档位及 Standard 速度。

首次请求完成后，程序输出报告的绝对路径。如需诊断重置后接口行为，可在报告记录的五小时重置时间到达后执行（非开发前置条件）：

```bash
swift run codex-pulse-probe verify-reset --report "<首次报告的绝对路径>"
```

重置后验证沿用原报告模型并核对账号身份。未到重置时间、额度许可未知或已耗尽时停止，不发送模型请求。更多步骤和判定边界见 [第一阶段验证说明](docs/phase-1-verification.md)。

## 菜单栏应用

安装到应用程序目录：

```bash
cd /Users/j/github_repo/codex-pulse
./scripts/install-app.sh
open "/Applications/Codex Pulse.app"
```

正式安装后的首次运行默认开启“登录时启动”，无需先打开菜单栏。开关读取系统真实状态；需要批准时点击“前往系统设置”。用户后续手动关闭或在系统设置中关闭后，重新运行和更新不会强制打开。开发目录副本不应用该默认设置，避免登录时启动错误副本。更新已安装应用前先退出它。

生成拖放安装包：

```bash
./scripts/package-dmg.sh
```

输出 `.build/dist/Codex-Pulse-<版本>.dmg`，打开后将应用拖到 Applications。安装包只有应用与 Applications 链接，不包含账号凭据；账号数据继续保存在原 Application Support 目录。详情见[安装与登录启动说明](docs/phase-4-installation.md)。本地 ad-hoc 签名适用于当前自用，尚未做 Developer ID 签名和公证。

仅用于开发目录运行：

```bash
cd /Users/j/github_repo/codex-pulse
./scripts/build-app.sh
open ".build/app/Codex Pulse.app"
```

应用启动时读取三个账号，点击菜单栏心电图图标查看结果，“立即刷新”重新并发查询。查询失败保留上次成功额度并以灰色及更新时间标记；服务端没有返回的窗口显示“未知”。启动时先查询额度，再对符合条件且本窗口未尝试过的账号发送一次真实最小请求；按各账号服务端五小时重置时间继续调度。“立即刷新”也重新检查调度，但不会在同一窗口重复请求。周额度耗尽或窗口未知时停止对应账号，重启及唤醒后恢复当前窗口，不补发错过的轮次。账号增删、登录和别名修改继续使用下面的命令行入口。用户名从经用户授权的只读内部资料接口获取；资料失败时保留最近名称并显示错误，额度查询独立处理。

本机使用 Command Line Tools 构建 SwiftUI 应用，生成本地 ad-hoc 签名的 `.app`。用户名接口限制见 [第三阶段说明](docs/phase-3-menu-bar.md)，自动调度、验证和失败恢复见 [第四阶段说明](docs/phase-4-automatic-requests.md)。

## 三账号管理

```bash
swift run codex-pulse accounts add --name "账号1"
swift run codex-pulse accounts list
swift run codex-pulse accounts login --id "<列表中的固定 ID>"
swift run codex-pulse accounts status
swift run codex-pulse accounts rename --id "<ID>" --name "工作账号"
swift run codex-pulse accounts remove --id "<ID>"
```

账号 ID 固定对应登录目录，别名可使用中文；最多三个账号。添加只登记条目，登录需要用户在浏览器完成。`status` 并发查询全部账号，单个失败会保留其他账号结果；同一个服务端账号被重复登录时会提示额度共享。以上命令不发送模型请求。

当前三个账号已完成登录和真实并发查询：账号1、账号3为 Plus，账号2为用户确认的 Free。Free 账号当前未返回五小时/周窗口，显示未知；自动调度根据服务端许可和窗口可用性决定是否请求，不按套餐名称伪造额度或时间。

`remove` 会删除所选账号的独立目录和凭据，保留历史验证报告；失败时保留待删除标记并可重试。已有 `probe-1` 可通过 `accounts add --id probe-1 --name "账号1"` 登记，直接使用其独立登录状态。详细流程及实际联调状态见 [第二阶段说明](docs/phase-2-account-management.md)。

## 第一版目标

- 集中展示三个账号的五小时额度、周额度、重置时间和最后更新时间。
- 提供菜单栏应用，统一负责账号登录、额度查询、展示和自动请求调度。
- 应用启动时，对满足额度条件的账号发送一次最小模型请求；无活动窗口时启动五小时窗口，已有窗口时不重新计时。
- 按服务端返回的五小时窗口重置时间调度后续请求；周额度耗尽时停止对应账号。
- 应用重启或电脑唤醒后重新查询并恢复调度，不补发错过的请求。

[官方说明](https://help.openai.com/en/articles/20001516-managing-usage-with-gpt-6-astra-in-work-and-codex)明确：上一五小时窗口结束后，首条 Work/Codex 消息启动下一窗口。额度查询不能视为窗口启动，最小请求自身也会消耗额度；实际调度以服务端重置时间为准。

## 开发顺序

1. 验证 Codex app-server 初始化、额度读取及最小模型请求完整执行（已完成）。
2. 实现三个账号的独立登录和账号管理（已完成，两 Plus 加一 Free，均已真实登录和并发查询）。
3. 实现菜单栏额度展示、手动刷新及错误状态（已实现；包含动态资料用户名）。
4. 自动请求调度、窗口去重、唤醒恢复、安装、登录时启动及 DMG 打包已实现；正式分发签名和公证待完成。
5. 完成三账号联调、异常处理及与日常 Codex App 并行使用验证。

后续阶段增加 CloudKit 私有数据库同步、iOS App 和 iPhone 小组件。

2026-10-02 用户确认已验证完整五小时周期，本次不重复观察；跨周长期验证仍待完成。

## 技术方向

- macOS 14 及以上，Swift 6 和 SwiftUI。
- 通过本机 Codex CLI 的 app-server 查询额度和管理独立账号。
- 以服务端返回的窗口时长和重置时间为准，不写死 primary、secondary 对应的窗口类型。
- 自动调度需主应用运行、Mac 处于唤醒状态且网络可用。

## 账号隔离

每个账号使用独立的 `CODEX_HOME`，计划保存于：

```text
~/Library/Application Support/CodexPulse/accounts/<account-id>/
```

调度检查点保存于 `Application Support/CodexPulse/scheduling/<account-id>.json`，最新自动请求报告位于 `verification/<account-id>/reports/automatic-latest.json`；均仅供本机使用，不保存令牌或原始响应。

主应用使用独立目录重新登录，不读取或修改日常 Codex App 的 `~/.codex` 认证和全局状态。账号令牌、Cookie 和认证文件不得进入 Git 仓库、导出额度数据或日志。

## 仓库文件

```text
codex-pulse/
├── README.md
├── README.zh-CN.md
├── Package.swift
├── Sources/
│   ├── CodexPulseCore/
│   ├── CodexPulseProbe/
│   ├── CodexPulseCLI/
│   ├── CodexPulseUI/
│   └── CodexPulseApp/
├── Tests/
│   ├── CodexPulseCoreTests/
│   └── CodexPulseUITests/
├── docs/
│   ├── design-plan.md
│   ├── phase-1-verification.md
│   ├── phase-2-account-management.md
│   ├── phase-3-menu-bar.md
│   ├── phase-4-automatic-requests.md
│   └── phase-4-installation.md
├── Resources/Info.plist
├── scripts/build-app.sh
├── scripts/install-app.sh
├── scripts/package-dmg.sh
├── scripts/test.sh
├── .gitignore
├── .gitattributes
└── .editorconfig
```

完整设计、技术约束和开发进度见 [设计方案](docs/design-plan.md)。新增自动请求功能的工期尚未重新估算。

## 上传 GitHub

本地仓库使用 `main` 分支和中文提交，已配置 `origin`。后续完成修改和验证后默认自动推送；需要手动同步时可使用：

```bash
cd /Users/j/github_repo/codex-pulse
git remote -v
git push -u origin main
```

用户明确要求暂不推送时，以该次指示为准。
