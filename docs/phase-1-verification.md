# 第一阶段：协议与最小请求验证

## 目的与范围

以单个独立 ChatGPT 账号验证 Codex app-server 的初始化、额度查询和最小模型请求完整执行。官方已明确上一五小时窗口结束后的首条 Work/Codex 消息启动下一窗口，无需额外实验验证该规则。

`verify-reset` 保留为可选诊断工具，只有在服务端返回的重置时间到达后才允许执行；不作为继续开发的前置条件。

本阶段提供 Swift Package 和命令行工具，不包含菜单栏、三账号界面或长期定时请求。模型请求每次只发一条“只回复 OK，不使用任何工具。”，不循环重试或自动消耗周额度。

协议依据：[官方 App Server 文档](https://learn.chatgpt.com/docs/app-server)，以及本机 Codex CLI 0.158.0 生成的 JSON Schema。CLI 升级后需重新验证兼容性。

## 编译与本地测试

```bash
cd /Users/j/github_repo/codex-pulse
swift build
./scripts/test.sh
```

应用运行只依赖 Swift 标准库、Foundation、CryptoKit 和本机 Codex CLI，无第三方包。协议测试额外使用 Python 3 运行本地模拟 JSONL 服务；它不访问网络或真实账号。测试使用 Swift Testing，关闭 XCTest 支持以适配仅安装 Command Line Tools 的环境。`scripts/test.sh` 从当前工具链查找并显式加载 Testing 宏插件，兼容 Swift 6.4 的 swiftbuild 在本机遗漏插件的情况。

## 实测步骤

1. 执行 `swift run codex-pulse-probe handshake`，确认初始化和 `account/read` 可用。未登录不影响握手验证。
2. 执行 `swift run codex-pulse-probe login`，在浏览器登录一个 Plus 账号。
3. 执行 `swift run codex-pulse-probe status`，读取完整额度快照；执行 `swift run codex-pulse-probe models` 查看目录。目录不保证账号实际模型访问权限。
4. 执行 `swift run codex-pulse-probe probe`，使用目录默认模型发送一次请求；也可使用 `--model <模型名>` 显式选择。该命令先查询额度，通过检查后才发送请求。
5. 保存程序输出的报告路径。初始化、真实额度读取和一次最小请求完整执行通过即完成本阶段。
6. 可选诊断：到达报告中 `after.buckets.<额度桶>` 内时长为 300 分钟窗口的 `resetsAt` 后，可执行 `swift run codex-pulse-probe verify-reset --report "<报告绝对路径>"` 并对比窗口；该命令另消耗一次真实请求，不默认执行。

账号别名默认 `probe-1`；使用 `--account <别名>` 可以隔离其他验证账号，但所有步骤必须使用一致别名。额度桶默认 `codex`；实际账号使用其他桶时，各次命令都需指定一致的 `--limit-id`。

## 账号隔离与请求约束

- 账号目录：`~/Library/Application Support/CodexPulse/accounts/<别名>/`。
- 空工作目录：`~/Library/Application Support/CodexPulse/verification/<别名>/workspace/`。
- 报告目录：`~/Library/Application Support/CodexPulse/verification/<别名>/reports/`。
- 使用独立目录重新登录，不读取、复制或修改 `~/.codex` 的认证文件或全局状态。
- 子进程清除已知的 API key、访问令牌和工作负载身份环境变量，并强制 ChatGPT 登录；认证由 CLI 写入独立目录。
- 验证目录权限为 `0700`，报告权限为 `0600`；只保存额度字段和身份摘要，不保存邮箱、账号原始 ID、认证响应、令牌或 stderr。
- 请求使用临时会话、只读沙箱、专用空工作目录；关闭 shell、统一命令执行、应用连接、插件、浏览器等功能，拒绝服务端工具请求。出现工具事件时停止验证并尝试中断对应 turn。
- 必须存在所选额度桶的 300 分钟和 10080 分钟窗口，二者均未耗尽；服务端 `ordinaryUsageAllowed` 必须明确为 `true`。缺失许可、缺失窗口或查询错误均停止。
- 初始化和单次协议调用默认超时 15 秒，模型执行默认超时 90 秒；浏览器登录最多等待 10 分钟。超时后不自动重试模型请求。
- stdout 持续按行读取，stderr 单独排空；正常关闭后仅在必要时终止本工具持有的子进程。

## 报告及判定

报告保存请求前后的完整额度窗口白名单、采集时间、模型、请求状态和窗口对比。

`status: completed` 仅表示对应 turn 收到 `completed` 状态、返回 OK 且请求后额度读取成功；`incomplete` 表示验证未完整完成。若在额度检查前停止，可能不会生成报告。未完成报告不能用于重置后验证。

窗口对比包括：

- `unchanged`：重置时间未变化，不能宣称新窗口已启动。
- `advanced`：观察到重置时间向后移动，仍需结合重置时点和多次观测判断。
- `newResetObserved`：此前未知、之后读到重置时间，不等于已证明由这次请求启动。
- `resetUnavailable` / `unknown`：数据不足，不推断窗口状态。

百分比可能四舍五入或延迟更新，用量变化为 0 不代表请求没有消耗额度。单次请求及前后快照无法建立可靠的因果关系；已有窗口、其他客户端使用和服务端刷新均可能影响观测。建议实测期间减少同账号的其他使用，并保留初始请求和重置后请求的两份报告。

后续调度依据[官方五小时窗口规则](https://help.openai.com/en/articles/20001516-managing-usage-with-gpt-6-astra-in-work-and-codex)及服务端实际返回值实现（2026-10-01 核对）。无需等待重置后实验；不能用硬编码的“请求时间 + 5 小时”替代服务端重置时间进行展示或调度。

## 本次验证记录

验证日期：2026-10-01。环境：Apple Silicon Mac，Swift 6.4，Codex CLI 0.158.0，Command Line Tools。

- `swift build`：通过。
- 真实 CLI 的 `initialize`、`initialized` 和未登录 `account/read`：通过。
- 未登录时 `status`：明确报错，未发送模型请求。
- 模拟协议测试：18 项通过，覆盖分包读取、stderr 排空、非法响应、RPC 错误、超时、失败 turn、工具拒绝、缺失窗口、周额度耗尽、身份及重置时间校验。
- 浏览器登录：用户已完成独立账号 `probe-1` 登录；真实 `account/read`、额度查询和模型目录读取通过。
- 最小真实请求：使用 `gpt-6-luna`，Standard 速度及支持的最低推理档位，收到 OK 和对应 turn 的 `completed`；请求后额度读取成功。

首次请求的报告采集时间为北京时间 2026-10-01 20:53:38～20:53:52。报告中的请求前后快照如下：

| 窗口 | 请求前已用 | 请求后已用 | 请求前后重置时间（北京时间） |
| --- | --- | --- | --- |
| 五小时 | 25% | 25% | 2026-10-02 00:12:06，未变化 |
| 周额度 | 14% | 14% | 2026-10-06 16:15:06，未变化 |

此前单独执行 `status` 曾读到 24% / 13%；它不是这次请求的即时基线，不能将其与请求后快照的差值归因于这次请求。报告内前后用量变化为 0 个百分点，仍不能推断请求没有消耗额度。

原始报告仅保存在本机验证目录，不提交到 Git：

```text
/Users/j/Library/Application Support/CodexPulse/verification/probe-1/reports/EC1909AC-7B65-4C1C-B0C5-4050B6B378E4.json
```

当前结论：独立登录、真实额度读取和一次最小请求已验证，第一阶段完成。账号已有五小时窗口，本次请求未改变重置时间；新窗口启动规则由官方说明确认，不依赖这次观测建立因果结论。

## 开发衔接

原定北京时间 2026-10-02 00:13 的后续验证任务已取消，未发送第二次验证请求。已按用户指出的官方规则移除等待额外窗口实验的要求。产品的长期自动请求功能尚未实现。

如后续发现需要排查窗口异常，可在实际重置时间到达、确认无未完成的同类请求后，手动执行可选诊断：

```bash
swift run codex-pulse-probe verify-reset --account probe-1 --report "/Users/j/Library/Application Support/CodexPulse/verification/probe-1/reports/EC1909AC-7B65-4C1C-B0C5-4050B6B378E4.json"
```

下一阶段为三个账号的独立登录和账号管理。首次登录由用户在浏览器完成；服务端额度缺失、许可未知或耗尽时继续停止模型请求。
