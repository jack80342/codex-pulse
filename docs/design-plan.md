# Codex Pulse（codex-pulse）多账号额度桌面小组件推荐方案

更新时间：2026-10-01

- Git 仓库名：`codex-pulse`
- 应用显示名称：`Codex Pulse`
- Swift 工程及主应用名称：`CodexPulse`
- 桌面小组件名称：`CodexPulseWidget`
- 本地仓库目录：`/Users/j/github_repo/codex-pulse`
- 仓库内方案文档：`docs/design-plan.md`

## 1. 项目目标

开发一个 macOS 原生桌面小组件，集中展示 3 个 Codex 账号的：

- 账号名称及套餐类型
- 当前额度已使用百分比
- 当前可用额度百分比
- 不同额度窗口及下次重置时间，包括当前的 5 小时额度和周额度
- Credits 余额及可用重置次数（接口返回时展示）
- 数据更新时间、登录失效和查询异常状态

该工具定位为个人本地工具，不依赖自建服务器，不抓取网页，不影响日常使用的 Codex App。

### 1.1 第一版新增目标：自动触发 5 小时额度窗口

先采用简单流程：应用打开时，对三个账号分别发送一次最小模型请求，尝试启动各自的 5 小时额度窗口；之后在每个窗口重置后自动再次请求，尝试启动下一轮窗口，直到对应账号的周额度耗尽。

具体流程：

1. 应用启动时，先查询三个账号的额度；仅对周额度未耗尽、5 小时额度可用且登录正常的账号发送一次最小模型请求，例如“只回复 OK”。
2. 请求完成后，重新调用 `account/rateLimits/read`，记录各账号实际返回的窗口状态和 `resetsAt`。
3. 后续请求以约每 5 小时一次为目标，实际按各账号服务端返回的 5 小时窗口重置时间调度；到期后先查询额度，满足条件再发送一次最小模型请求，并重新读取下一次重置时间。
4. 某账号周额度耗尽时，停止该账号的自动模型请求，其他账号继续独立运行。
5. 应用重启或电脑唤醒时，重新查询额度后恢复调度，不补发休眠或退出期间错过的请求，避免集中消耗额度。

实现及验收边界：

- 额度查询与模型请求是两种不同操作。`account/rateLimits/read` 用于查询额度，不能将查询成功视为已启动 5 小时窗口。
- 必须先对一个账号进行请求前后对比，验证最小模型请求是否确实启动新的 5 小时窗口。官方文档未保证这一触发机制，未验证前不得宣称自动启动成功；重置时间以服务端返回值为准。
- 最小模型请求本身会消耗额度；该功能目标是尝试提前触发窗口，不承诺增加额度或累积未使用窗口。
- 模型请求使用各账号独立的 ChatGPT 登录状态，在专用空工作目录和独立会话中执行，不读取用户项目、不执行命令、不修改文件。
- 一个账号的查询失败、请求失败或认证失效不得影响另外两个账号；周额度缺失或查询异常时，不得推断为仍有额度并继续发送模型请求。
- 定时请求由 macOS 主应用负责，需应用后台运行、电脑处于唤醒状态且网络可用；Widget 和 iOS 端只展示状态。

参考：[Codex App Server 额度接口](https://learn.chatgpt.com/docs/app-server)、[套餐额度说明](https://learn.chatgpt.com/docs/pricing)。

## 2. 可行性结论

技术上可行。

本机安装的 Codex CLI 0.149.0 提供本地 `app-server`，通过 JSONL 协议调用：

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

采用“菜单栏常驻应用 + WidgetKit 桌面小组件”的组合，而不是只开发一个 Widget。

```text
CodexPulse 主应用
  ├── 管理三个账号
  ├── 完成账号登录
  ├── 调用 codex app-server
  ├── 定时读取额度
  ├── 保存非敏感额度快照
  └── 通知 WidgetKit 刷新
                    ↓
               App Group
                    ↓
CodexPulseWidget
  ├── 读取额度快照
  ├── 展示三个账号
  └── 不管理登录、不接触认证凭据
```

主应用负责认证、进程和网络；Widget 只负责显示。这样符合 WidgetKit 的生命周期和刷新限制，也更容易处理登录失效及协议错误。

## 4. 技术选型

- Swift 6
- SwiftUI
- WidgetKit
- App Groups
- `Process`、`Pipe`：运行 Codex app-server 并进行 JSONL 通信
- `Codable`：解析协议响应
- `WidgetCenter`：触发 Widget 刷新
- `SMAppService`：可选的登录时启动
- Unified Logging：记录不含凭据的运行状态

最低支持版本建议为 macOS 14。

第一版不建议上架 Mac App Store，优先制作个人使用的签名应用或 DMG。

## 5. 三账号隔离方案

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

一个 app-server 实例只服务一个账号。三个账号分别登录后，可以长期保持各自的认证状态。

### 5.2 不影响正式 Codex App 的强制约束

小组件不得执行以下操作：

- 不得把 `CODEX_HOME` 指向 `~/.codex`
- 不得读取、复制、写入或删除 `~/.codex/auth.json`
- 不得修改 `~/.codex/.codex-global-state.json`
- 不得复用官方 App 的会话和全局状态
- 不得在未设置独立 `CODEX_HOME` 时执行 `codex login` 或 `codex logout`
- 不得执行 `killall codex`、`killall ChatGPT` 等全局结束命令
- 不得结束非本应用创建的进程

即使小组件中的账号与 Codex App 当前账号相同，也应在小组件的独立目录内重新登录一次，不能直接复制官方 App 的认证文件。

目录关系如下：

```text
日常使用的 Codex App
└── ~/.codex

额度小组件
├── Application Support/CodexPulse/accounts/account-1
├── Application Support/CodexPulse/accounts/account-2
└── Application Support/CodexPulse/accounts/account-3
```

这样即使小组件崩溃、协议变化或登录过期，也不会破坏日常工作的 Codex App。

## 6. 账号添加与登录流程

推荐使用 app-server 的登录流程，而不是打开 Terminal 执行命令：

1. 用户点击“添加账号”。
2. 应用创建 UUID 和独立账号目录。
3. 使用该目录启动 app-server。
4. 完成 `initialize`。
5. 调用 `account/login/start`。
6. 使用 `NSWorkspace.shared.open` 打开认证地址。
7. 监听 `account/login/completed`。
8. 调用 `account/read` 获取邮箱和套餐。
9. 用户为账号设置别名。
10. 首次调用 `account/rateLimits/read` 并保存额度快照。

三个账号首次登录时，浏览器中的 ChatGPT 网页登录状态可能需要切换。可以使用不同浏览器 Profile 或无痕窗口完成登录；该过程不应改变 Codex App 的账号状态。

## 7. Codex app-server 通信

### 7.1 启动方式

按以下顺序查找 Codex 可执行文件：

```text
/opt/homebrew/bin/codex
/usr/local/bin/codex
用户手动指定的路径
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

每个账号设置 15 秒超时，三个账号顺序查询。只保存自己启动的 `Process` 引用，结束时只终止对应进程。

不建议常驻三个 app-server，因为额度只需要分钟级更新，短期进程更容易控制资源和故障边界。

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
- 若任一额度窗口的剩余百分比低于阈值，菜单栏和 Widget 均提示该窗口名称及重置时间。
- 接近或经过 5 小时窗口重置时间时，触发一次完整的 `account/rateLimits/read`；周额度及其它额度桶均以该次服务端返回值更新。
- `account/rateLimits/updated` 通知只可能包含部分字段；收到通知后合并到最近一次完整快照，或直接重新调用 `account/rateLimits/read`，不得将未返回窗口清空。

## 9. 数据存储与安全

### 主应用私有目录

保存：

- 三个独立 `CODEX_HOME`
- 账号配置
- 协议兼容状态

目录权限应限制为当前用户访问。

### App Group

只保存 Widget 展示需要的非敏感快照：

- 账号 ID 和别名
- 可选的脱敏邮箱
- 套餐类型
- 各额度桶、额度窗口、使用百分比及重置时间
- Credits 余额
- 最后更新时间
- 错误状态

禁止将访问令牌、刷新令牌、Cookie 或完整认证文件写入 App Group。

### 日志

日志不得包含：

- access token
- refresh token
- Cookie
- app-server 完整认证响应
- 认证文件正文

## 10. 刷新策略

本节的定期刷新只查询额度。第 1.1 节的自动模型请求使用独立调度，不能在每次 15～30 分钟刷新时发送模型请求。

主应用：

- 应用启动时立即刷新
- 用户点击“立即刷新”时刷新
- 后台常驻时每 15～30 分钟刷新
- 网络恢复后刷新
- 接近重置时间时安排一次刷新

Widget：

- 读取 App Group 中的最新快照
- 使用约 30 分钟的 Timeline 更新周期
- 主应用数据变化时调用 `WidgetCenter.shared.reloadTimelines`
- 使用 `Text(resetDate, style: .relative)` 展示动态倒计时

如果数据超过 45 分钟未更新，Widget 显示“数据可能已过期”，而不是继续把旧数据当成当前结果。

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

### Widget

优先支持 `systemMedium` 和 `systemLarge`：

```text
主账号       Plus        剩余 50%
██████████░░░░░░░░░░
5小时额度 · 2小时后重置
7天额度 · 8月25日 23:06重置

工作账号     Plus        剩余 82%
████████████████░░░░
5小时额度 · 2小时后重置
```

颜色建议：

- 剩余大于 50%：绿色
- 剩余 20%～50%：黄色
- 剩余小于 20%：红色
- 数据过期或查询异常：灰色

提供“隐藏邮箱”选项，默认在桌面只显示账号别名。

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
- 一个账号失败不能影响另外两个账号
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

业务层和 Widget 不直接依赖 app-server 原始 JSON。

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
- 连续查询三个账号
- 查询期间正常使用 Codex App
- 关闭小组件后确认无遗留 app-server 进程
- 更新 Codex CLI 后执行兼容验证
- 断网、恢复网络及认证过期测试

### 安全验证

- 确认 App Group 不包含令牌
- 确认日志不输出凭据
- 确认从未写入 `~/.codex`
- 确认不会终止 Codex App 进程

## 15. 开发阶段与工作量

### 第一阶段：协议验证，0.5～1人天

- Swift 启动 app-server
- 完成初始化和额度读取
- 验证错误及超时处理

### 第二阶段：账号管理，1～2人天

- 三个独立 `CODEX_HOME`
- 登录流程
- 账号别名和删除

### 第三阶段：菜单栏应用，1人天

- 账号列表
- 额度展示
- 手动刷新
- 错误状态

### 第四阶段：Widget，1人天

- App Group
- Widget 布局
- Timeline 和刷新

### 第五阶段：后台运行与打包，1～2人天

- 开机启动
- 定时刷新
- 日志和错误恢复
- 签名及 DMG

### 第六阶段：测试和适配，1人天

- 三账号联调
- Codex App 并行使用验证
- 协议兼容测试

预计总工作量：5～8人天。

## 16. iOS App 与跨设备同步方案

### 16.1 可行性结论

可以同时提供 iOS App 和 iPhone Widget，但 iOS 设备不能运行 Homebrew 安装的 `codex` CLI，也不能直接复用 macOS 上的 `codex app-server` 查询方式。

当前没有适合个人 Plus/Pro 账号、可供纯 iOS 应用直接查询 Codex 套餐剩余额度的正式公开 API。因此不推荐开发“完全脱离 Mac 的纯 iOS 查询端”。

推荐让 Mac 继续承担额度采集任务，通过 CloudKit 将非敏感额度快照同步给 iPhone：

```text
Mac 数据采集端
  ├── 三个独立 CODEX_HOME
  ├── 调用 codex app-server
  ├── 查询三个账号额度
  └── 上传额度快照到 CloudKit
                  ↓
        CloudKit 私有数据库
                  ↓
iOS App + iOS Widget
  ├── 展示三个账号额度
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
├── macOS Widget
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

即使 CloudKit 同步发生故障，也只能影响额度展示，不能影响三个 Codex 账号的认证状态。

### 16.4 数据流与刷新

Mac 端：

- 每 15～30 分钟查询三个账号
- 查询成功后更新本地 App Group
- 将最新快照写入 CloudKit 私有数据库
- 在额度发生变化时刷新 macOS Widget

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
- `systemMedium`：展示三个账号的剩余百分比
- `systemLarge`：展示三个账号的全部额度窗口和重置时间
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
- 把三个账号的凭据上传到自建服务器
- 在 VPS 上长期运行三个 Codex CLI 账号
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

macOS、iOS及两端 Widget 全部完成，预计总工作量约为 8～13人天。

使用 CloudKit、App Groups 和真机分发时，需要配置相应的 Apple Developer 能力、Bundle Identifier、Entitlements 及 CloudKit Container。

## 17. 最终建议

第一版采用以下范围：

- 个人自用，不上架 Mac App Store
- 使用已安装的 `/opt/homebrew/bin/codex`
- 三个账号全部使用独立 `CODEX_HOME`
- 菜单栏应用常驻，Widget 只读取快照
- 每 15～30 分钟刷新一次
- 按第 1.1 节验证并实现启动时及 5 小时窗口重置后的最小模型请求，对周额度耗尽的账号停止自动请求
- 不自建服务器
- 不抓取 Codex Usage 网页
- 不直接调用未公开 HTTP 地址
- 不读取或修改 `~/.codex`

该方案实现路径短、隐私风险低，并能最大程度保证每天使用的 Codex App 不受影响。最大风险是 app-server 协议升级，因此必须通过独立协议适配层和版本检测控制影响范围。

推荐分两个阶段实施：

1. 第一阶段先验证最小模型请求能否启动 5 小时窗口，再完成 macOS 菜单栏应用、三账号隔离、额度采集、自动请求调度和 macOS Widget，验证核心数据链路及长期稳定性。
2. 第二阶段增加 CloudKit 私有数据库、iOS App 和 iOS Widget。iOS端只负责读取和展示额度快照，不接触 Codex 登录凭据。

这种实施顺序能够把最大的协议风险集中在 Mac 数据采集层。未来即使 `codex app-server` 发生变化，也只需要修改 `CodexProtocolAdapter`，不影响 CloudKit 数据结构和两端 Widget 的主要界面代码。
