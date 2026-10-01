import Foundation
import Darwin

public enum AccountError: Error, CustomStringConvertible {
    case invalidName, duplicateID, accountLimit, notFound, deleting, busy, invalidStorage, storageFailure

    public var description: String {
        switch self {
        case .invalidName: "账号别名须为 1～64 个可显示字符。"
        case .duplicateID: "该账号 ID 已在列表中。"
        case .accountLimit: "最多管理三个账号，请先删除不再使用的账号。"
        case .notFound: "账号 ID 不在管理列表中。"
        case .deleting: "账号正在删除；请再次执行 remove 完成本地清理。"
        case .busy: "账号或列表正在被另一操作使用，请稍后再试。"
        case .invalidStorage: "本地账号存储无效或目录不安全；未覆盖原文件。"
        case .storageFailure: "本地账号文件操作失败；未输出凭据或原始文件内容。"
        }
    }
}

/// ID 固定对应 CODEX_HOME；别名仅用于显示，不参与路径拼接。
public struct ManagedAccount: Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public let createdAt: Date
    public var pendingDeletion: Bool

    public init(id: String, name: String, createdAt: Date = Date(), pendingDeletion: Bool = false) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.pendingDeletion = pendingDeletion
    }
}

private struct AccountRegistry: Codable {
    var schemaVersion = 1
    var accounts: [ManagedAccount] = []
}

enum PrivateStorage {
    static func directory(_ url: URL) throws {
        let official = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").resolvingSymlinksInPath().path
        let resolved = url.resolvingSymlinksInPath().path
        guard resolved != official, !resolved.hasPrefix(official + "/") else { throw AccountError.invalidStorage }
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFDIR else { throw AccountError.invalidStorage }
        } else {
            guard errno == ENOENT else { throw AccountError.storageFailure }
            do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
            catch { throw AccountError.storageFailure }
        }
        guard chmod(url.path, 0o700) == 0 else { throw AccountError.storageFailure }
    }

    static func regularFile(_ url: URL) throws -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            if errno == ENOENT { return false }
            throw AccountError.storageFailure
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { throw AccountError.invalidStorage }
        return true
    }
}

/// flock 同时保护不同进程；非阻塞获取，避免长时间登录阻塞其他操作。
public final class AccountLease {
    private let descriptor: Int32

    init(file: URL, wait: TimeInterval = 0) throws {
        let candidate = open(file.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard candidate >= 0 else { throw AccountError.invalidStorage }
        var info = stat()
        guard fstat(candidate, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1, fchmod(candidate, 0o600) == 0 else {
            close(candidate)
            throw AccountError.invalidStorage
        }
        let deadline = ProcessInfo.processInfo.systemUptime + wait
        while flock(candidate, LOCK_EX | LOCK_NB) != 0 {
            let lockError = errno
            guard lockError == EWOULDBLOCK || lockError == EAGAIN else {
                close(candidate)
                throw AccountError.storageFailure
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                close(candidate)
                throw AccountError.busy
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        descriptor = candidate
    }

    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

public struct AccountStore: Sendable {
    public let root: URL

    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexPulse")
    }

    private var registryURL: URL { root.appendingPathComponent("account-list.json") }

    private func locked<T>(_ body: (inout AccountRegistry) throws -> T) throws -> T {
        try PrivateStorage.directory(root)
        let lease = try AccountLease(file: root.appendingPathComponent("account-list.lock"), wait: 1)
        defer { withExtendedLifetime(lease) {} }
        var registry = AccountRegistry()
        if try PrivateStorage.regularFile(registryURL) {
            do { registry = try JSONDecoder().decode(AccountRegistry.self, from: Data(contentsOf: registryURL)) }
            catch { throw AccountError.invalidStorage }
            guard registry.schemaVersion == 1, registry.accounts.count <= 3,
                  Set(registry.accounts.map(\.id)).count == registry.accounts.count else { throw AccountError.invalidStorage }
            for account in registry.accounts {
                _ = try ProbePaths(account: account.id, root: root)
                try validateName(account.name)
            }
        }
        return try body(&registry)
    }

    private func save(_ registry: AccountRegistry) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(registry).write(to: registryURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: registryURL.path)
        } catch { throw AccountError.storageFailure }
    }

    private func validateName(_ name: String) throws {
        guard !name.isEmpty, name.count <= 64,
              name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw AccountError.invalidName }
    }

    public func list() throws -> [ManagedAccount] { try locked { $0.accounts } }

    @discardableResult
    public func add(name: String, id: String = UUID().uuidString.lowercased()) throws -> ManagedAccount {
        try validateName(name)
        _ = try ProbePaths(account: id, root: root)
        return try locked { registry in
            guard !registry.accounts.contains(where: { $0.id == id }) else { throw AccountError.duplicateID }
            guard registry.accounts.count < 3 else { throw AccountError.accountLimit }
            let account = ManagedAccount(id: id, name: name, createdAt: Date(), pendingDeletion: false)
            registry.accounts.append(account)
            try save(registry)
            return account
        }
    }

    public func rename(id: String, name: String) throws {
        try validateName(name)
        try locked { registry in
            guard let index = registry.accounts.firstIndex(where: { $0.id == id }) else { throw AccountError.notFound }
            guard !registry.accounts[index].pendingDeletion else { throw AccountError.deleting }
            registry.accounts[index].name = name
            try save(registry)
        }
    }

    /// 持有账号租约至会话结束，删除不能与登录、查询或 probe 并行操作同一目录。
    public func withAccount<T>(id: String, _ body: (ManagedAccount, ProbePaths) throws -> T) throws -> T {
        let paths = try ProbePaths(account: id, root: root)
        let lease = try paths.acquireLease()
        defer { withExtendedLifetime(lease) {} }
        let account = try locked { registry in
            guard let account = registry.accounts.first(where: { $0.id == id }) else { throw AccountError.notFound }
            guard !account.pendingDeletion else { throw AccountError.deleting }
            return account
        }
        try paths.prepare()
        return try body(account, paths)
    }

    public func remove(id: String) throws {
        let paths = try ProbePaths(account: id, root: root)
        let lease = try paths.acquireLease()
        defer { withExtendedLifetime(lease) {} }
        try locked { registry in
            guard let index = registry.accounts.firstIndex(where: { $0.id == id }) else { throw AccountError.notFound }
            // 先持久化删除标记。崩溃或清理失败时保留该项，禁止启动会话，可重试清理。
            registry.accounts[index].pendingDeletion = true
            try save(registry)
            try PrivateStorage.directory(root.appendingPathComponent("accounts"))
            var info = stat()
            if lstat(paths.accountHome.path, &info) == 0 {
                guard info.st_mode & S_IFMT == S_IFDIR else { throw AccountError.invalidStorage }
                do { try FileManager.default.removeItem(at: paths.accountHome) }
                catch { throw AccountError.storageFailure }
            } else if errno != ENOENT { throw AccountError.storageFailure }
            registry.accounts.remove(at: index)
            try save(registry)
        }
    }
}
