# Codex Pulse（codex-pulse）多账号额度菜单栏应用方案

更新时间：2026-10-02

- Git 仓库名：`codex-pulse`
- 应用显示名称：`Codex Pulse`
- Swift 工程及主应用名称：`CodexPulse`
- 本地仓库目录：`/Users/j/github_repo/codex-pulse`
- 仓库内方案文档：`docs/design-plan.md`

## 1. 项目目标

开发一个 macOS 原生菜单栏应用，集中展示多个 Codex 账号（不设数量上限）的：

- 账号名称及套餐类型
- 当前额度已使用百分比
- 当前可用额度百分比
- 不同额度窗口及下次重置时间，包括当前的 5 小时额度和周额度
- Credits 余额及可用重置次数（接口返回时展示）
- 数据更新时间、登录失效和查询异常状态
- 中文、英文界面，启动时按 macOS 首选语言顺序自动选择

该工具定位为个人本地工具，不依赖自建服务器，不抓取网页，不影响日常使用的 Codex App。

### 1.1 第一版新增目标：自动触发 5 小时额度窗口

先采用简单流程：应用打开时，对所有已添加账号中满足额度条件的账号分别发送一次最小模型请求，无活动窗口时启动各自的 5 小时额度窗口，已有窗口时不重新计时；之后在每个窗口重置后自动再次请求，启动下一轮窗口，直到对应账号的周额度耗尽。

具体流程：

1. 应用启动时，先查询所有已添加账号的额度；仅对周额度未耗尽、5 小时额度可用且登录正常的账号发送一次最小模型请求，例如“只回复 OK”。
2. 请求完成后，重新调用 `account/rateLimits/read`，记录各账号实际返回的窗口状态和 `resetsAt`。
3. 后续请求以约每 5 小时一次为目标，实际按各账号服务端返回的 5 小时窗口重置时间调度；到期后先查询额度，满足条件再发送一次最小模型请求，并重新读取下一次重置时间。
4. 某账号周额度耗尽时，停止该账号的自动模型请求，其他账号继续独立运行。
5. 应用重启或电脑唤醒时，重新查询额度后恢复调度，不补发休眠或退出期间错过的请求，避免集中消耗额度。已尝试的当前窗口不再请求，首次安装或未尝试的当前窗口才发送一次；结果不确定时同样不立即重试。

实现及验收边界：

- 额度查询与模型请求是两种不同操作。`account/rateLimits/read` 用于查询额度，不能将查询成功视为已启动 5 小时窗口。
- 官方说明已明确：上一 5 小时窗口结束后，首条 Work/Codex 消息启动下一窗口（2026-10-01 核对）。无需通过额外模型请求重复验证官方规则；第一阶段只验证登录、额度接口及最小请求完整执行，实际调度和展示以服务端返回的重置时间为准。
- 最小模型请求本身会消耗额度；该功能目标是尽早启动可用窗口，不承诺增加额度或累积未使用窗口。
- 模型请求使用各账号独立的 ChatGPT 登录状态，在专用空工作目录和独立会话中执行，不读取用户项目、不执行命令、不修改文件。
- 一个账号的查询失败、请求失败或认证失效不得影响其他账号；周额度缺失或查询异常时，不得推断为仍有额度并继续发送模型请求。
- 定时请求由 macOS 主应用负责，需应用后台运行、电脑处于唤醒状态且网络可用；iOS 端只展示状态。

参考：[Codex App Server 额度接口](https://learn.chatgpt.com/docs/app-server)、[套餐额度说明](https://learn.chatgpt.com/docs/pricing)、[官方五小时窗口规则](https://help.openai.com/en/articles/20001516-managing-usage-with-gpt-6-astra-in-work-and-codex)。

## 2. 可行性结论

技术上可行。

本机已安装 Codex CLI 0.158.0（2026-10-01 核对），提供本地 `app-server`，通过 JSONL 协议调用：

```text
account/rateLimits/read
```

可以取得以下信息：

- `planType`
- `usedPercent`
- `windowDurationMins`
- `resetsAt`
- `credits.balance`
- `rateLimitResetCredits`
- `rateLimitsByLimitId` 中的多个额度桶
- `primary`、`secondary` 等额度窗口

接口返回的是使用比例，不是固定消息数量。因此界面应显示“已用 X%”或“剩余约 X%”，不能承诺“还能发送多少条消息”。

当前额度可能同时存在 5 小时和周等多个窗口。5 小时不是“可连续使用 5 小时”的计时器，而是一个独立的滚动使用额度窗口；必须单独展示其使用比例和重置时间。当任一额度桶缺失该窗口时，界面不应补零或假设其存在。

## 3. 推荐产品形态

采用菜单栏常驻应用，集中管理所有已添加账号、查询和展示额度，并承担后续自动请求调度。

```text
CodexPulse 菜单栏应用
  ├── 管理所有已添加账号及独立登录
  ├── 调用 codex app-server 查询额度
  ├── 动态读取资料用户名
  ├── 展示额度、重置时间和异常状态
  └── 自动请求调度、窗口去重与唤醒恢复
```

认证、进程、网络和展示由同一个菜单栏应用负责。

### 3.1 界面国际化（0.7.0）

菜单栏应用支持简体中文和英文，启动时读取 macOS 首选语言列表，按顺序选择首个中英文条目；其他语言跳过，如果列表中没有中英文则使用英文。中文地区及简繁体变体统一使用简体中文，英文地区变体统一使用英文。更改系统首选语言后重新打开应用生效，无需新增应用内语言设置。

翻译范围包括额度页、账号管理、面板内确认区、空列表及 CLI 缺失引导、登录启动提示、查询错误和自动请求状态，日期和数字也使用所选语言格式。真实用户名、套餐名称、已有别名和账号 ID 保持原值。新建临时条目通过可选的生成名称标记显示“待登录账号”或“Pending account”，原有账号列表仍可直接读取，不迁移已有名称。

中英文各 114 个资源键，随应用和 DMG 打包；共享服务消息也使用同一语言资源。开发者 CLI 帮助及已有验证报告正文保留原内容。本次编译、99 项测试和两种语言各七种界面的独立原生宿主渲染检查通过；宿主检查使用演示数据，不等同于真实浏览器登录或菜单栏按钮交互验收。交付细节见 `docs/phase-6-internationalization.md`。

## 4. 技术选型

- Swift 6
- SwiftUI
- `Process`、`Pipe`：运行 Codex app-server 并进行 JSONL 通信
- `Codable`：解析协议响应
- `SMAppService`：可选的登录时启动
- Unified Logging：记录不含凭据的运行状态

最低支持版本建议为 macOS 14。

第一版不建议上架 Mac App Store，优先制作个人使用的签名应用或 DMG。

## 5. 多账号隔离方案

2026-10-01 用户确认的实际配置：账号1、账号3为 Plus，账号2为 Free。三个账号均保留独立登录和额度展示；账号2当前服务端未返回五小时及周窗口，显示未知，按现有额度校验停止模型请求。自动调度根据服务端实际返回的许可和窗口条件决定资格，不把 Free 套餐名称直接映射为 0% 或某个重置时间。

### 5.1 独立 CODEX_HOME

每个账号使用独立的 Codex 运行目录：

```text
~/Library/Application Support/CodexPulse/accounts/<account-id>/
```

例如：

```text
accounts/
├── account-1/
├── account-2/
└── account-3/
```

调用 CLI 时设置独立环境变量：

```bash
CODEX_HOME="<账号目录>" /opt/homebrew/bin/codex app-server
```

一个 app-server 实例只服务一个账号。所有已添加账号分别登录后，可以长期保持各自的认证状态。

### 5.2 不影响正式 Codex App 的强制约束

菜单栏应用不得执行以下操作：

- 不得把 `CODEX_HOME` 指向 `~/.codex`
- 不得读取、复制、写入或删除 `~/.codex/auth.json`
- 不得修改 `~/.codex/.codex-global-state.json`
- 不得复用官方 App 的会话和全局状态
- 不得在未设置独立 `CODEX_HOME` 时执行 `codex login` 或 `codex logout`
- 不得执行 `killall codex`、`killall ChatGPT` 等全局结束命令
- 不得结束非本应用创建的进程

即使本工具中的账号与 Codex App 当前账号相同，也应在本工具的独立目录内重新登录一次，不能直接复制官方 App 的认证文件。

目录关系如下：

```text
日常使用的 Codex App
└── ~/.codex

Codex Pulse 菜单栏应用
├── Application Support/CodexPulse/accounts/account-1
├── Application Support/CodexPulse/accounts/account-2
└── Application Support/CodexPulse/accounts/account-3
```

这样即使菜单栏应用崩溃、协议变化或登录过期，也不会破坏日常工作的 Codex App。

## 6. 账号添加与登录流程

2026-10-02 更新：取消原三个账号的数量上限。0.6.0 已补齐空列表“添加第一个账号”和常驻“管理账号”入口，支持直接添加并登录、失败重试、取消登录、重新登录及确认删除。账号添加无需别名输入，登录启动开关下方的普通说明已去掉，系统批准入口和错误提示保留。CLI 自动查找，不让用户选择可执行文件或设置路径；缺失时显示安装说明和重新检测入口。无需用户下载源码或安装 Swift 来管理账号，Codex CLI 仍需单独安装。

0.6.1 将入口简化为“管理账号”，并让菜单栏窗口在额度页与管理页切换时同步内容高度，保持顶部位置，避免沿用旧窗口高度而留下空白。

0.6.2 将删除与重新登录的模态弹窗替换为管理面板内的确认区，处理点击弹窗按钮后面板关闭、操作未完成的问题。取消仅返回列表，确认后才执行所选条目的操作；确认期间禁止新增和选择其他条目。用户已实际确认取消后面板保持打开并正常返回账号列表，临时条目的新增、取消登录及确认删除通过。重启后原三个账号仍已登录；真实浏览器登录和重复身份额度共享验证按用户要求跳过，用户确认重启后“登录时启动”仍开启且无错误，本次调整后的验收范围已完成。

新增条目采用 UUID 和原有独立目录，失败或取消保留可管理的条目。重新登录明确退出所选条目的本地认证再授权，不影响日常 Codex App。增删或登录完成后立即刷新用户名、额度和调度；管理操作期间暂停查询和调度，防止冲突。账号数量不限，但查询和自动请求各最多三个工作任务。重复身份提示共享额度，沿用每窗口去重规则。协议和模型测试已完成，真实浏览器及系统对话框交互仍需人工验收；详情见仓库内 `docs/phase-5-account-management.md`。

推荐使用 app-server 的登录流程，而不是打开 Terminal 执行命令：

1. 用户点击“添加账号”。
2. 应用创建 UUID 和独立账号目录。
3. 使用该目录启动 app-server。
4. 完成 `initialize`。
5. 调用 `account/login/start`。
6. 使用默认浏览器打开认证地址。
7. 监听 `account/login/completed`。
8. 调用 `account/read` 获取邮箱和套餐。
9. 显示只读资料接口动态返回的真实用户名；不要求填写别名，未完成登录时显示系统生成的临时名称。
10. 首次调用 `account/rateLimits/read` 并保存额度快照。

所有已添加账号首次登录时，浏览器中的 ChatGPT 网页登录状态可能需要切换。可以使用不同浏览器 Profile 或无痕窗口完成登录；该过程不应改变 Codex App 的账号状态。

## 7. Codex app-server 通信

### 7.1 启动方式

自动查找以下位置，不提供用户文件选择或路径配置：

```text
/opt/homebrew/bin/codex
/usr/local/bin/codex
绝对 PATH 目录
常见用户 bin / .local / npm / Volta 安装目录
nvm / fnm 已安装的 Node 版本目录
```

启动时为 `Process.environment` 注入当前账号的 `CODEX_HOME`。

### 7.2 协议初始化

向 app-server 标准输入发送 JSONL：

```json
{"id":"1","method":"initialize","params":{"clientInfo":{"name":"codex-pulse","title":"Codex Pulse","version":"1.0"}}}
{"method":"initialized","params":{}}
{"id":"2","method":"account/rateLimits/read"}
```

逐行读取标准输出，根据 `id` 匹配响应。标准错误单独读取，防止管道堵塞。

### 7.3 进程策略

推荐按需启动短期进程：

```text
启动 app-server
→ initialize
→ account/rateLimits/read
→ 解析响应
→ 正常关闭进程
```

每个账号设置 15 秒超时，账号数量不设上限，最多三个任务独立并发查询，单个失败保留其他账号结果。只保存自己启动的 `Process` 引用，结束时只终止对应进程。

不建议按账号数量常驻 app-server，因为额度只需要分钟级更新，短期进程更容易控制资源和故障边界。

## 8. 数据模型

```swift
struct CodexAccount: Codable, Identifiable {
    let id: UUID
    var alias: String
    var email: String?
    var codexHomePath: String
    var createdAt: Date
}

struct AccountQuota: Codable, Identifiable {
    let id: UUID
    let accountID: UUID
    let planType: String?
    let windows: [QuotaWindow]
    let creditBalanceRaw: String?
    let resetCreditCount: Int
    let updatedAt: Date
    let status: QuotaStatus
}

struct QuotaWindow: Codable, Identifiable {
    let id: String
    let limitID: String?
    let durationMinutes: Int?
    let usedPercent: Double
    let resetsAt: Date?

    var availablePercent: Double {
        max(0, 100 - usedPercent)
    }
}
```

界面不能写死 `primary` 等于 5 小时、`secondary` 等于 7 天。应根据 `windowDurationMins` 生成标签：`300` 分钟显示“5小时额度”，`10080` 分钟显示“7天额度”，其它值显示实际时长；未知时长保留兼容标签。展示层将 `usedPercent` 四舍五入为整数百分比，解析层保留 `Double`，兼容服务端的小数表示。

读取时优先遍历：

```text
rateLimitsByLimitId 的全部额度桶
```

每个额度桶分别展开 `primary`、`secondary` 等非空窗口。`rateLimits` 只是向后兼容的单桶视图；仅当多桶字段不存在时才回退使用它：

```text
rateLimits
```

### 8.1 5 小时额度展示规则

- 同一账号的 5 小时额度和周额度分别显示，不能用其中一个覆盖另一个。
- 若任一额度窗口的剩余百分比低于阈值，菜单栏提示该窗口名称及重置时间。
- 接近或经过 5 小时窗口重置时间时，触发一次完整的 `account/rateLimits/read`；周额度及其它额度桶均以该次服务端返回值更新。
- `account/rateLimits/updated` 通知只可能包含部分字段；收到通知后合并到最近一次完整快照，或直接重新调用 `account/rateLimits/read`，不得将未返回窗口清空。

## 9. 数据存储与安全

### 主应用私有目录

保存：

- 各账号独立 `CODEX_HOME`
- 账号配置
- 协议兼容状态

目录权限应限制为当前用户访问。

### 日志

日志不得包含：

- access token
- refresh token
- Cookie
- app-server 完整认证响应
- 认证文件正文

## 10. 刷新策略

当前实现启动、手动、重置到期、唤醒及系统时间变化时查询，按服务端重置时间自动发送最小请求；15～30 分钟额外轮询和网络恢复监听仍为后续规划。本节的定期刷新只查询额度。第 1.1 节的自动模型请求使用独立调度，不能在每次 15～30 分钟刷新时发送模型请求。

主应用：

- 应用启动时立即刷新
- 用户点击“立即刷新”时刷新
- 后台常驻时每 15～30 分钟刷新
- 网络恢复后刷新
- 接近重置时间时安排一次刷新

## 11. 界面设计

### 菜单栏应用

```text
Codex Pulse
├── 主账号：5小时额度剩余 50%，2小时后重置
├── 主账号：7天额度剩余 72%，5天后重置
├── 工作账号：5小时额度剩余 82%，2小时后重置
├── 备用账号：需要重新登录
├── 立即刷新
├── 管理账号
├── 开机启动
└── 退出
```

颜色建议：

- 剩余大于 50%：绿色
- 剩余 20%～50%：黄色
- 剩余小于 20%：红色
- 数据过期或查询异常：灰色

菜单栏默认展示资料接口动态读取的用户名，不展示完整邮箱。

## 12. 异常处理

至少定义以下状态：

```text
codexNotInstalled
unsupportedCodexVersion
notLoggedIn
authenticationExpired
networkUnavailable
requestTimeout
protocolChanged
invalidResponse
processLaunchFailed
```

错误处理原则：

- 保留最近一次成功数据
- 明确显示最后更新时间
- 协议错误不能显示成“额度为 0”
- 一个账号失败不能影响其他账号
- 认证失效时只要求重新登录对应账号

## 13. 协议兼容设计

`codex app-server` 目前仍是实验性功能，必须将所有协议逻辑封装在单独模块：

```text
CodexProtocolAdapter
├── initialize()
├── login()
├── readAccount()
├── readRateLimits()
└── decodeNotifications()
```

业务层和界面不直接依赖 app-server 原始 JSON。

启动时执行：

```bash
codex --version
```

记录已验证版本范围。遇到未知版本时可以继续尝试兼容解析，但必须在失败后提示“当前 Codex CLI 版本暂不兼容”，不得修改正式 Codex App 或自动降级 Codex CLI。

## 14. 测试方案

### 单元测试

- 只有 7 天窗口
- 只有 5 小时窗口
- 同时存在 5 小时和 7 天窗口
- 5 小时窗口重置、周窗口保持不变
- 存在多个 `limitId`
- Credits 有余额和无余额
- 可用重置次数大于 0
- 登录失效
- 返回未知字段
- 缺少可选字段
- 非法 JSON
- 进程超时

### 集成测试

- 使用独立测试 `CODEX_HOME` 登录
- 连续查询所有已添加账号
- 查询期间正常使用 Codex App
- 退出菜单栏应用后确认无遗留 app-server 进程
- 更新 Codex CLI 后执行兼容验证
- 断网、恢复网络及认证过期测试

### 安全验证

- 确认额度展示和导出数据不包含令牌
- 确认日志不输出凭据
- 确认从未写入 `~/.codex`
- 确认不会终止 Codex App 进程

## 15. 开发阶段与工作量

### 第一阶段：协议与最小请求验证，原估算 0.5～1人天

- 使用 Swift Package 实现最小验证程序，启动独立 app-server 并完成初始化
- 对一个独立登录账号读取五小时和周额度，保存请求前后快照
- 发送一次最小模型请求，确认真实返回 OK 及对应 turn 完成；不等待额外窗口实验
- 服务端普通额度许可未知、窗口缺失或额度耗尽时停止模型请求
- 验证异常、超时、请求完成状态及进程退出，避免将请求接受误判为执行成功
- 具体运行步骤和结果见仓库内 `docs/phase-1-verification.md`；2026-10-01 已完成独立账号登录、真实额度读取和一次最小请求

此处工期为原估算。官方五小时窗口规则作为实现依据，重置后对比工具仅保留为可选诊断。

### 第二阶段：账号管理，1～2人天

- 各账号独立 `CODEX_HOME`
- 登录流程
- 账号别名和删除

2026-10-01 第二阶段已完成并通过编译及 30 项测试：当时的 `codex-pulse accounts` 支持最多三个账号的本地列表（2026-10-02 已取消上限）、独立登录、中文别名修改、删除及并发额度查询。三个条目均已登录，新进程并发查询通过；账号1、账号3为 Plus，账号2为用户确认的 Free，其五小时/周窗口保持未知。具体命令、目录隔离、删除恢复和验证记录见仓库内 `docs/phase-2-account-management.md`。

### 第三阶段：菜单栏应用，1人天

- 账号列表
- 额度展示
- 手动刷新
- 错误状态

2026-10-01 第三阶段已实现原生 SwiftUI 菜单栏应用，可展示三个账号的套餐、五小时/周剩余额度、服务端重置时间及最后更新时间，支持启动查询、手动刷新和错误时保留旧数据。正常卡片不单独显示额度更新时间，统一查看底部查询完成时间；查询失败而保留旧额度的卡片灰显，并显示“上次成功更新”及旧数据时间。用户已确认菜单栏入口和刷新按钮可见，并提供界面截图。详情见仓库内 `docs/phase-3-menu-bar.md`。

账号标题已改为动态读取 Codex 个人资料页的真实 `username`，不写死三个用户名，也不以邮箱前缀代替。`account/read` 不提供此字段；用户已明确授权新增只读内部资料接口 `GET https://chatgpt.com/backend-api/profiles/me`，仅使用各账号独立 `CODEX_HOME` 中的登录凭据，读取 `profile_details.username`。三个账号已真实查询成功，刷新时名称同步更新。名称与凭据不进入 Git 或额度报告，现有别名保留在本地账号管理配置中。资料失败单独提示并保留最近名称，不影响额度结果；内部接口可能随 App 升级变化。

此授权仅允许上述用户名资料查询，额度仍通过 app-server 读取，其余未公开 HTTP 接口不在范围内。

### 第四阶段：自动请求调度、后台运行与打包，工期待重新估算

- 启动时发送最小模型请求，按服务端五小时重置时间调度后续请求
- 对周额度耗尽、额度未知或认证失效的账号停止自动请求
- 开机启动、定时额度查询和唤醒恢复
- 日志和错误恢复
- 签名及 DMG

2026-10-01 已完成本阶段的自动请求调度：启动时先读取额度，符合条件的账号每窗口最多尝试一次真实最小请求，成功后读取服务端下一次重置时间；到期重新校验额度，周额度耗尽、额度未知或认证异常时停止对应账号。检查点在请求前落盘，重启和唤醒不会重复当前窗口请求，也不会补发错过的轮次；请求结果未知时等待已知服务端重置，不立即重试。面板展示每个账号的自动请求状态及下次请求时间。两个 Plus 账号真实请求完成，Free 账号窗口未知而跳过，重复执行未新增模型请求。详见 `docs/phase-4-automatic-requests.md`。

当前支持应用常驻期间的调度及睡眠、唤醒和系统时间变化恢复。2026-10-02 已完成安装到 `/Applications/Codex Pulse.app`、基于 `SMAppService.mainApp` 的“登录时启动”开关和 DMG 拖放安装包。开关读取 macOS 真实注册状态，需要系统批准时提供设置入口，正式安装后的首次运行默认请求开启，不需要先打开菜单栏；通过一次性初始化标记保留后续手动或系统关闭选择，升级和重启不强制开启。安装和更新复用原账号目录及调度检查点，DMG 不包含任何账号数据。具体安装、构建及验证见 `docs/phase-4-installation.md`。

2026-10-02 已补齐应用内账号管理并取消账号数量限制，见第五阶段说明。用户确认已验证完整五小时周期，本次不重复观察；跨周长期稳定性仍待验证。额外分钟级查询、网络恢复监听、Developer ID 分发签名及公证留待后续。

### 第五阶段：测试和适配，原估算 1人天

- 多账号联调
- Codex App 并行使用验证
- 协议兼容测试

前三阶段及第四阶段的自动调度、安装、登录启动和本地 DMG 打包已完成；剩余工作为正式分发签名、公证及长期稳定性和协议适配验证。工期需按当前范围重新评估，自动请求功能尚未重新估算。

## 16. iOS App 与跨设备同步方案

### 16.1 可行性结论

可以同时提供 iOS App 和 iPhone Widget，但 iOS 设备不能运行 Homebrew 安装的 `codex` CLI，也不能直接复用 macOS 上的 `codex app-server` 查询方式。

当前没有适合个人 Plus/Pro 账号、可供纯 iOS 应用直接查询 Codex 套餐剩余额度的正式公开 API。因此不推荐开发“完全脱离 Mac 的纯 iOS 查询端”。

推荐让 Mac 继续承担额度采集任务，通过 CloudKit 将非敏感额度快照同步给 iPhone：

```text
Mac 数据采集端
  ├── 各账号独立 CODEX_HOME
  ├── 调用 codex app-server
  ├── 查询所有已添加账号额度
  └── 上传额度快照到 CloudKit
                  ↓
        CloudKit 私有数据库
                  ↓
iOS App + iOS Widget
  ├── 展示所有已添加账号额度
  ├── 展示下次重置时间
  └── 不保存 Codex 登录凭据
```

### 16.2 多端工程结构

建议在同一个 Xcode 工程中建立多个 Target，共享数据模型和展示组件：

```text
CodexPulse
├── Shared
│   ├── Models
│   ├── QuotaFormatting
│   ├── QuotaComponents
│   └── CloudKitStore
├── macOS App
│   ├── CodexAppServerClient
│   ├── AccountManager
│   └── QuotaCollector
├── iOS App
│   ├── AccountList
│   └── QuotaDetail
└── iOS Widget
```

可跨平台复用：

- 账号与额度数据模型
- 剩余百分比计算
- 额度窗口名称和重置时间格式
- 进度条及状态颜色
- CloudKit 快照读取逻辑
- 错误和数据过期状态

macOS 独有部分只有 Codex CLI 调用、账号登录和额度采集。

### 16.3 CloudKit 数据模型

CloudKit 仅保存展示需要的非敏感数据：

```swift
struct SyncedQuotaSnapshot: Codable {
    let accountID: UUID
    let alias: String
    let planType: String?
    let windows: [SyncedQuotaWindow]
    let creditBalanceRaw: String?
    let resetCreditCount: Int
    let updatedAt: Date
    let status: QuotaStatus
}

struct SyncedQuotaWindow: Codable {
    let limitID: String?
    let durationMinutes: Int?
    let usedPercent: Double
    let resetsAt: Date?
}
```

建议使用用户 iCloud 账号下的 CloudKit 私有数据库。Mac 和 iPhone 需要登录同一个 Apple ID。

严禁上传：

- Codex access token
- refresh token
- Cookie
- `auth.json`
- 完整 app-server 认证响应
- Codex 会话内容
- 用户项目或工作区信息

即使 CloudKit 同步发生故障，也只能影响额度展示，不能影响各 Codex 账号的认证状态。

### 16.4 数据流与刷新

Mac 端：

- 每 15～30 分钟查询所有已添加账号
- 将最新快照写入 CloudKit 私有数据库

iOS App：

- 启动或进入前台时读取 CloudKit
- 将结果缓存到 iOS App Group
- 数据变化后调用 `WidgetCenter.shared.reloadTimelines`
- 提供手动刷新入口

iOS Widget：

- 优先展示 iOS App Group 中的缓存
- 使用 Timeline 定期尝试更新
- 使用 `Text(resetDate, style: .relative)` 展示动态倒计时
- 数据超过 45～60 分钟时显示“数据可能已过期”

Mac 关机、休眠或断网后，iPhone仍可显示最后一次同步的快照，但额度不会继续更新。界面必须展示最后更新时间，不能让旧数据看起来像实时结果。

### 16.5 iOS Widget 形态

建议支持：

- `systemSmall`：展示用户选择的单个账号
- `systemMedium`：展示所有已添加账号的剩余百分比
- `systemLarge`：展示所有已添加账号的全部额度窗口和重置时间
- 锁屏矩形 Widget：展示最低剩余额度及最近一次重置倒计时

Small Widget 示例：

```text
主账号
Plus
5小时额度剩余 50%
2小时后重置
```

Medium Widget 示例：

```text
主账号  5小时 50%   2小时后
主账号  7天   72%   5天后
工作账号 5小时 82%  2小时后
```

### 16.6 iOS 安全边界

- iOS App 不保存任何 Codex 认证信息
- iOS Widget 不接触 CloudKit 写权限之外的敏感数据
- Widget App Group 只保存额度快照
- 默认隐藏邮箱，只显示用户设置的别名
- iPhone丢失时不会暴露可用于登录 Codex 的凭据
- 删除账号时，由 Mac 端删除独立 `CODEX_HOME`；iOS只删除对应展示记录

### 16.7 不推荐的 iOS 方案

不推荐以下实现：

- 在 iOS 中抓取 Codex Usage 网页
- 将 ChatGPT Cookie 保存到 iPhone
- 直接调用未公开的个人额度 HTTP 接口
- 把所有已添加账号的凭据上传到自建服务器
- 在 VPS 上长期运行多个 Codex CLI 账号
- 仅依赖局域网从 iPhone 连接 Mac

局域网方案只能在 Mac 醒着、网络相同且权限允许时工作；网页抓取和未公开接口则容易因登录及页面结构变化失效。

### 16.8 iOS 增量工作量

在 macOS 版本完成的基础上：

- CloudKit 数据同步：1～2人天
- iOS App 页面：1人天
- iOS Widget：1人天
- 跨设备刷新及异常处理：1～2人天
- 真机测试、签名及权限配置：1人天

iOS 增量工作量约为 3～6人天。

整体工期需结合当前 macOS 剩余任务与上述 iOS 增量范围重新评估，暂不沿用原整体估算。

使用 CloudKit、App Groups 和真机分发时，需要配置相应的 Apple Developer 能力、Bundle Identifier、Entitlements 及 CloudKit Container。

## 17. 最终建议

第一版采用以下范围：

- 个人自用，不上架 Mac App Store
- 使用已安装的 `/opt/homebrew/bin/codex`
- 所有已添加账号全部使用独立 `CODEX_HOME`
- 菜单栏应用常驻，统一展示额度并承担自动请求调度
- 当前按服务端重置时间刷新，额外每 15～30 分钟轮询为后续规划
- 按第 1.1 节实现启动时及 5 小时窗口重置后的最小模型请求，对周额度耗尽的账号停止自动请求
- 不自建服务器
- 不抓取 Codex Usage 网页
- 除用户授权的只读用户名资料查询外，不直接调用未公开 HTTP 地址
- 不读取或修改 `~/.codex`

该方案实现路径短、隐私风险低，并能最大程度保证每天使用的 Codex App 不受影响。最大风险是 app-server 协议升级，因此必须通过独立协议适配层和版本检测控制影响范围。

推荐分两个阶段实施：

1. 第一阶段先验证登录、额度接口及最小模型请求完整执行，再按官方窗口规则完成 macOS 菜单栏应用、多账号隔离、额度采集、自动请求调度，验证核心数据链路及长期稳定性。
2. 第二阶段增加 CloudKit 私有数据库、iOS App 和 iOS Widget。iOS端只负责读取和展示额度快照，不接触 Codex 登录凭据。

这种实施顺序能够把最大的协议风险集中在 Mac 数据采集层。未来即使 `codex app-server` 发生变化，也只需要修改 `CodexProtocolAdapter`，不影响 CloudKit 数据结构和 iOS 展示层的主要界面代码。
