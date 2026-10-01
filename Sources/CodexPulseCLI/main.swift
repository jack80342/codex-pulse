import CodexPulseCore
import Foundation
import Darwin

func emit(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
}

let usage = """
Codex Pulse 三账号管理工具
用法：codex-pulse accounts <add|list|rename|remove|login|status> [选项]
  add --name <显示别名> [--id <固定ID>]    默认生成 UUID；可用 probe-1 接入已有独立验证账号
  list                                  读取本地列表，不查询服务端
  rename --id <ID> --name <新别名>        更改显示名称，保留登录目录
  remove --id <ID>                       删除该独立账号目录及凭据；保留历史验证报告
  login --id <ID>                        打开浏览器登录，仅针对所选独立账号
  status [--id <ID>]                     查询登录状态和额度；省略 ID 时并发查询全部账号
  --codex <绝对路径>                     login/status 可指定 Codex CLI
  --timeout <秒>                         login/status 协议超时，默认 15，最大 300
登录最多等待 10 分钟。账号管理不发送模型请求，不自动购买额度或重置。
"""

func show(_ status: AccountStatus) {
    let states = ["loggedIn": "已登录", "notLoggedIn": "未登录", "quotaError": "额度查询失败",
                  "pendingDeletion": "删除待完成", "error": "状态查询失败"]
    emit("\(status.account.name) [\(status.account.id)]：\(states[status.state] ?? status.state)")
    if let error = status.error { emit("  \(error)") }
    guard let snapshot = status.snapshot else { return }
    emit("  普通额度许可：\(snapshot.ordinaryUsageAllowed.map { String($0) } ?? "未知")")
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
    emit("  更新时间：\(formatter.string(from: snapshot.capturedAt))")
    for id in snapshot.buckets.keys.sorted() {
        guard let bucket = snapshot.buckets[id] else { continue }
        emit("  \(id) / \(bucket.planType ?? "未知套餐")")
        for minutes in [300, 10080] {
            let label = minutes == 300 ? "五小时" : "周额度"
            guard let window = bucket.window(minutes: minutes) else { emit("    \(label)：未知"); continue }
            let reset = window.resetsAt.map { formatter.string(from: Date(timeIntervalSince1970: Double($0))) } ?? "未知"
            emit("    \(label)：已用 \(window.usedPercent)%；重置 \(reset)")
        }
    }
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.isEmpty || arguments == ["--help"] || arguments == ["help"] {
        emit(usage)
        exit(0)
    }
    guard arguments.count >= 2, arguments[0] == "accounts" else { throw ProbeError.invalidArgument(usage) }
    let command = arguments[1]
    let allowed: [String: Set<String>] = [
        "add": ["--id", "--name"], "list": [], "rename": ["--id", "--name"], "remove": ["--id"],
        "login": ["--id", "--codex", "--timeout"], "status": ["--id", "--codex", "--timeout"]
    ]
    guard let flags = allowed[command] else { throw ProbeError.invalidArgument(usage) }
    var options: [String: String] = [:]
    var index = 2
    while index < arguments.count {
        let flag = arguments[index]
        guard flags.contains(flag), index + 1 < arguments.count, options[flag] == nil else {
            throw ProbeError.invalidArgument("选项无效、重复或缺少参数。\n" + usage)
        }
        options[flag] = arguments[index + 1]
        index += 2
    }
    if ["rename", "remove", "login"].contains(command), options["--id"] == nil {
        throw ProbeError.invalidArgument("该命令需要 --id 指定固定账号 ID。")
    }
    if ["add", "rename"].contains(command), options["--name"] == nil {
        throw ProbeError.invalidArgument("该命令需要 --name 指定显示别名。")
    }
    let store = AccountStore()
    switch command {
    case "add":
        let name = options["--name"] ?? ""
        let account: ManagedAccount
        if let id = options["--id"] { account = try store.add(name: name, id: id) }
        else { account = try store.add(name: name) }
        emit("已添加：\(account.name) [\(account.id)]；请执行 accounts login --id \(account.id)。")
    case "list":
        let accounts = try store.list()
        if accounts.isEmpty { emit("尚无账号，请执行 accounts add --name <别名>。") }
        for account in accounts {
            emit("\(account.name) [\(account.id)]" + (account.pendingDeletion ? "：删除待完成，请重试 remove。" : ""))
        }
    case "rename":
        try store.rename(id: options["--id"] ?? "", name: options["--name"] ?? "")
        emit("账号别名已更新；固定 ID 和登录目录保持不变。")
    case "remove":
        try store.remove(id: options["--id"] ?? "")
        emit("该账号已从列表移除，本地独立登录目录及凭据已删除；历史验证报告保留。")
    case "login", "status":
        let timeout = Double(options["--timeout"] ?? "15") ?? 0
        guard timeout.isFinite, timeout > 0, timeout <= 300 else { throw ProbeError.invalidArgument("协议超时须在 0～300 秒之间。") }
        let executable = options["--codex"] ?? ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            .first(where: FileManager.default.isExecutableFile(atPath:)) ?? ""
        guard executable.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executable) else {
            throw ProbeError.invalidArgument("未找到 Codex CLI，请用 --codex 指定绝对路径。")
        }
        let service = AccountService(store: store, executable: URL(fileURLWithPath: executable), timeout: timeout)
        let statuses: [AccountStatus]
        if command == "login" {
            let id = options["--id"] ?? ""
            try service.login(id: id) { url in
                emit("正在打开该账号的登录页面。请确认浏览器使用目标账号，必要时切换网页账号；最多等待 10 分钟。")
                try LoginBrowser.open(url)
            }
            emit("该独立账号登录已确认；正在读取额度。")
            statuses = [try service.status(id: id)]
        } else if let id = options["--id"] {
            statuses = [try service.status(id: id)]
        } else {
            statuses = try await service.statuses()
        }
        if statuses.isEmpty { emit("尚无账号，请先执行 accounts add --name <别名>。") }
        for status in statuses { show(status) }
        var seen: [String: String] = [:]
        var duplicated = false
        for status in statuses {
            if let digest = status.snapshot?.identityDigest {
                if let name = seen[digest] {
                    emit("提示：\(name) 与 \(status.account.name) 登录了同一个服务端账号，额度共享；请检查浏览器账号。")
                    duplicated = true
                } else { seen[digest] = status.account.name }
            }
        }
        if duplicated || statuses.contains(where: { $0.error != nil }) { exit(1) }
    default: break
    }
} catch {
    let message = (error as? AccountError)?.description ?? (error as? ProbeError)?.description ?? AccountError.storageFailure.description
    FileHandle.standardError.write(Data(("操作停止：" + message + "\n").utf8))
    exit(1)
}
