import Foundation

public struct AutomaticRequestResult: Sendable {
    public let accountID: String
    public let message: String
    public let nextRequestAt: Date?
    public let lastAttemptAt: Date?
    public let snapshot: QuotaSnapshot?

    public init(accountID: String, message: String, nextRequestAt: Date? = nil,
                lastAttemptAt: Date? = nil, snapshot: QuotaSnapshot? = nil) {
        self.accountID = accountID
        self.message = message
        self.nextRequestAt = nextRequestAt
        self.lastAttemptAt = lastAttemptAt
        self.snapshot = snapshot
    }
}

private struct AutomaticCheckpoint: Codable {
    var schemaVersion = 1
    let createdAt: Date
    let identityDigest: String
    let attemptedAt: Date
    var nextReset: Int64?
    var outcome: String
}

/// 每个账号的查询、检查点写入和最小请求共用账号租约，防止跨进程重复请求。
public struct AutomaticRequestService: Sendable {
    public let store: AccountStore
    private let makeClient: @Sendable (ProbePaths) throws -> AppServerClient
    private let now: @Sendable () -> Date
    private let turnTimeout: TimeInterval

    public init(store: AccountStore, executable: URL) {
        self.init(store: store, makeClient: { paths in
            try AppServerClient(executable: executable, arguments: ProbePaths.serverArguments,
                                codexHome: paths.accountHome, workspace: paths.workspace)
        })
    }

    public init(store: AccountStore, now: @escaping @Sendable () -> Date = { Date() }, turnTimeout: TimeInterval = 90,
                makeClient: @escaping @Sendable (ProbePaths) throws -> AppServerClient) {
        self.store = store
        self.now = now
        self.turnTimeout = turnTimeout
        self.makeClient = makeClient
    }

    public func run(statuses: [AccountStatus]) async -> [AutomaticRequestResult] {
        var seen = Set<String>()
        var permitted = Set<String>()
        for status in statuses where status.state == "loggedIn" {
            if let identity = status.snapshot?.identityDigest, seen.insert(identity).inserted {
                permitted.insert(status.account.id)
            }
        }
        let allowed = permitted
        return await withTaskGroup(of: (Int, AutomaticRequestResult).self) { group in
            for (index, status) in statuses.enumerated() {
                group.addTask {
                    guard allowed.contains(status.account.id), let identity = status.snapshot?.identityDigest else {
                        return (index, AutomaticRequestResult(accountID: status.account.id,
                            message: status.state == "loggedIn" && status.snapshot?.identityDigest != nil
                                ? "重复登录，自动请求暂停" : "账号或额度状态未知，自动请求暂停"))
                    }
                    return (index, process(id: status.account.id, expectedIdentity: identity))
                }
            }
            var results: [(Int, AutomaticRequestResult)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    public func process(id: String, expectedIdentity: String) -> AutomaticRequestResult {
        do {
            return try store.withAccount(id: id) { account, paths in
                let client = try makeClient(paths)
                defer { client.close() }
                try client.initialize()
                let session = ProbeSession(client: client)
                let snapshot = try session.readQuota()
                guard snapshot.identityDigest == expectedIdentity else {
                    return AutomaticRequestResult(accountID: id, message: "账号身份已变化，自动请求暂停", snapshot: snapshot)
                }
                let checkpointURL = try checkpointFile(paths: paths)
                var checkpoint = try load(at: checkpointURL)
                if checkpoint?.createdAt != account.createdAt || checkpoint?.identityDigest != expectedIdentity { checkpoint = nil }
                let date = now()
                let bucket = snapshot.buckets["codex"]
                guard let five = bucket?.window(minutes: 300), let weekly = bucket?.window(minutes: 10080),
                      let reset = five.resetsAt else {
                    return result(id, "额度窗口或重置时间未知，自动请求暂停", snapshot, checkpoint)
                }
                if weekly.usedPercent >= 100 { return result(id, "周额度已耗尽，自动请求停止", snapshot, checkpoint) }
                if five.usedPercent >= 100 {
                    return result(id, "五小时额度已耗尽，等待重置", snapshot, checkpoint,
                                  next: future(reset, at: date))
                }
                do { try snapshot.validateForProbe(limitID: "codex") }
                catch { return result(id, message(error), snapshot, checkpoint) }
                if var saved = checkpoint {
                    if saved.nextReset == nil {
                        // 崩溃或超时可能已发出请求；只采纳新读取的服务端窗口，不补发。
                        saved.nextReset = future(reset, at: date).map { Int64($0.timeIntervalSince1970) }
                        try save(saved, to: checkpointURL)
                        return result(id, saved.outcome == "completed" ? "请求已完成，等待服务端重置" : "上次请求结果待确认，等待服务端重置", snapshot, saved,
                                      next: future(reset, at: date))
                    }
                    if let nextReset = saved.nextReset, Double(nextReset) > date.timeIntervalSince1970 {
                        let next = future(reset, at: date) ?? Date(timeIntervalSince1970: Double(nextReset))
                        saved.nextReset = Int64(next.timeIntervalSince1970)
                        try save(saved, to: checkpointURL)
                        return result(id, saved.outcome == "completed" ? "自动请求已就绪" : "上次请求未确认，等待重置",
                                      snapshot, saved, next: next)
                    }
                }
                var attempt = AutomaticCheckpoint(createdAt: account.createdAt, identityDigest: expectedIdentity,
                    attemptedAt: date, nextReset: future(reset, at: date).map { Int64($0.timeIntervalSince1970) }, outcome: "pending")
                // 必须先写入检查点；写入失败时不发送模型请求。
                try save(attempt, to: checkpointURL)
                do {
                    let report = try session.runProbe(account: id, limitID: "codex", model: nil, workspace: paths.workspace,
                        reportURL: paths.reports.appendingPathComponent("automatic-latest.json"),
                        turnTimeout: turnTimeout, expectedIdentity: expectedIdentity)
                    guard let after = report.after, after.identityDigest == expectedIdentity else { throw ProbeError.invalidResponse }
                    attempt.nextReset = after.buckets["codex"]?.window(minutes: 300)?.resetsAt
                        .flatMap { future($0, at: now()).map { Int64($0.timeIntervalSince1970) } }
                    attempt.outcome = "completed"
                    try save(attempt, to: checkpointURL)
                    if after.buckets["codex"]?.window(minutes: 10080)?.usedPercent == 100 {
                        return result(id, "请求完成；周额度已耗尽，自动请求停止", after, attempt)
                    }
                    return result(id, attempt.nextReset == nil ? "请求完成；下次重置未知，自动请求暂停" : "最小请求已完成",
                                  after, attempt, next: attempt.nextReset.map { Date(timeIntervalSince1970: Double($0)) })
                } catch {
                    // 失败也留下已尝试记录；同一窗口不重试，不输出原始错误或响应。
                    attempt.outcome = "incomplete"
                    try save(attempt, to: checkpointURL)
                    return result(id, message(error), snapshot, attempt,
                                  next: attempt.nextReset.flatMap { future($0, at: now()) })
                }
            }
        } catch {
            return AutomaticRequestResult(accountID: id, message: message(error))
        }
    }

    private func result(_ id: String, _ text: String, _ snapshot: QuotaSnapshot,
                        _ checkpoint: AutomaticCheckpoint?, next: Date? = nil) -> AutomaticRequestResult {
        AutomaticRequestResult(accountID: id, message: text, nextRequestAt: next,
                               lastAttemptAt: checkpoint?.attemptedAt, snapshot: snapshot)
    }

    private func future(_ reset: Int64, at date: Date) -> Date? {
        Double(reset) > date.timeIntervalSince1970 ? Date(timeIntervalSince1970: Double(reset)) : nil
    }

    private func checkpointFile(paths: ProbePaths) throws -> URL {
        let directory = paths.root.appendingPathComponent("scheduling")
        try PrivateStorage.directory(directory)
        return directory.appendingPathComponent("\(paths.accountHome.lastPathComponent).json")
    }

    private func load(at url: URL) throws -> AutomaticCheckpoint? {
        guard try PrivateStorage.regularFile(url) else { return nil }
        guard let data = try? Data(contentsOf: url), data.count <= 1_048_576,
              let checkpoint = try? JSONDecoder().decode(AutomaticCheckpoint.self, from: data),
              checkpoint.schemaVersion == 1, ["pending", "completed", "incomplete"].contains(checkpoint.outcome),
              checkpoint.nextReset.map({ $0 > 0 }) ?? true else { throw AccountError.invalidStorage }
        return checkpoint
    }

    private func save(_ checkpoint: AutomaticCheckpoint, to url: URL) throws {
        _ = try PrivateStorage.regularFile(url)
        do {
            try JSONEncoder().encode(checkpoint).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { throw AccountError.storageFailure }
    }

    private func message(_ error: Error) -> String {
        if let error = error as? ProbeError { return error.description }
        if let error = error as? AccountError { return error.description }
        return "自动请求失败，已暂停；未自动重试。"
    }
}
