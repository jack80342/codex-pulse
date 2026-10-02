# 第七阶段：手动检查更新（0.8.0）

## 行为

- 标题右上角“⋯ / 更多选项”菜单提供“检查更新 / Check for Updates”及“退出 / Quit”；底部只保留“立即刷新”和上次查询时间，更新结果按需显示。仅在用户点击检查更新时请求 GitHub。
- 查询 `GET https://api.github.com/repos/jack80342/codex-pulse/releases/latest`，不携带 Codex 登录凭据、Cookie 或认证信息。
- 按三个数字段比较版本，例如 `0.7.10` 大于 `0.7.9`；不推荐草稿、预发布版本或降级。
- 发现新版时显示版本号和“查看更新”。正式 Release 中存在已上传、非空且名称匹配的 DMG 时，另显示“下载安装包”；入口由浏览器打开，安装由用户完成。
- 无新版时显示当前版本已是最新。网络失败、超时、HTTP 错误及 GitHub 匿名请求限流单独提示，允许重新检查。
- 检查期间禁用按钮，关闭再打开面板保留本次状态；重启应用不自动检查。
- 检查更新独立于额度查询及调度，不消耗 Codex 额度。

## 验证与交付

2026-10-02：109 项自动化测试通过（Core 66、UI 43），release 构建通过。更新相关测试覆盖数字版本比较、错误响应、草稿和预发布过滤、安装包缺失、外部链接拒绝、失败后重试及并发点击去重。中英文新版提示及中文限流状态的原生宿主渲染检查通过；宿主使用演示数据，不等同于实际菜单栏点击验收。

本机真实接口请求收到 HTTP 403，响应明确注明 `X-RateLimit-Remaining: 0`；真实网络查询的成功路径暂受 GitHub 匿名请求限流影响，失败提示已验证。桌面工具检查时 Mac 处于锁屏状态，未完成真实菜单栏按钮交互验收。

0.8.0（构建号 12）应用及 DMG 均获 Apple `Accepted`，公证凭证附加与验证、严格签名、应用分发检查及 DMG 完整性检查通过。最后一份 DMG 公证日志下载因系统无法读取 `codex-pulse-notary` 钥匙串配置而失败；提交结果与公证凭证均已验证，未重复提交。当前 Mac 的 Gatekeeper 全局评估关闭，其 `spctl` 结果不替代另一台默认配置机器的首次启动验收。

- 应用提交 ID：`2f0c8e18-8685-45ba-9937-e31d78830024`
- DMG 提交 ID：`d0ddfc28-aba3-404e-a7bf-f2f053947436`
- 本地安装包：`.build/dist/notarized/Codex-Pulse-0.8.0.dmg`（822,309 bytes）
- SHA-256：`5f738d116afabe5206982598d27ebc3f9f29e867d6782bd77a71cf98394a4b68`

本机 `/Applications/Codex Pulse.app` 已替换为签名、公证版 0.8.0 并启动。既有 GitHub 0.7.1 Release 保留，本次未创建新的 Release。

## 0.8.1 布局调整（2026-10-02）

按用户确认的方案，将“检查更新”和“退出”移入标题右上角的“⋯”菜单，底部保留“立即刷新”与查询完成时间，更新结果仍按需显示。增加中英文“更多选项”提示及辅助功能名称，检查更新期间在标题区域显示进度并禁用重复查询。额度和账号管理调用链保持原有行为。

109 项现有测试通过，release 构建及中英文界面渲染检查通过。实际更新查询已恢复，取得 GitHub 当前正式版本 `0.7.1`、发布页面及 DMG 下载链接。桌面工具读取已安装应用时超时，尚未自动完成实际菜单点击验收。

0.8.1（构建号 13）应用及 DMG 均获 Apple `Accepted`，公证日志下载、凭证附加与验证、签名及分发检查、DMG 完整性检查通过；已安装并启动本机签名、公证版应用。

- 应用提交 ID：`e3572691-95a5-419f-b3fe-079baeb8c10b`
- DMG 提交 ID：`413a80db-657d-4082-8082-279b2e5a1f43`
- 本地安装包：`.build/dist/notarized/Codex-Pulse-0.8.1.dmg`（830,641 bytes）
- SHA-256：`18b154e84273d846f4726808b9377141bf6a0650e07c7ef64d30e13edfeba028`

本次修改文件：

- `Sources/CodexPulseUI/MenuBarPanel.swift`
- `Sources/CodexPulseCore/Resources/en.lproj/Localizable.strings`
- `Sources/CodexPulseCore/Resources/zh-Hans.lproj/Localizable.strings`
- `Resources/Info.plist`
- `docs/design-plan.md`
- `docs/phase-7-update-check.md`
- `/Users/j/Desktop/work/Codex多账号额度小组件推荐方案.md`（与仓库方案同步）

## 0.8.0 修改文件

- `Sources/CodexPulseCore/AppUpdateClient.swift`
- `Sources/CodexPulseUI/AppUpdateModel.swift`
- `Sources/CodexPulseUI/MenuBarPanel.swift`
- `Sources/CodexPulseApp/CodexPulseApp.swift`
- `Sources/CodexPulseCore/Resources/en.lproj/Localizable.strings`
- `Sources/CodexPulseCore/Resources/zh-Hans.lproj/Localizable.strings`
- `Tests/CodexPulseCoreTests/AppUpdateTests.swift`
- `Tests/CodexPulseUITests/AppUpdateModelTests.swift`
- `Resources/Info.plist`
- `README.md`、`README.zh-CN.md`
- `docs/design-plan.md`、桌面原方案文档（内容同步）
- `docs/official-distribution.md`
- `docs/phase-2-account-management.md`
- `docs/phase-3-menu-bar.md`
- `docs/phase-4-automatic-requests.md`
- `docs/phase-4-installation.md`
- `docs/phase-5-account-management.md`
- `docs/phase-7-update-check.md`

上述方案文档同时移除了用户取消的跨端同步、移动端、小组件及七项扩展开发目标。现有额度展示、账号管理和自动请求逻辑未作代码变更。
