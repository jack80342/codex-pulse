# 第八阶段：应用图标（0.8.3）

## 实现

应用此前没有 `CFBundleIconFile` 和 ICNS 资源，系统显示默认应用图标。现新增浅色圆角底板、蓝色原创矢量心电波形，与菜单栏的波形主题及面板蓝色一致。菜单栏继续使用系统符号，应用图标使用自行绘制的路径。

- `Resources/AppIcon.icns` 包含 16、32、128、256、512 像素及各自 Retina 版本，共 10 个尺寸，最大 1024 像素。
- `Resources/Info.plist` 使用 `CFBundleIconFile=AppIcon`，版本 0.8.3、构建号 15。
- `scripts/build-app.sh` 将图标复制至应用 `Contents/Resources`，再签名。正式 DMG 使用同一应用包。
- 图形源码位于 `scripts/generate-app-icon.swift`，通过 AppKit 绘制并用 `iconutil` 生成 ICNS。重建命令：`swift scripts/generate-app-icon.swift`。

本次影响应用资源与打包，不改变额度、账号管理和自动请求调度行为。

## 验证（2026-10-02）

- 生成脚本运行通过，ICNS 回转为 iconset 后的 10 个 PNG 尺寸检查通过；大图及小图视觉检查通过。
- 打包脚本语法检查、release 构建通过；未为资源变更新增业务测试。
- 应用及 DMG 均获 Apple `Accepted`，两份日志的 `issues` 为 `null`；签名、公证凭证、应用分发与 DMG 完整性检查通过。
- 本机已安装并启动签名、公证版 0.8.3，并重新注册应用元数据。`NSWorkspace.icon(forFile:)` 成功解析安装后的应用图标，ICNS 提供 10 个表示，系统读取预览经视觉检查确认。
- 最终 DMG 挂载后，应用图标与仓库资源逐字节相同，应用签名、公证凭证及系统图标解析检查通过。

系统图标解析属于应用元数据校验，不等同于自动操作 Finder 窗口验收。当前 Mac 的 Gatekeeper 全局评估关闭，不以其 `spctl` 输出单独代替默认 Gatekeeper 首次打开验收。

- 应用提交 ID：`96c9851a-a5fd-4914-8aa1-1e7e1e22e13e`
- DMG 提交 ID：`4292ffa8-279a-4270-918b-acee95639eed`
- 安装包：`.build/dist/notarized/Codex-Pulse-0.8.3.dmg`（1,235,967 bytes）
- SHA-256：`9d656b44245fd775a2c6d3901436cd54df8841ef0db534a9cb8c7fe8b65d0e6c`
- 系统图标预览：`.build/app-icon-qa/installed-system-icon.png`

## 修改文件

- `Resources/AppIcon.icns`
- `Resources/Info.plist`
- `scripts/generate-app-icon.swift`
- `scripts/build-app.sh`
- `docs/design-plan.md`
- `docs/phase-8-app-icon.md`
- `/Users/j/Desktop/work/Codex多账号额度小组件推荐方案.md`（同步仓库方案）

2026-10-02：0.8.3 已发布为 GitHub 最新正式 Release，并完成下载包逐字节及公证凭证校验，见 [正式分发记录](official-distribution.md#最新发布0832026-10-02)。
