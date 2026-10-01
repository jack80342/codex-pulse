import Foundation

public struct ProbePaths {
    public let accountHome: URL
    public let workspace: URL
    public let reports: URL

    public init(account: String, root: URL? = nil) throws {
        guard !account.isEmpty, account.count <= 64,
              account.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains($0) })
        else { throw ProbeError.invalidArgument("账号别名仅支持 1～64 位字母、数字、连字符和下划线。") }
        let base = root ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexPulse")
        accountHome = base.appendingPathComponent("accounts/\(account)")
        workspace = base.appendingPathComponent("verification/\(account)/workspace")
        reports = base.appendingPathComponent("verification/\(account)/reports")
    }

    public func prepare() throws {
        let officialHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").resolvingSymlinksInPath().path
        for url in [accountHome, workspace, reports] {
            let resolved = url.resolvingSymlinksInPath().path
            guard resolved != officialHome, !resolved.hasPrefix(officialHome + "/") else {
                throw ProbeError.invalidArgument("验证目录不能指向日常 Codex 的认证目录。")
            }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
        guard try FileManager.default.contentsOfDirectory(atPath: workspace.path).isEmpty else {
            throw ProbeError.invalidArgument("专用工作目录必须为空，避免读取项目内容。")
        }
    }

    public static let serverArguments = [
        "app-server", "--listen", "stdio://",
        "-c", "cli_auth_credentials_store=\"file\"",
        "-c", "forced_login_method=\"chatgpt\"",
        "-c", "project_doc_max_bytes=0",
        "-c", "web_search=\"disabled\"",
        "-c", "features.shell_tool=false",
        "-c", "features.unified_exec=false",
        "-c", "features.apps=false",
        "-c", "features.plugins=false",
        "-c", "features.browser_use=false",
        "-c", "features.computer_use=false",
        "-c", "features.multi_agent=false",
        "-c", "features.image_generation=false"
    ]
}

public final class ProbeSession {
    public let client: AppServerClient

    public init(client: AppServerClient) { self.client = client }

    public func readAccount() throws -> [String: Any]? {
        let result = try client.request("account/read", params: ["refreshToken": false])
        if result["account"] is NSNull { return nil }
        guard let account = result["account"] as? [String: Any] else { throw ProbeError.invalidResponse }
        return account
    }

    public func readQuota() throws -> QuotaSnapshot {
        guard let account = try readAccount() else { throw ProbeError.notLoggedIn }
        guard account["type"] as? String == "chatgpt" else { throw ProbeError.unsupportedAccount }
        let result = try client.request("account/rateLimits/read")
        return try QuotaSnapshot.decode(JSONSerialization.data(withJSONObject: result), email: account["email"] as? String)
    }

    public func models() throws -> [[String: Any]] {
        var models: [[String: Any]] = []
        var cursor: String?
        var seen = Set<String>()
        repeat {
            var params: [String: Any] = ["limit": 100, "includeHidden": false]
            if let cursor { params["cursor"] = cursor }
            let result = try client.request("model/list", params: params)
            guard let page = result["data"] as? [[String: Any]] else { throw ProbeError.invalidResponse }
            models.append(contentsOf: page)
            cursor = result["nextCursor"] as? String
            if let cursor, !seen.insert(cursor).inserted { throw ProbeError.invalidResponse }
        } while cursor != nil
        return models
    }

    public func runProbe(
        account: String, limitID: String, model requestedModel: String?, workspace: URL,
        reportURL: URL, previousURL: URL? = nil, turnTimeout: TimeInterval = 90
    ) throws -> ProbeReport {
        guard turnTimeout.isFinite, turnTimeout > 0 else {
            throw ProbeError.invalidArgument("模型执行超时必须是正数。")
        }
        let before = try readQuota()
        var modelName = requestedModel
        if let previousURL {
            let previous = try ProbeReport.load(from: previousURL)
            guard previous.limitID == limitID else { throw ProbeError.invalidArgument("额度桶与原报告不一致。") }
            try previous.validateContinuation(account: account, snapshot: before)
            if modelName == nil { modelName = previous.model }
        }
        try before.validateForProbe(limitID: limitID)
        let catalog = try models()
        let selected = catalog.first { entry in
            if let modelName { return entry["model"] as? String == modelName }
            return entry["isDefault"] as? Bool == true
        }
        guard let selected, let model = selected["model"] as? String else {
            throw ProbeError.invalidArgument("指定模型未出现在当前目录中；请执行 models 查看。")
        }
        var report = ProbeReport(account: account, limitID: limitID, model: model, before: before, previous: previousURL)
        try report.save(to: reportURL)
        do {
            let threadResult = try client.request("thread/start", params: [
                "model": model, "cwd": workspace.path, "ephemeral": true,
                "sandbox": "read-only", "approvalPolicy": "untrusted", "serviceTier": "default",
                "baseInstructions": "You are a text-only quota probe. Reply exactly OK. Never call tools.",
                "developerInstructions": "Do not read files, execute commands, browse, or modify anything.",
                "serviceName": "codex-pulse-probe"
            ])
            guard let thread = threadResult["thread"] as? [String: Any], let threadID = thread["id"] as? String else {
                throw ProbeError.invalidResponse
            }
            var params: [String: Any] = [
                "threadId": threadID,
                "input": [["type": "text", "text": "只回复 OK，不使用任何工具。"]],
                "serviceTierForTurn": "default"
            ]
            if let efforts = selected["supportedReasoningEfforts"] as? [[String: Any]] {
                let supported = Set(efforts.compactMap { $0["reasoningEffort"] as? String })
                if let effort = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"].first(where: supported.contains) {
                    params["effort"] = effort
                }
            }
            let turnResult = try client.request("turn/start", params: params)
            guard let turn = turnResult["turn"] as? [String: Any], let turnID = turn["id"] as? String else {
                throw ProbeError.invalidResponse
            }
            do {
                try waitForTurn(threadID: threadID, turnID: turnID, timeout: turnTimeout)
            } catch {
                _ = try? client.request("turn/interrupt", params: ["threadId": threadID, "turnId": turnID])
                throw error
            }
            report.after = try readQuota()
            for minutes in [300, 10080] {
                report.observations.append(.compare(
                    before: before.buckets[limitID]?.window(minutes: minutes),
                    after: report.after?.buckets[limitID]?.window(minutes: minutes), minutes: minutes
                ))
            }
            report.status = "completed"
            try report.save(to: reportURL)
            return report
        } catch {
            report.status = "incomplete"
            report.failure = (error as? ProbeError)?.description ?? "本地报告写入失败。"
            try? report.save(to: reportURL)
            throw error
        }
    }

    private func waitForTurn(threadID: String, turnID: String, timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var receivedOK = false
        while true {
            let message = try client.nextNotification(until: deadline) {
                guard let params = $0["params"] as? [String: Any], params["threadId"] as? String == threadID else { return false }
                let turn = params["turn"] as? [String: Any]
                return (params["turnId"] as? String ?? turn?["id"] as? String) == turnID
            }
            guard let params = message["params"] as? [String: Any] else { throw ProbeError.invalidResponse }
            if message["method"] as? String == "turn/completed" {
                guard let turn = params["turn"] as? [String: Any], let status = turn["status"] as? String else {
                    throw ProbeError.invalidResponse
                }
                guard status == "completed" else {
                    throw ProbeError.turnFailed(["failed", "interrupted"].contains(status) ? status : "unknown")
                }
                guard receivedOK else { throw ProbeError.invalidResponse }
                return
            }
            if let item = params["item"] as? [String: Any], let type = item["type"] as? String {
                guard ["agentMessage", "reasoning", "userMessage"].contains(type) else { throw ProbeError.unexpectedTool }
                if type == "agentMessage", message["method"] as? String == "item/completed" {
                    receivedOK = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == "OK"
                }
            }
        }
    }
}
