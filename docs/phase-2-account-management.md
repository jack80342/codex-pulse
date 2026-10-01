# 第二阶段：三账号管理

## 范围与结构

新增 `codex-pulse accounts` 命令行入口。`AccountStore` 管理本地列表和目录操作；`AccountService` 编排独立登录与额度读取，复用已有 `ProbeSession` 和 `AppServerClient`。本说明记录账号管理阶段；菜单栏的后续进展见 [第三阶段说明](phase-3-menu-bar.md)。

- 每个账号使用固定 ID 和独立 `CODEX_HOME`；默认生成 UUID，可显式登记已有独立验证账号 `probe-1`。
- 显示别名支持中文，1～64 个字符，不参与目录拼接；重命名不改变 ID 或登录状态。
- 本地列表最多三个条目，待删除条目仍占用名额；列表原子写入，格式损坏时明确报错，不重置或覆盖。
- 本地列表仅保存固定 ID、别名、创建时间和删除标记，不保存邮箱、原始服务端账号 ID 或令牌。
- 账号管理操作不发送模型请求，也不自动购买或应用额度重置。

## 使用步骤

```bash
cd /Users/j/github_repo/codex-pulse
swift build
./scripts/test.sh

# 若使用第一阶段已经独立登录的账号，登记既有目录；不复制凭据。
swift run codex-pulse accounts add --id probe-1 --name "账号1"
swift run codex-pulse accounts add --name "账号2"
swift run codex-pulse accounts add --name "账号3"
swift run codex-pulse accounts list

# 从 list 中复制对应的固定 ID，每次只登录一个目标账号。
swift run codex-pulse accounts login --id "<账号2的ID>"
swift run codex-pulse accounts login --id "<账号3的ID>"
swift run codex-pulse accounts status
```

本机已登记三个条目时不要重复执行 `add`。添加不代表已登录。`login` 打开默认浏览器，等待对应登录完成事件并再次读取账号；已登录时不重复打开浏览器。浏览器可能保留其他账号的网页会话，请在授权前确认目标账号。需要时先切换浏览器网页账号，再启动该账号登录。

`status` 省略 ID 时并发查询全部条目，按列表顺序输出；也可以加 `--id` 单独查询。真实登录状态与额度每次重新读取，不把缓存或未登录当作成功。显示未登录、额度查询失败、状态查询失败或删除待完成；未知窗口显示未知。查询有错误或发现重复服务端身份时退出码为 1，但仍输出其余账号结果。

身份摘要仅用于内存中的重复登录提示，不显示或保存邮箱。重复提示需要两份成功读取的额度快照；额度读取失败时无法确认账号是否不同。误登录同一个服务端账号时，可删除误登录的独立条目，再添加并使用正确网页账号登录；这只清理所选独立目录。

```bash
swift run codex-pulse accounts rename --id "<ID>" --name "工作账号"
swift run codex-pulse accounts remove --id "<ID>"
```

删除会移除所选条目及 `accounts/<ID>` 中的本地登录凭据和 CLI 状态，不删除历史验证报告，也不操作日常 `~/.codex`。账号 ID 不是服务端账户删除操作。

## 隔离、并发与失败处理

本地数据均位于 `~/Library/Application Support/CodexPulse/`：

```text
account-list.json                  # 列表，0600
account-list.lock                  # 跨进程列表锁，0600
account-locks/<ID>.lock             # 跨进程账号会话锁，0600
accounts/<ID>/                     # 独立登录目录，0700
verification/<ID>/workspace/       # 专用空目录，0700
verification/<ID>/reports/         # 历史验证报告，0700
```

新管理入口与原 `codex-pulse-probe` 共用账号锁；同一账号的登录、查询、probe 与删除不能并行运行。账号忙时明确报错，其他账号可继续查询。列表锁只保护短暂文件操作，最多等待一秒；登录等待期间不占用列表锁。服务端子进程仍由调用方创建和关闭，超时或失败不影响非本工具持有的进程。

删除先持久化待删除标记，再清理独立账号目录，成功后移除条目。异常或崩溃时留下可恢复状态；待删除账号不能开启会话，修复本地阻塞后重试相同 `remove` 即可完成清理。目录符号链接、非法路径及指向日常 `.codex` 的路径被拒绝；不通过链接删除外部文件。

## 验证记录

2026-10-01，macOS / Apple Silicon / Swift 6.4 / Codex CLI 0.158.0：

- `swift build` 通过。
- `./scripts/test.sh`：30 项测试通过（第一阶段 18 项、新增或补充 12 项）。
- 覆盖列表跨实例持久化、别名与凭据目录分离、三个名额、路径校验、损坏列表保护、删除隔离、待删除恢复和活动会话锁。
- 本地模拟 JSONL 服务验证三账号并发结果及排序、一个超时/未登录/额度错误不丢失其他账号结果、登录事件匹配、失败/非法 URL/超时取消，以及新进程保留登录状态。
- 进程测试按套件串行运行，三账号聚合内部仍并发，避免测试本身大量 Python 启动竞争资源造成无关超时。生产协议默认超时仍为 15 秒。
- 三个本地条目已建立。真实并发 `status` 在北京时间 21:49:27 返回：账号1已登录（Plus），五小时已用 37%、周额度已用 15%，重置时间分别为 2026-10-02 00:12:06 和 2026-10-06 16:15:06；账号2、账号3明确显示未登录。此次仅查询，未发送模型请求。
- 账号2已于北京时间 21:58 完成真实登录。新进程汇总查询返回账号1为 Plus，账号2为 free 且五小时/周窗口均未知；未提示账号1与账号2身份重复。用户随后确认账号2就是 Free 账号，登录结果符合目标配置，无需重新登录。
- 账号3已于北京时间 22:01 完成登录，服务端返回 Plus。22:01:54 再次用新进程并发查询三个账号，三者均已登录且未提示重复；账号2仍为 free，缺少五小时/周窗口。当前快照如下，本次仅登录与查询，未发送模型请求。

| 条目 | 服务端套餐 | 五小时已用 | 周额度已用 | 五小时重置（北京时间） | 周重置（北京时间） |
| --- | --- | --- | --- | --- | --- |
| 账号1 | Plus | 41% | 16% | 2026-10-02 00:12:06 | 2026-10-06 16:15:06 |
| 账号2 | Free | 未知 | 未知 | 未知 | 未知 |
| 账号3 | Plus | 0% | 52% | 2026-10-02 03:01:54 | 2026-10-05 11:04:21 |

以上重置时间仅记录服务端快照，不推断第三个账号已由本工具发送模型消息或启动新窗口。用户确认的两 Plus 加一 Free 配置已完成独立登录、重启后读取和真实并发查询，第二阶段完成。未知额度保持未知，不补成 0%；账号2在缺少五小时/周窗口时不会通过模型请求的额度校验。

## 本阶段修改文件

- `Package.swift`
- `Sources/CodexPulseCore/AccountStore.swift`
- `Sources/CodexPulseCore/AccountService.swift`
- `Sources/CodexPulseCore/ProbeSession.swift`
- `Sources/CodexPulseCLI/main.swift`
- `Sources/CodexPulseProbe/main.swift`
- `Tests/CodexPulseCoreTests/AccountTests.swift`
- `Tests/CodexPulseCoreTests/AccountServiceTests.swift`
- `Tests/CodexPulseCoreTests/ProtocolTests.swift`
- `Tests/CodexPulseCoreTests/Fixtures/app-server.py`
- `scripts/test.sh`
- `README.md`
- `docs/design-plan.md`
- `docs/phase-1-verification.md`
- `docs/phase-2-account-management.md`
- 原方案 `/Users/j/Desktop/work/Codex多账号额度小组件推荐方案.md` 同步第二阶段进度。

## 尚未完成与风险

第二阶段已无待完成的登录事项。账号2当前没有五小时/周窗口，后续调度应继续停止该账号的模型请求，直到服务端返回满足条件的额度。删除凭据是本地不可逆清理，删除后的账号需重新登录。CLI 升级可能改变认证和额度协议；当前仅适配已验证的 0.158.0。菜单栏列表、额度展示、手动刷新和错误状态已在第三阶段实现，见 [第三阶段说明](phase-3-menu-bar.md)。长期自动请求功能仍待实现。
