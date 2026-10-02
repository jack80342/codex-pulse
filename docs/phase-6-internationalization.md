# 0.7.0：中英文界面

2026-10-02，版本 0.7.0 / build 10。

## 目标与语言选择

根据 macOS 首选语言自动选择中文或英文，无需让用户手动设置应用语言。启动时读取 `Locale.preferredLanguages`，从前到后选取第一个支持的语言；忽略其他语言，未包含中英文时默认英文。

- `zh`、`zh-CN`、`zh-Hans-CN`、`zh-Hant-TW` 等统一显示简体中文。
- `en`、`en-US`、`en-GB` 等统一显示英文。
- 语言在进程启动时确定，更改系统首选语言后需退出并重新打开应用。

## 调整范围与实现

界面文本原先分散在 SwiftUI 视图、UI 模型和核心服务的错误及调度消息中。增加共享 `PulseLocalization` 和中英文 `.strings` 资源，两种语言各 114 个键；视图、模型和服务统一从资源读取。日期、数字和额度进度条的辅助功能描述使用所选语言格式。英文账号数区分单数和复数。

覆盖额度页、管理账号、新增及取消登录、删除及重新登录确认区、空列表与 CLI 缺失引导、登录时启动的系统状态及错误、查询错误、用户名查询错误、重复身份提示及自动请求状态。

SwiftPM 声明默认英文并处理语言资源；应用 Info.plist 声明中英文。构建脚本将 Core 资源包复制到应用 `Contents/Resources` 后签名，安装和 DMG 复用该流程。已安装应用优先加载自身资源包，不依赖构建目录。

## 兼容性与数据

真实用户名、套餐名称、账号 ID 和已有别名不翻译。新建 GUI 条目的存储名称使用固定 UUID，另以可选字段 `usesGeneratedName` 标识系统生成的名称；未取得用户名时按当前语言显示“待登录账号”或“Pending account”及 ID 前八位。读取真实用户名后仍优先显示接口结果。

该标记默认缺失，旧 schema 1 列表可以直接读取，原调用方的初始化和添加接口通过默认参数继续兼容，未标记条目保持原名称，即使名称恰好等于 ID。通过开发者 CLI 重命名时清除生成标记，保留自定义名称。无需迁移已有条目或修改凭据目录。

本次没有调整登录、额度协议、窗口判断、检查点格式、去重、并发限制和自动请求调度。共享错误说明会随语言改变，枚举项及协议错误代码保持原值。开发者 CLI 帮助、命令名及历史验证报告正文没有整体翻译。

## 验证

- `swift build --product CodexPulseApp`、应用构建通过。
- `./scripts/test.sh`：99 项测试通过，核心 61、UI 38。
- 新增测试覆盖语言优先顺序、不支持语言与默认值、地区和简繁体变体、两种资源的键及格式参数一致性、英文资源无中文、百分号、账号数、用户名与错误代码插值、日期格式、临时名称显示与旧列表兼容、生成标记的持久化及重命名行为。原查询、账号管理、去重及窗口尺寸测试继续通过。
- 独立原生宿主使用演示数据，在测试进程参数中分别提供英文优先和中文优先的语言列表；没有更改 Mac 的全局语言偏好。两种语言各渲染额度页、管理页、删除确认、重新登录确认、空列表、CLI 缺失及六账号列表，共 14 个场景；检查文字完整显示、按钮布局和窗口内容高度。
- 测试宿主使用从正式构建产物复制的资源包，开发环境资源回退被测试桩禁止；全部场景确认从宿主应用自身 Resources 加载资源。显示窗口宽度为 390 个逻辑像素，长英文说明换行，确认区无需模态弹窗。

渲染检查只使用独立测试窗口，不等同于真实 MenuBarExtra 的点击操作；本次未重复真实浏览器登录或五小时周期验收，沿用用户已确认的原功能结果。源码测试及渲染文件保存在忽略目录 `.build/internationalization-qa`。

## 交付与风险

已安装并重新启动 `/Applications/Codex Pulse.app`，版本 0.7.0 / build 10。更新前确认三个原账号租约空闲，退出原应用；更新后账号列表文件摘要相同。应用签名、DMG 校验及只读挂载检查通过，包内版本、可执行文件和两种语言资源与安装版本一致，Applications 链接正确。安装包为 `.build/dist/Codex-Pulse-0.7.0.dmg`。语言资源与应用需一起分发；更改系统首选语言后重启应用生效。中文目前只提供简体文案。原有 app-server、内部只读资料接口兼容性与本地 ad-hoc 签名边界继续适用。

## 本次修改文件

- `Package.swift`
- `Resources/Info.plist`
- 新增 `Sources/CodexPulseCore/PulseLocalization.swift`
- 新增 `Sources/CodexPulseCore/Resources/en.lproj/Localizable.strings`
- 新增 `Sources/CodexPulseCore/Resources/zh-Hans.lproj/Localizable.strings`
- `Sources/CodexPulseCore/AccountProfileClient.swift`
- `Sources/CodexPulseCore/AccountStore.swift`
- `Sources/CodexPulseCore/AppServerClient.swift`
- `Sources/CodexPulseCore/AutomaticRequestService.swift`
- `Sources/CodexPulseCore/ProbeSession.swift`
- `Sources/CodexPulseUI/AccountManagementModel.swift`
- `Sources/CodexPulseUI/AccountManagementPanel.swift`
- `Sources/CodexPulseUI/LoginItemModel.swift`
- `Sources/CodexPulseUI/MenuBarModel.swift`
- `Sources/CodexPulseUI/MenuBarPanel.swift`
- 新增 `Tests/CodexPulseCoreTests/LocalizationTests.swift`
- `Tests/CodexPulseCoreTests/AccountTests.swift`
- `Tests/CodexPulseCoreTests/AutomaticRequestTests.swift`
- `Tests/CodexPulseUITests/AccountManagementTests.swift`
- `Tests/CodexPulseUITests/LoginItemModelTests.swift`
- `Tests/CodexPulseUITests/MenuBarModelTests.swift`
- `scripts/build-app.sh`
- `README.md`
- `README.zh-CN.md`
- `docs/design-plan.md`
- 新增本文档 `docs/phase-6-internationalization.md`
- 同步更新原方案 `/Users/j/Desktop/work/Codex多账号额度小组件推荐方案.md`。
