import Foundation
import Darwin

public enum ProbeError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case codexNotInstalled
    case notLoggedIn
    case loginFailed
    case unsupportedAccount
    case unknownQuota
    case exhaustedQuota
    case invalidResponse
    case rpc(String, Int)
    case timeout(String)
    case processExited
    case launchFailed
    case unexpectedTool
    case turnFailed(String)

    public var description: String {
        switch self {
        case .invalidArgument(let message): message
        case .codexNotInstalled: PulseLocalization.text("error.probe.cliMissing")
        case .notLoggedIn: PulseLocalization.text("error.probe.notLoggedIn")
        case .loginFailed: PulseLocalization.text("error.probe.loginFailed")
        case .unsupportedAccount: PulseLocalization.text("error.probe.unsupported")
        case .unknownQuota: PulseLocalization.text("error.probe.unknownQuota")
        case .exhaustedQuota: PulseLocalization.text("error.probe.exhausted")
        case .invalidResponse: PulseLocalization.text("error.probe.invalidResponse")
        case .rpc(let method, let code): PulseLocalization.text("error.probe.rpc", method, code)
        case .timeout(let operation): PulseLocalization.text("error.probe.timeout", operation)
        case .processExited: PulseLocalization.text("error.probe.processExited")
        case .launchFailed: PulseLocalization.text("error.probe.launchFailed")
        case .unexpectedTool: PulseLocalization.text("error.probe.unexpectedTool")
        case .turnFailed(let status): PulseLocalization.text("error.probe.turnFailed", status)
        }
    }
}

/// 同步调用入口；读取线程只通过 condition 访问接收状态，写入由 writeLock 串行保护。
public final class AppServerClient: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let condition = NSCondition()
    private let operationLock = NSLock()
    private let writeLock = NSLock()
    private let termination = DispatchSemaphore(value: 0)
    private var responses: [String: [String: Any]] = [:]
    private var notifications: [[String: Any]] = []
    private var failure: ProbeError?
    private var nextID = 0
    private var closed = false
    private var closeFinished = false
    public let timeout: TimeInterval
    public var isRunning: Bool { process.isRunning }

    public init(
        executable: URL, arguments: [String], codexHome: URL, workspace: URL,
        timeout: TimeInterval = 15
    ) throws {
        guard timeout.isFinite, timeout > 0 else {
            throw ProbeError.invalidArgument(PulseLocalization.text("error.probe.positiveTimeout"))
        }
        self.timeout = timeout
        var environment = ProcessInfo.processInfo.environment
        for key in [
            "OPENAI_API_KEY", "CODEX_API_KEY", "CODEX_ACCESS_TOKEN", "OPENAI_ACCESS_TOKEN",
            "OPENAI_IDENTITY_TOKEN_FILE", "OPENAI_IDENTITY_TOKEN_AUDIENCE",
            "OPENAI_BEARER_TOKEN", "OPENAI_ORGANIZATION", "OPENAI_PROJECT"
        ] {
            environment.removeValue(forKey: key)
        }
        // GUI 进程的 PATH 可能不包含 Node 安装目录，npm CLI 的 env node 需同目录运行时。
        environment["PATH"] = executable.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        environment["CODEX_HOME"] = codexHome.path
        process.environment = environment
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workspace
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        let termination = self.termination
        process.terminationHandler = { _ in termination.signal() }
        do { try process.run() } catch { throw ProbeError.launchFailed }
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
        DispatchQueue.global(qos: .utility).async { [self] in readOutput() }
        // stderr 仅排空，防止管道阻塞；不保存可能含认证信息的原始日志。
        let errorHandle = errors.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            while !errorHandle.availableData.isEmpty {}
        }
    }

    public func initialize() throws {
        _ = try request("initialize", params: ["clientInfo": [
            "name": "codex-pulse", "title": "Codex Pulse", "version": "0.1.0"
        ]])
        try write(["method": "initialized", "params": [:]])
    }

    public func request(_ method: String, params: [String: Any]? = [:]) throws -> [String: Any] {
        operationLock.lock()
        defer { operationLock.unlock() }
        nextID += 1
        let id = String(nextID)
        try write(["id": id, "method": method, "params": params as Any? ?? NSNull()])
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let message = responses.removeValue(forKey: id) {
                if let error = message["error"] as? [String: Any] {
                    throw ProbeError.rpc(method, (error["code"] as? Int) ?? -1)
                }
                guard let result = message["result"] as? [String: Any] else {
                    throw ProbeError.invalidResponse
                }
                return result
            }
            if let failure { throw failure }
            guard condition.wait(until: deadline) else { throw ProbeError.timeout(method) }
        }
    }

    public func nextNotification(
        until deadline: Date, matching predicate: ([String: Any]) -> Bool
    ) throws -> [String: Any] {
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let index = notifications.firstIndex(where: predicate) {
                return notifications.remove(at: index)
            }
            if let failure { throw failure }
            guard condition.wait(until: deadline) else { throw ProbeError.timeout(PulseLocalization.text("error.probe.waitNotification")) }
        }
    }

    public func close() {
        condition.lock()
        if closed {
            // 取消登录与会话 defer 可能同时关闭；必须等进程退出后才释放账号租约。
            while !closeFinished { condition.wait() }
            condition.unlock()
            return
        }
        closed = true
        failure = .processExited
        condition.broadcast()
        condition.unlock()
        writeLock.lock()
        try? input.fileHandleForWriting.close()
        writeLock.unlock()
        if process.isRunning, termination.wait(timeout: .now() + 1) == .timedOut {
            if process.isRunning { process.terminate() }
            if termination.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                // 仅结束本实例创建并持有的子进程。
                kill(process.processIdentifier, SIGKILL)
                _ = termination.wait(timeout: .now() + 1)
            }
        }
        condition.lock()
        closeFinished = true
        condition.broadcast()
        condition.unlock()
    }

    private func write(_ message: [String: Any]) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        do {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: data)
        } catch { throw ProbeError.processExited }
    }

    private func readOutput() {
        var buffer = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty {
                fail(buffer.isEmpty ? .processExited : .invalidResponse)
                return
            }
            buffer.append(chunk)
            guard buffer.count <= 4 * 1024 * 1024 else { fail(.invalidResponse); return }
            while let end = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<end])
                buffer.removeSubrange(...end)
                if line.isEmpty { continue }
                guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
                else { fail(.invalidResponse); return }
                if let id = message["id"], message["method"] != nil {
                    // 不执行服务端提出的命令、文件操作或交互请求。
                    try? write(["id": id, "error": ["code": -32601, "message": "Probe rejects tool requests"]])
                    fail(.unexpectedTool)
                    return
                }
                condition.lock()
                if let id = message["id"] {
                    responses[String(describing: id)] = message
                } else if let method = message["method"] as? String,
                          ["account/login/completed", "turn/completed", "item/started", "item/completed"].contains(method) {
                    notifications.append(message)
                }
                if responses.count + notifications.count > 512 { failure = .invalidResponse }
                condition.broadcast()
                condition.unlock()
            }
        }
    }

    private func fail(_ error: ProbeError) {
        condition.lock()
        if failure == nil { failure = error }
        condition.broadcast()
        condition.unlock()
    }
}
