# 第四阶段：自动最小请求与恢复调度

## 本次实现范围

菜单栏应用启动时查询三个独立账号，对登录正常、普通使用许可明确允许、五小时及周额度均已知且未耗尽、五小时重置时间已知的账号发送一次真实最小请求。后续依据每个账号的服务端 `resetsAt` 安排一次定时查询，重新校验后再请求，不使用本机时间加五小时推测窗口。

复用既有 `ProbeSession.runProbe`：在专用空目录创建临时只读会话，要求只回复 OK，禁用工具，使用模型目录的默认模型、最低支持的推理档位及 Standard 速度。匹配实际 `turn/completed` 和 OK 回复后才视为完成，再读取请求后的额度。该请求会消耗真实额度，并不增加额度或累积未使用窗口。

以下为原版行为；0.9.1 的手动补试例外见文末。

同一账号当前窗口最多尝试一次。重复手动刷新、重启或重新打开面板不会重复请求；首次运行或尚未尝试的窗口发送一次。休眠越过多个窗口时只处理当前窗口，不补发历史请求。周额度耗尽、窗口未知、许可未知、认证或查询异常时停止对应账号，其他账号独立继续。Free 的窗口保持未知，因此跳过，而非硬编码禁止 Free。

菜单栏显示每个账号的自动请求状态及下一次计划时间。请求进行中禁用刷新，成功后的额度用于更新卡片。请求结果不确定时不立即重试；有已知重置时间则等待该时间后重新校验，无已知时间则暂停并等待用户刷新、重启或唤醒时重新读取。由于需要确认是否已有请求执行，恢复时新读到的当前窗口只用于等待，不直接补发。

## 检查点与并发边界

每个账号在现有账号租约内读取额度、写入检查点和执行请求。发送前必须成功落盘 `pending`，完成后写入 `completed`，失败写入 `incomplete`；不能将发送成功视为执行完成。检查点包含账号创建时间、身份摘要、尝试时间、下次重置时间和结果状态，不含用户名、邮箱或令牌。

```text
~/Library/Application Support/CodexPulse/
├── scheduling/<account-id>.json
└── verification/<account-id>/reports/automatic-latest.json
```

目录权限为 0700，检查点和报告为 0600。每个账号仅保留一个最新自动请求报告，历史手动验证报告仍保留。检查点损坏或路径不安全时停止该账号，不覆盖原文件、不发送请求；删除后重建相同 ID 时以新的创建时间隔离旧检查点。服务端身份在读取或发送前发生变化时停止请求。重复登录同一服务端身份的条目只允许首个条目参与调度。

`ProbeSession.runProbe` 新增可选 `expectedIdentity` 参数用于发送前再次校验；既有 CLI 调用默认值保持兼容。账号登记字段、CLI 查询行为及认证目录没有改变。

## 定时与睡眠恢复

状态模型按最早的有效账号重置时间创建一次性主 RunLoop 定时器。到期后查询全部账号，各自依据检查点决定是否请求，再计算下一次时间。Mac 将休眠时取消定时器；唤醒及系统时间变化时重新读取额度并恢复。正在执行请求时收到恢复事件，只合并为一次后续查询，不并行重复请求。

需要菜单栏应用保持运行、Mac 醒着且网络可用。应用退出或 Mac 休眠时不能请求，也不主动唤醒 Mac。网络或认证异常停止的账号可在“立即刷新”、重启或唤醒后重新校验。

## 验证记录

2026-10-01，macOS / Apple Silicon / Swift 6.4 / Codex CLI 0.158.0：

- `./scripts/test.sh`：核心 47 项、菜单栏状态模型 15 项，共 62 项通过。
- 新增验证启动及重复刷新去重、重启检查点恢复、跨多个错过窗口只发送一次、采用请求后服务端重置时间、未知及耗尽额度阻止请求、周额度耗尽后停止、请求超时中断且不立即重试、崩溃检查点、检查点损坏保护、账号租约互斥、身份变化、删除重建隔离、三账号及重复身份处理。
- 状态模型验证请求后额度更新、最早实际重置时间、睡眠取消和唤醒重新查询、忙时恢复事件合并、整体查询失败暂停。
- 独立运行状态模型并驱动主 RunLoop，真实一次性定时器触发后重新检查一次，进入睡眠状态后不再调度；此验证使用模拟账号，不发送模型请求。
- 真实三个账号联调：两个 Plus 各完成一次最小请求，模型目录返回默认 `gpt-6.1-sol`；Free 缺失两个窗口而跳过。服务端下一次五小时重置时间为北京时间 2026-10-02 00:12:06 和 04:46:08。时间是本次快照，后续以服务端新值为准。
- 再次运行同一真实流程，两个 Plus 恢复等待状态，最新请求报告哈希未变化，确认未重复发送模型请求。
- 应用构建、Info.plist 和本地签名校验通过。新版菜单栏应用已启动；启动后的两份报告仍未变化，复用检查点而不重复请求。
- 2026-10-02 用户确认已验证完整五小时周期；新增状态由模型测试覆盖，本次不重复周期验证。

## 本次修改文件

- `Sources/CodexPulseCore/AutomaticRequestService.swift`
- `Sources/CodexPulseCore/ProbeSession.swift`
- `Sources/CodexPulseUI/MenuBarModel.swift`
- `Sources/CodexPulseUI/MenuBarPanel.swift`
- `Sources/CodexPulseApp/CodexPulseApp.swift`
- `Resources/Info.plist`
- `Tests/CodexPulseCoreTests/AutomaticRequestTests.swift`
- `Tests/CodexPulseCoreTests/Fixtures/app-server.py`
- `Tests/CodexPulseUITests/MenuBarModelTests.swift`
- `README.md`
- `docs/design-plan.md`
- `docs/phase-3-menu-bar.md`
- `docs/phase-4-automatic-requests.md`
- 原方案 `/Users/j/Desktop/work/Codex多账号额度小组件推荐方案.md` 同步。

## 当前状态与使用边界

自动调度、安装、登录时启动及 DMG 打包已完成。0.7.1 已完成 Developer ID 签名、公证与正式发布，见[分发说明](official-distribution.md)。CLI 协议、模型目录及已授权的用户名资料接口变化可能影响使用。

检查点在请求前写入，因此在写入后、实际发送前崩溃时，可能保守地跳过一次窗口；这是避免结果未知时重复消耗额度的必要边界。查询失败或重置时间缺失不会推测下一次时间，需恢复条件后再校验。长时间关机、睡眠或断网会错过窗口，无法保证持续每五小时执行。

## 0.9.1：立即刷新后限次补试（2026-11-16）

后台仍每窗口最多尝试一次。用户点击“立即刷新”后先读额度，仅对本窗口未完成或结果未确认、窗口和用量许可已知且额度允许的账号补试一次；成功请求不补发，重复身份仍只允许原顺序首个合格条目。未尝试或已到期的新窗口按原流程发一次，不在同次刷新再补。

检查点 schemaVersion=1，增加可选 manualRetryUsed，旧文件缺失表示未补试。补试前在账号租约内原子保存 pending、manualRetryUsed=true，失败/超时/崩溃仍保留已用预算，连续点击和重启不再补，下一窗口重建预算。未知窗口不猜测，损坏检查点不覆盖；无已知重置时先采纳服务端未来重置，符合条件才补试。

只有面板刷新按钮（含 Cmd-R）启用 allowManualRetry=true；启动、定时器、唤醒、账号管理及普通 refresh 均默认 false。未新增轮询/网络恢复监听，也未修复无未来重置时间时不挂定时器的原有行为。没有新增 UI 说明或第三方依赖，仅增加已用补试的中英文状态。

风险：第一次超时请求可能实际已成功，补试仍可能额外消耗一次最小请求额度；这是用户授权的例外，不是无限重试。两个 Plus 等待完成通知超时的根因（网络/服务端/CLI 通知兼容）未在本次解决。

验证：121 项测试通过（Core 72、UI 49），覆盖失败后一次补试、pending 崩溃恢复、连续点击、成功不补、新窗口恢复预算、旧检查点、未知/耗尽窗口、重复身份及手动入口和启动/唤醒隔离。测试采用临时目录及本地 fixture，未补发真实请求。

修改文件：AutomaticRequestService.swift、中英文 Localizable.strings、MenuBarModel.swift、MenuBarPanel.swift、AutomaticRequestTests.swift、MenuBarModelTests.swift、Resources/Info.plist（0.9.1 / 19）、docs/design-plan.md 及本文件。

Release 构建通过。Apple 公证前置检查曾返回协议 403；用户本人接受协议后，服务恢复，应用和 DMG 均获 Accepted、issues:null，签名、附加票据、应用分发和 DMG 完整性验证通过。本机此前 Gatekeeper 评估关闭，不把 spctl 的 override=security disabled 当作默认 Gatekeeper 的首次启动验证。未为绕过该错误修改凭据/安全配置。

- 应用公证 ID：`58b1abe1-9578-4268-80f5-4d69689933e7`
- DMG 公证 ID：`f1023090-1ffb-4103-9218-eee4af450b97`
- 工作目录：`.build/notarization.XT792c/`
- 正式包：`.build/dist/notarized/Codex-Pulse-0.9.1.dmg`
- SHA-256：`91e4a62cfe2375c907b2532806d94d0da5773316b5051941c8406eaaa956c3be`

已通过暂存、严格签名和票据校验、失败回滚保护替换 `/Applications/Codex Pulse.app`，确认版本 0.9.1（19）并启动；替换期间账号列表及检查点摘要一致。启动仅执行后台规则，未自动使用手动补试预算。

证据位于 `.build/manual-retry-qa/`：tests.log、build.log、notarization-final.log、install.log。真实账号点击补试是否成功仍待用户实际验收，本轮没有自动执行手动补试、没有借测试消耗真实账号额度；2026-11-16 已按用户授权提交、推送并发布，见下方正式发布记录。原桌面方案路径 `/Users/j/Desktop/work/Codex多账号额度小组件推荐方案.md` 已不存在，未擅自重建，只更新仓库方案。

### 0.9.1 正式发布（2026-11-16）

[Codex Pulse 0.9.1](https://github.com/jack80342/codex-pulse/releases/tag/v0.9.1) 已于 2026-11-16 16:37:39（Asia/Shanghai）发布为 Latest 正式版。标签 v0.9.1 指向 `1db597b5f6a2098129413497b5f145b18ad54566`；版本 0.9.1、构建号 19。发布说明在 `docs/releases/v0.9.1.md`，保持简短中英文，不包含验证长段。

DMG（1,311,804 bytes）及 SHA256SUMS.txt 已上传。上传资产的大小、GitHub digest 与本地校验一致；发布后下载两文件逐字节比较通过，下载 DMG 的 stapler validate 通过；latest API 返回 v0.9.1（draft=false、prerelease=false）。证据保存在 `.build/release-0.9.1-qa/`。

内置浏览器连续超时后切换 GitHub CLI。用户完成标准设备授权，CLI 沿用 macOS 已有回环代理并使用 HTTP/1.1 后认证和发布成功；未修改系统代理、安全配置或提取浏览器 Cookie。草稿确认两资产 uploaded 后发布，未重复创建 Release、未覆盖公开标签。以上为分发验证，不替代真实账号的手动补试成功验收。
