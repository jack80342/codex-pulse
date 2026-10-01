import CodexPulseCore
import Foundation
import Darwin

func emit(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
}

func show(_ snapshot: QuotaSnapshot) {
    emit("服务端普通额度许可：\(snapshot.ordinaryUsageAllowed.map { String($0) } ?? "未知")")
    for id in snapshot.buckets.keys.sorted() {
        guard let bucket = snapshot.buckets[id] else { continue }
        emit("额度桶：\(id)，套餐：\(bucket.planType ?? "未知")")
        for window in bucket.windows {
            let duration = window.windowDurationMins.map { "\($0) 分钟" } ?? "未知时长"
            let reset = window.resetsAt.map { ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double($0))) } ?? "未知"
            emit("  \(duration)：已用 \(window.usedPercent)%；重置 \(reset)")
        }
    }
}

let usage = """
Codex Pulse 第一阶段验证工具
用法：codex-pulse-probe <handshake|login|status|models|probe|verify-reset> [选项]
  --account <别名>       独立账号目录，默认 probe-1
  --codex <绝对路径>     默认优先 /opt/homebrew/bin/codex，其次 /usr/local/bin/codex
  --timeout <秒>         协议请求超时，默认 15
  --turn-timeout <秒>    模型执行超时，默认 90
  --model <模型名>       probe 可指定 models 返回的模型；省略时使用目录默认模型
  --limit-id <额度桶>    默认 codex
  --report <绝对路径>    verify-reset 必填，使用首次 probe 生成的报告
login 将打开浏览器，需用户自行登录；probe 和 verify-reset 各发送一次真实模型请求。
报告保存在 ~/Library/Application Support/CodexPulse/verification/<别名>/reports/。
"""

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first, command != "--help", command != "help" else {
        emit(usage)
        exit(0)
    }
    guard ["handshake", "login", "status", "models", "probe", "verify-reset"].contains(command) else {
        throw ProbeError.invalidArgument("未知命令。\n" + usage)
    }
    var options: [String: String] = [:]
    var index = 1
    let supported = Set(["--account", "--codex", "--timeout", "--turn-timeout", "--model", "--limit-id", "--report"])
    while index < args.count {
        guard supported.contains(args[index]), index + 1 < args.count, options[args[index]] == nil else {
            throw ProbeError.invalidArgument("选项无效、重复或缺少参数。\n" + usage)
        }
        options[args[index]] = args[index + 1]
        index += 2
    }
    let account = options["--account"] ?? "probe-1"
    let timeout = Double(options["--timeout"] ?? "15") ?? 0
    let turnTimeout = Double(options["--turn-timeout"] ?? "90") ?? 0
    guard timeout.isFinite, timeout > 0, timeout <= 300,
          turnTimeout.isFinite, turnTimeout > 0, turnTimeout <= 600 else {
        throw ProbeError.invalidArgument("协议超时须在 0～300 秒之间，模型超时须在 0～600 秒之间。")
    }
    let executablePath = options["--codex"] ?? ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        .first(where: FileManager.default.isExecutableFile(atPath:)) ?? ""
    guard executablePath.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executablePath) else {
        throw ProbeError.invalidArgument("未找到 Codex CLI，请用 --codex 指定绝对路径。")
    }
    let previousURL: URL?
    if command == "verify-reset" {
        guard let path = options["--report"], path.hasPrefix("/") else {
            throw ProbeError.invalidArgument("verify-reset 需要 --report 指定首次验证报告的绝对路径。")
        }
        previousURL = URL(fileURLWithPath: path)
    } else {
        guard options["--report"] == nil else { throw ProbeError.invalidArgument("--report 仅用于 verify-reset。") }
        previousURL = nil
    }
    let paths = try ProbePaths(account: account)
    try paths.prepare()
    let client = try AppServerClient(
        executable: URL(fileURLWithPath: executablePath), arguments: ProbePaths.serverArguments,
        codexHome: paths.accountHome, workspace: paths.workspace, timeout: timeout
    )
    defer { client.close() }
    try client.initialize()
    emit("app-server 初始化成功；独立账号：\(account)")
    let session = ProbeSession(client: client)
    switch command {
    case "handshake":
        if let info = try session.readAccount() { emit("账号类型：\(info["type"] as? String ?? "未知")") }
        else { emit("独立账号尚未登录；初始化和 account/read 已通过。") }
    case "login":
        if let info = try session.readAccount() {
            guard info["type"] as? String == "chatgpt" else { throw ProbeError.unsupportedAccount }
            emit("该独立账号已经登录。")
            break
        }
        let login = try client.request("account/login/start", params: ["type": "chatgpt"])
        guard let loginID = login["loginId"] as? String, let rawURL = login["authUrl"] as? String,
              let url = URL(string: rawURL), url.scheme == "https",
              let host = url.host, ["auth.openai.com", "chatgpt.com", "auth.chatgpt.com"].contains(host) else {
            throw ProbeError.invalidResponse
        }
        let browser = Process()
        browser.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        browser.arguments = [url.absoluteString]
        do { try browser.run(); browser.waitUntilExit() } catch { throw ProbeError.launchFailed }
        guard browser.terminationStatus == 0 else { throw ProbeError.launchFailed }
        emit("浏览器已打开，请在浏览器登录用于验证的账号；等待最多 10 分钟。")
        do {
            let notification = try client.nextNotification(until: Date().addingTimeInterval(600)) {
                $0["method"] as? String == "account/login/completed" &&
                ($0["params"] as? [String: Any])?["loginId"] as? String == loginID
            }
            guard (notification["params"] as? [String: Any])?["success"] as? Bool == true else {
                throw ProbeError.loginFailed
            }
            guard let info = try session.readAccount(), info["type"] as? String == "chatgpt" else {
                throw ProbeError.unsupportedAccount
            }
            emit("独立账号登录成功；未输出邮箱或令牌。")
        } catch {
            _ = try? client.request("account/login/cancel", params: ["loginId": loginID])
            throw error
        }
    case "status": show(try session.readQuota())
    case "models":
        guard let info = try session.readAccount() else { throw ProbeError.notLoggedIn }
        guard info["type"] as? String == "chatgpt" else { throw ProbeError.unsupportedAccount }
        for model in try session.models() {
            guard let name = model["model"] as? String else { continue }
            emit(name + ((model["isDefault"] as? Bool == true) ? "（目录默认模型）" : ""))
        }
        emit("模型目录不保证账号实际访问权限，真实请求错误会明确报出。")
    case "probe", "verify-reset":
        let reportURL = paths.reports.appendingPathComponent("\(UUID().uuidString).json")
        emit("额度检查通过后将发送一次最小真实模型请求；报告计划保存至：\(reportURL.path)")
        let report = try session.runProbe(
            account: account, limitID: options["--limit-id"] ?? "codex", model: options["--model"],
            workspace: paths.workspace, reportURL: reportURL, previousURL: previousURL, turnTimeout: turnTimeout
        )
        emit("模型请求已完成：\(report.model)；以下为请求后的额度。")
        if let after = report.after { show(after) }
        for observation in report.observations {
            let change = observation.usedPercentChange.map { String($0) } ?? "未知"
            emit("\(observation.durationMinutes) 分钟窗口：重置变化 \(observation.resetChange)，用量变化 \(change) 个百分点")
        }
        emit(report.conclusion)
    default: break
    }
} catch {
    let message = (error as? ProbeError)?.description ?? "本地文件操作失败，未输出原始认证或日志内容。"
    FileHandle.standardError.write(Data(("验证停止：" + message + "\n").utf8))
    exit(1)
}
