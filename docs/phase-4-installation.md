# 第四阶段：安装、登录时启动与 DMG

## 实现范围

2026-10-02 完成应用安装、原生登录启动开关和本地 DMG 打包。用户已确认五小时周期验证通过，本次不再重复观察该周期。调度和账号目录沿用既有实现，不新增认证或后台进程。

安装位置为 `/Applications/Codex Pulse.app`，版本 0.5.1。启动正式副本前退出原开发目录副本，两个版本共享原 `Application Support/CodexPulse` 下的独立账号和检查点，安装包不包含这些数据。

## 安装和更新

```bash
cd /Users/j/github_repo/codex-pulse
./scripts/install-app.sh
open "/Applications/Codex Pulse.app"
```

脚本先构建、复制并验证签名，再替换安装位置。已有目标必须属于 `dev.codexpulse.mac`，符号链接和其他应用不会被覆盖。运行中的已安装应用必须先退出；替换步骤失败时恢复旧应用。脚本仅处理应用包，不删除账号数据，也不更改官方 `~/.codex`。

开发时仍可使用 `scripts/build-app.sh` 在 `.build/app` 生成应用。开发目录副本的登录启动开关不可用，避免系统记录临时路径。正式副本和开发副本不要同时运行。

## 登录时启动

菜单栏新增“登录时启动”开关，调用 [Apple `SMAppService.mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp) 的注册和注销方法，不写自制 LaunchAgent 或使用 AppleScript。

正式安装后的首次运行默认请求开启，由应用启动入口处理，不需要先打开菜单栏。一次性初始化标记 `loginItemDefaultApplied` 保存在本应用的 UserDefaults，只记录默认设置已应用，不代表系统已经启用。用户之后在开关或系统设置中关闭时，不会被重启或升级重新打开；开发目录副本不消耗首次初始化标记。首次注册失败会显示真实错误，不反复自动尝试，用户可通过开关重试。

开关从系统状态读取，不将本地偏好值当作启用成功；重复设置当前状态不重复注册。关闭调用异步注销，处理中禁用开关。注册或注销失败时保留系统实际状态并显示脱敏错误代码。

系统返回 `requiresApproval` 时，开关代表已经提出注册，但旁边明确提示等待系统批准，并提供“前往系统设置”。在系统中修改登录项后，重新打开面板或应用再次激活时重新读取状态。登录启动只在用户登录后运行应用，不在未登录时运行，也不唤醒休眠的 Mac。

## DMG 安装包

```bash
./scripts/package-dmg.sh
```

生成 `.build/dist/Codex-Pulse-<版本>.dmg`，当前为 `Codex-Pulse-0.5.1.dmg`。只打包应用和指向 `/Applications` 的拖放入口。打开 DMG，将应用拖入 Applications；更新前先退出旧版本，再替换应用。

输出使用压缩 UDZO 格式，临时目录清理后只保留成品。DMG、应用和编译输出位于已被 Git 忽略的 `.build`，源码仓库不保存二进制或账号凭据。

## 验证记录

- `./scripts/test.sh`：核心 47 项、菜单栏及登录启动状态模型 26 项，共 73 项通过；默认开启相关的 11 项登录启动测试单独再次通过。
- 新增验证真实系统状态驱动开关、外部修改后刷新、等待批准、注册和注销失败保持真实状态及错误脱敏、开发副本不注册、系统状态未改变时不伪造成功。
- 安装脚本和 DMG 脚本通过 shell 语法检查；应用构建、Info.plist 校验和本地签名校验通过。
- 已安装到 `/Applications/Codex Pulse.app` 并启动，运行进程路径确认属于正式副本；已有两个 Plus 检查点更新，确认恢复原账号调度。
- DMG 校验和通过；只读挂载后验证应用签名、版本信息、Applications 链接及可执行文件与已安装副本一致，验证后已卸载镜像。
- 桌面工具读取该菜单栏应用超时，系统登录项检查工具也超时。已请求用户在真实界面确认开关结果；注册及注销的应用调用由模型测试覆盖，实际注销登录后自动启动尚未验证。本次不为此退出用户会话。

2026-10-02 默认开启调整：新增首次正式运行启用、重复启动去重、手动关闭及系统关闭后不重启注册、等待批准、已启用状态不重复注册、开发副本不消耗初始化、初次失败显示错误及手动重试验证。0.5.1 已更新安装并启动，首次运行初始化标记从缺失变为已应用；此标记仅证明启动入口执行，不代替系统登录项真实状态验证。DMG 同步更新并校验，实际注销再登录验证仍未执行。

## 本次修改文件

- `Sources/CodexPulseApp/CodexPulseApp.swift`（默认设置调整新增）
- `Sources/CodexPulseUI/LoginItemModel.swift`
- `Sources/CodexPulseUI/MenuBarPanel.swift`
- `Resources/Info.plist`
- `Tests/CodexPulseUITests/LoginItemModelTests.swift`
- `scripts/install-app.sh`
- `scripts/package-dmg.sh`
- `README.md`
- `docs/design-plan.md`
- `docs/phase-3-menu-bar.md`
- `docs/phase-4-automatic-requests.md`
- `docs/phase-4-installation.md`
- 原方案 `/Users/j/Desktop/work/Codex多账号额度小组件推荐方案.md` 同步。

## 默认开启调整修改文件

- `Sources/CodexPulseApp/CodexPulseApp.swift`
- `Sources/CodexPulseUI/LoginItemModel.swift`
- `Sources/CodexPulseUI/MenuBarPanel.swift`
- `Resources/Info.plist`
- `Tests/CodexPulseUITests/LoginItemModelTests.swift`
- `README.md`
- `docs/design-plan.md`
- `docs/phase-4-installation.md`
- 原方案 `/Users/j/Desktop/work/Codex多账号额度小组件推荐方案.md` 同步。

## 适用范围与剩余项

当前应用和 DMG 使用本地 ad-hoc 签名，尚未使用 Developer ID 证书或公证；用于当前个人安装，不代表正式发布版本。系统是否允许运行登录项以其实际状态为准，更新本地签名的应用后如系统要求重新批准，可从开关及系统设置处理。跨周长期观察、额外分钟级额度查询和网络恢复监听不在本次范围。
