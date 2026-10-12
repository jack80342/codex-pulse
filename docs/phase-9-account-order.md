# 第九阶段：账号展示排序与管理标题点击（0.9.0）

日期：2026-10-12。版本 0.9.0，构建号 17；本次本机交付，尚未新增 GitHub Release。

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

## 本机签名与交付

最终版本 0.9.0（17）已安装到 `/Applications/Codex Pulse.app` 并启动，保留原账号数据。应用及 DMG 均获 Apple Accepted，两份日志 `issues:null`；严格签名、附加公证凭证、应用分发检查与 DMG 完整性通过。本机原 Gatekeeper 评估关闭，不据此声称默认 Gatekeeper 首次打开验收通过。

- 应用公证 ID：`a1b5b60f-c1f2-4ba9-a1fa-81438e8201dd`
- DMG 公证 ID：`dda94bd5-ad3e-489f-92ce-666e014aa6a5`
- 本地包：`.build/dist/notarized/Codex-Pulse-0.9.0.dmg`
- SHA-256：`567aca32d82137e7148f801474dcda7680eb756bc619e4cff98bbd154d6acd1a`
- 日志与中英文渲染：`.build/account-order-qa/`；最终公证工作目录 `.build/notarization.mqFWpd/`。

桌面工具首次读取已安装应用成功，识别三个原账号、拖动手柄和“管理账号”按钮；随后点击被状态变化保护拒绝，重新获取应用状态超时，因此未完成鼠标拖动及标题点击的自动验收。未通过其他输入工具绕过；需用户实际确认交互。尚未新增 GitHub Release。
