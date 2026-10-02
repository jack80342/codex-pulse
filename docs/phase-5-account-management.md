# 首次使用与应用内账号管理

2026-10-02，版本 0.6.0（build 7）。

## 目标及影响范围

取消原三个账号的数量限制，补齐已安装应用的首次使用及后续账号增删、登录重试。沿用原账号列表格式、固定 ID、独立 `CODEX_HOME`、账号租约、用户名资料接口和自动请求检查点。旧账号无需迁移或再次登录，原 CLI 调用方式继续可用。界面已去掉别名输入及登录启动开关下方的普通说明文字（系统批准入口和错误提示仍保留）；现有名称字段保留，未获取用户名时用于区分账号，新增条目由系统生成临时名称。

账号数量不设上限，查询与自动请求各最多三个工作任务，完成一个后继续下一个，结果仍按列表顺序显示。界面列表使用延迟布局，刷新清理缓存使用账号 ID 集合，避免随账号增长反复扫描列表。

## 用户流程

1. 单独安装 Codex CLI，并将 Codex Pulse 安装到 Applications。DMG 不带 Codex CLI 或开发者的账号凭据，使用者无需源码或 Swift。
2. 点击菜单栏图标，空列表显示“添加第一个账号”。CLI 已找到时点击直接打开浏览器登录；未找到时打开“管理账号”中的安装引导。
3. 应用自动检测 Codex CLI，不要求选择文件或设置路径。依次查找 Homebrew、绝对 PATH 目录、常见用户安装目录及 nvm/fnm 的 Node 版本目录；不运行登录 Shell、不读取启动脚本或递归扫描磁盘。缺失时显示安装说明，安装后点“重新检测”；返回前台和账号操作前也会检测。登录、查询、调度使用同一查找逻辑。所发现 CLI 的目录加入子进程 PATH，支持 npm CLI 查找同目录 Node 运行时。
4. 点击“添加账号”，无需填写别名。生成 UUID 和临时名称，登记独立条目并打开默认浏览器；确认目标 ChatGPT 账号再完成授权，最多等待 10 分钟。
5. 完成后重新查询真实用户名及额度，并恢复符合条件账号的自动最小请求调度；该请求会消耗额度，界面已说明。
6. 后续在同一入口继续新增、登录重试、重新登录或删除条目。

登录失败或取消保留条目供重试、删除，不把登记成功当作认证成功。登录等待在后台执行，取消关闭本次登录创建的 app-server，唤醒等待并释放租约。没有复制或触碰日常 Codex App 的认证文件。

“重新登录”需确认，会通过所选独立目录的 app-server 调用 `account/logout`，再重新授权。不会复用原来的“已登录直接返回”路径。失败或取消后可能需要再次登录。旧用户名和额度缓存在重新登录时清除，确认未登录后也不再显示旧额度。

“删除”需确认，仅删除条目及其独立目录中的本地登录凭据和 CLI 状态，保留历史验证报告和现有检查点；该条目立即移出界面及调度。不会删除 ChatGPT 服务端账号。目录清理失败沿用待删除标记和重试流程；账号忙时明确报错。

账号管理与菜单栏刷新互斥，管理期间暂停自动调度；完成后重新读取列表、资料、额度并按服务端时间重建调度。跨进程仍由原账号租约保护。浏览器登录等待期间其他账号的自动请求会暂缓，完成或取消后恢复；不补发错过的轮次。重复身份仍提示共享额度，只有首个符合条件条目自动请求。

## 接口兼容

- `AccountService.login` 新增有默认值的 `forceReauthentication` 和 `cancellation` 参数，旧调用方保持原行为。
- JSONL `request` 的参数允许 `nil`，仅用于 `account/logout` 的协议空参数；原字典参数调用兼容。
- 原 `AccountError.accountLimit` 枚举项保留以兼容调用方，账号存储不再抛出它。
- 列表 schema 版本、已有账号目录、权限、检查点及跨进程锁保持原格式。
- 应用无手动 CLI 路径设置；开发者 CLI 的原有 `--codex` 参数继续可用。

## 验证及边界

- `swift build` 及 `.app` 构建通过；安装到 `/Applications/Codex Pulse.app`，版本 0.6.0 / build 7。
- `./scripts/test.sh`：89 项测试通过（核心 55、UI 模型 34）；最终界面调整后重新运行全部 34 项 UI 模型测试通过。
- 覆盖六个账号的持久化及界面操作、七个账号的额度查询结果排序和失败隔离、六个账号的自动请求及每窗口去重、登录取消及并发关闭等待进程退出后释放租约、强制重新登录、CLI 缺失、自动发现 PATH 和 Node 版本目录、所发现 CLI 的运行时 PATH、符号链接可执行文件、账号删除失败与调度恢复、退出登录清除旧缓存。
- 独立临时宿主渲染检查空列表、新账号引导和六账号管理列表；确认添加、登录、删除和重新检测按钮显示正常。该检查只使用演示数据，不等同于真实弹窗或浏览器登录操作。
- 本机 CLI 已更新至 0.159.3（`codex --version` 核对），现有三个真实账号只读查询通过，仍为 Plus / Free / Plus，Free 缺失窗口保持未知；查询未发送模型请求。
- 已安装应用已重新启动，更新前后原账号列表文件摘要相同。
- 最终 DMG 的校验、签名和只读挂载内容检查通过；包内应用版本为 0.6.0 / build 7，可执行文件与安装版本一致。

测试使用独立临时目录和本地 JSONL 模拟服务，不对用户现有账号执行退出、删除或额外模型请求。真实浏览器授权和确认弹窗交互仍需人工验收；现有三个真实账号继续用于只读查询验证。完整五小时周期沿用用户已经确认的结果，跨周长期稳定性仍待观察。

当前依赖已适配的 Codex CLI 协议及经授权的内部只读资料接口，CLI 或资料接口升级可能需要适配。签名仍为本地 ad-hoc，尚未完成 Developer ID 签名与公证。

## 0.6.1：管理页窗口高度修复

实际验收截图显示，展开账号管理后窗口保留额度页的高度，较短的管理内容居中，上下出现空白。入口文案已简化为“管理账号”。根视图按内容高度布局，并通过附着在面板上的原生视图调用 [`NSWindow.setContentSize`](https://developer.apple.com/documentation/appkit/nswindow/setcontentsize(_:)) 同步所属窗口尺寸；更新在当前布局后合并执行，保持窗口顶部位置，不查找或调整其他窗口。

- 全部 92 项测试通过（核心 55、UI 37）；新增三项原生窗口回归测试，覆盖反复缩放、所属窗口隔离及顶部位置、挂入窗口前的更新合并、无效尺寸和移出窗口后的处理。
- 使用演示数据在不自动调整大小的原生宿主中复现旧高度保留，检查空列表、三个和六个账号，连续展开 / 收起 / 展开均通过。三个账号的管理页窗口从额度页的 675 缩为 398 个逻辑像素，六个账号的管理页为 475；截图未出现上下空白。
- `swift build --product CodexPulseApp`、应用构建、安装和 DMG 打包通过；版本 0.6.1 / build 8。包内签名、校验、版本及可执行文件与安装版本一致。
- 更新前确认现有账号租约空闲后退出应用，安装后重新启动；原账号列表摘要未改变。

上述宿主检查不等同于真实 MenuBarExtra 的交互验收。安装版本的展开 / 收起效果仍需用户确认，新增、取消、删除、真实浏览器登录及重复身份提示的实际验收继续待完成。

本次修复文件：`Sources/CodexPulseUI/MenuBarPanel.swift`、新增 `Sources/CodexPulseUI/MenuBarWindowSizer.swift`、新增 `Tests/CodexPulseUITests/MenuBarWindowSizeTests.swift`、`Resources/Info.plist`、`docs/design-plan.md`、本文档，以及同步更新的原方案 `/Users/j/Desktop/work/Codex多账号额度小组件推荐方案.md`。

## 0.6.2：确认操作留在管理面板内

用户实际反馈：删除弹窗可显示，但点击“取消”或“删除”后菜单栏面板消失，操作不能正常完成。检查现有流程，删除仅在确认回调中执行；反馈后核对原三个账号条目仍完整保留。将这条失效的 SwiftUI `.alert` 交互路径替换为管理面板内的确认区，删除与重新登录共用相同处理方式。

取消只清除待确认状态并返回账号列表；确认前不会退出登录或删除条目，确认后仍调用原服务处理所选固定 ID。确认期间禁止新增及切换目标条目，取消始终可用，确认按钮在账号操作或刷新时暂停。保留原有错误处理、目录删除范围和后台调度行为。

- 全部 92 项测试通过（核心 55、UI 37），应用编译、构建、安装和打包通过。
- 独立宿主以演示数据渲染删除和重新登录确认区，标题、说明及两个按钮完整显示；尺寸均为 390 × 405 个逻辑像素，窗口随内容调整。此检查没有执行确认按钮，也没有操作真实账号。
- 已安装并重新启动 0.6.2 / build 9，关闭旧模态弹窗；原账号列表摘要未改变。DMG 的校验、签名、版本及可执行文件与安装版本一致。

真实 MenuBarExtra 的点击行为仍需用户确认。先在原账号的删除确认区仅点“取消”，确认返回列表；随后用临时条目验收取消登录及确认删除。浏览器登录、重复身份提示等剩余实际验收仍未完成。

本次修复文件：`Sources/CodexPulseUI/AccountManagementPanel.swift`、`Resources/Info.plist`、`docs/design-plan.md`、本文档，以及同步更新的原方案 `/Users/j/Desktop/work/Codex多账号额度小组件推荐方案.md`。

## 本次修改文件

- `Sources/CodexPulseCore/AccountStore.swift`
- `Sources/CodexPulseCore/AccountService.swift`
- `Sources/CodexPulseCore/AppServerClient.swift`
- `Sources/CodexPulseCore/AutomaticRequestService.swift`
- `Sources/CodexPulseCore/CodexExecutable.swift`
- `Sources/CodexPulseCore/LoginCancellation.swift`
- `Sources/CodexPulseUI/AccountManagementModel.swift`
- `Sources/CodexPulseUI/AccountManagementPanel.swift`
- `Sources/CodexPulseUI/MenuBarModel.swift`
- `Sources/CodexPulseUI/MenuBarPanel.swift`
- `Sources/CodexPulseApp/CodexPulseApp.swift`
- `Sources/CodexPulseCLI/main.swift`
- `Resources/Info.plist`
- `Tests/CodexPulseCoreTests/AccountTests.swift`
- `Tests/CodexPulseCoreTests/AccountServiceTests.swift`
- `Tests/CodexPulseCoreTests/AutomaticRequestTests.swift`
- `Tests/CodexPulseCoreTests/Fixtures/app-server.py`
- `Tests/CodexPulseCoreTests/ProtocolTests.swift`
- `Tests/CodexPulseUITests/AccountManagementTests.swift`
- `Tests/CodexPulseUITests/MenuBarModelTests.swift`
- `README.md`
- `README.zh-CN.md`
- `docs/design-plan.md`
- `docs/phase-2-account-management.md`
- `docs/phase-3-menu-bar.md`
- `docs/phase-5-account-management.md`
- 原方案 `/Users/j/Desktop/work/Codex多账号额度小组件推荐方案.md` 同步更新。
