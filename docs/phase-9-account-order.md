# 第九阶段：账号展示排序与管理标题点击（0.9.0）

日期：2026-10-12。当前版本 0.9.0，构建号 18；2026-10-12 完成本机交付，2026-10-13 已正式发布 GitHub Release。

## 行为与兼容

- 管理页账号左侧手柄拖动排序；上/下半行选择插入前/后，显示插入线。松手保存后，管理页与额度卡片立即使用相同顺序，退出重启保留。
- 仅保存 `account-list.json` 的可选 `displayOrder`，schemaVersion 仍为 1；旧配置默认原顺序，新增排末尾，删除保持其余相对顺序。
- 原 `accounts` 数组保持不变，查询/自动请求仍使用原顺序，重复账号主条目选择、凭据目录和检查点不变。
- 写入在现有文件锁下校验全量 UUID 集合，防止与其他进程的新增/删除冲突；失败不改变当前展示并提示错误。
- 登录、删除、刷新、确认区期间不能排序。排序复用管理互斥，结束后恢复原定时器；本身不触发查询/模型请求，确已到期或待恢复时按原流程处理。
- 管理标题改为整行 plain Button，箭头、文字及行内空白都可展开/收起；内部操作按钮独立。

## 验证

115 项测试通过（Core 68、UI 47）。新增覆盖旧配置、持久化与重新读取、新增/删除、过期/重复/非法 ID 拒绝、上下/首尾插入、保存失败、登录互斥、排序不查询/不请求、刷新与重新创建界面后保留顺序、自动调度输入保持原顺序。构建通过，中英文原生宿主管理列表渲染检查通过。

原生宿主使用演示数据；拖动鼠标及真实菜单栏标题点击不应仅依据渲染或模型测试认定实测通过。测试未读写真实账号凭据、未删除原账号。

## 修改文件

- `Sources/CodexPulseCore/AccountStore.swift`
- `Sources/CodexPulseCore/Resources/en.lproj/Localizable.strings`
- `Sources/CodexPulseCore/Resources/zh-Hans.lproj/Localizable.strings`
- `Sources/CodexPulseUI/AccountManagementModel.swift`
- `Sources/CodexPulseUI/AccountManagementPanel.swift`
- `Sources/CodexPulseUI/MenuBarModel.swift`
- `Sources/CodexPulseUI/MenuBarPanel.swift`
- `Tests/CodexPulseCoreTests/AccountTests.swift`
- `Tests/CodexPulseUITests/AccountManagementTests.swift`
- `Resources/Info.plist`
- `docs/design-plan.md`、本文件、桌面原方案 MD。

## 首次本机签名与交付（构建 17，已由下方修复版替换）

最终版本 0.9.0（17）已安装到 `/Applications/Codex Pulse.app` 并启动，保留原账号数据。应用及 DMG 均获 Apple Accepted，两份日志 `issues:null`；严格签名、附加公证凭证、应用分发检查与 DMG 完整性通过。本机原 Gatekeeper 评估关闭，不据此声称默认 Gatekeeper 首次打开验收通过。

- 应用公证 ID：`a1b5b60f-c1f2-4ba9-a1fa-81438e8201dd`
- DMG 公证 ID：`dda94bd5-ad3e-489f-92ce-666e014aa6a5`
- 本地包：`.build/dist/notarized/Codex-Pulse-0.9.0.dmg`
- SHA-256：`567aca32d82137e7148f801474dcda7680eb756bc619e4cff98bbd154d6acd1a`
- 日志与中英文渲染：`.build/account-order-qa/`；最终公证工作目录 `.build/notarization.mqFWpd/`。

桌面工具首次读取已安装应用成功，识别三个原账号、拖动手柄和“管理账号”按钮；随后点击被状态变化保护拒绝，重新获取应用状态超时，因此未完成鼠标拖动及标题点击的自动验收。未通过其他输入工具绕过；构建 18 的用户实际确认见下方修复记录。尚未新增 GitHub Release。

## 拖动无效反馈与修复（2026-10-12）

用户反馈构建 17 拖动无效。旧实现仅手柄启动系统 NSItemProvider/DropDelegate 拖放，账号名称不能拖动；真实菜单栏拖放回调未成功验收。改用面板内部 DragGesture，覆盖左侧手柄及账号名称区域，采用同一命名坐标系获取行位置，按鼠标纵坐标显示插入线并在松手后保存。移除系统拖放类型/会话依赖；右侧登录/删除按钮仍独立，存储和调度不变。标题整行展开/收起继续保留。

修复版 0.9.0（18），116 项测试通过（Core 68、UI 48），新增覆盖行坐标、跨行/间隙和首尾插入计算。此前模型测试通过没有证明真实鼠标拖放可用。2026-10-12 用户已在修复版实际确认“拖动和标题点击都正常”，拖动排序及管理标题展开/收起验收通过；未据此扩大为重启保留顺序或另一台 Mac 的用户验收。

修复版应用及 DMG 已再次签名、公证（Accepted，issues:null）、附加票据并验证；已安装并启动 0.9.0（18），保留账号数据。本地包仍未发布 GitHub Release。

- 应用公证 ID：`0950d67e-c73f-4302-9020-f306d698dc08`
- DMG 公证 ID：`05c6a025-dcbb-4db0-a486-2c2097e67fef`
- 最终工作目录：`.build/notarization.fRltUy/`
- 最终 DMG SHA-256：`c69e43a470156cc7d18c85c181a803f545f234bebecf79a23fa9123aca8dd4df`
- 最终测试/安装日志：`.build/account-order-qa/tests-local-drag.log`、`install-local-drag.log`；渲染 `zh-local-drag.png`、`en-local-drag.png`。

## 正式发布（2026-10-13）

用户在上传后的 GitHub 草稿页面完成发布。[v0.9.0](https://github.com/jack80342/codex-pulse/releases/tag/v0.9.0) 已核对为 Latest 正式版本，公开 API 确认 draft=false、prerelease=false、发布时刻为 2026-10-13 11:11:14（Asia/Shanghai）。标签解引用提交 `fa98b9e568a38f46c608980201edce371df743a4`，安装包版本 0.9.0（18）。

公开资产为 `Codex-Pulse-0.9.0.dmg`（1,306,902 bytes）与 `SHA256SUMS.txt`。GitHub 资产摘要与本地 SHA-256 相同，校验文件下载后与本地逐字节一致，线上中英文说明与 `docs/releases/v0.9.0.md` 一致；latest API 返回 v0.9.0。内部测试与验收记录保留于本文件，Release 说明不包含验证长段。

本轮重新验证本地 DMG 及其中应用的严格签名、公证票据和版本，无认证文件或账号列表打包；不重建已验收包、不移动发布标签。本机关闭 Gatekeeper、未在另一台默认设置 Mac 首次启动的既有验证边界继续保留。

发布后 DMG 下载首次超时、一次续传连接被重置；随后续传成功，完整下载包与本地正式包逐字节相同，下载包的附加公证票据验证通过。该网络问题未影响正式发布。

证据：`.build/release-0.9.0-qa/` 保存公开 API 响应、下载资产和校验文件。
