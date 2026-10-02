import Foundation

public struct AccountStatus: Sendable {
    public let account: ManagedAccount
    public let state: String
    public let snapshot: QuotaSnapshot?
    public let error: String?
    public let username: String?
    public let usernameError: String?

    public init(account: ManagedAccount, state: String, snapshot: QuotaSnapshot?, error: String?,
                username: String? = nil, usernameError: String? = nil) {
        self.account = account
        self.state = state
        self.snapshot = snapshot
        self.error = error
        self.username = username
        self.usernameError = usernameError
    }
}

public struct AccountService: Sendable {
    public let store: AccountStore
    private let makeClient: @Sendable (ProbePaths) throws -> AppServerClient
    private let readUsername: (@Sendable (ProbePaths) throws -> String)?

    public init(store: AccountStore, executable: URL, timeout: TimeInterval = 15,
                readUsername: (@Sendable (ProbePaths) throws -> String)? = nil) {
        self.init(store: store, readUsername: readUsername, makeClient: { paths in
            try AppServerClient(executable: executable, arguments: ProbePaths.serverArguments,
                                codexHome: paths.accountHome, workspace: paths.workspace, timeout: timeout)
        })
    }

    public init(store: AccountStore, readUsername: (@Sendable (ProbePaths) throws -> String)? = nil,
                makeClient: @escaping @Sendable (ProbePaths) throws -> AppServerClient) {
        self.store = store
        self.makeClient = makeClient
        self.readUsername = readUsername
    }

    public func login(id: String, forceReauthentication: Bool = false, cancellation: LoginCancellation? = nil, openURL: (URL) throws -> Void) throws {
        try store.withAccount(id: id) { _, paths in
            let client = try makeClient(paths)
            defer { client.close() }
            try cancellation?.bind(client)
            defer { cancellation?.unbind() }
            try client.initialize()
            if forceReauthentication { _ = try client.request("account/logout", params: nil) }
            try ProbeSession(client: client).login(openURL: openURL)
        }
    }

    private func status(_ account: ManagedAccount) -> AccountStatus {
        do {
            return try store.withAccount(id: account.id) { current, paths in
                let client = try makeClient(paths)
                defer { client.close() }
                try client.initialize()
                let session = ProbeSession(client: client)
                guard let info = try session.readAccount() else {
                    return AccountStatus(account: current, state: "notLoggedIn", snapshot: nil, error: nil)
                }
                guard info["type"] as? String == "chatgpt" else { throw ProbeError.unsupportedAccount }
                var snapshot: QuotaSnapshot?
                var quotaError: String?
                do { snapshot = try session.readQuota() }
                catch { quotaError = message(error) }
                var username: String?
                var usernameError: String?
                if let readUsername {
                    do { username = try readUsername(paths) }
                    catch { usernameError = (error as? ProfileError)?.description ?? ProfileError.transport.description }
                }
                return AccountStatus(account: current, state: snapshot == nil ? "quotaError" : "loggedIn",
                                     snapshot: snapshot, error: quotaError, username: username, usernameError: usernameError)
            }
        } catch {
            return AccountStatus(account: account, state: account.pendingDeletion ? "pendingDeletion" : "error",
                                 snapshot: nil, error: message(error))
        }
    }

    public func status(id: String) throws -> AccountStatus {
        guard let account = try store.list().first(where: { $0.id == id }) else { throw AccountError.notFound }
        return status(account)
    }

    public func statuses() async throws -> [AccountStatus] {
        let accounts = try store.list()
        return await withTaskGroup(of: (Int, AccountStatus).self) { group in
            var iterator = accounts.enumerated().makeIterator()
            for _ in 0..<3 {
                if let (index, account) = iterator.next() { group.addTask { (index, status(account)) } }
            }
            var results: [(Int, AccountStatus)] = []
            for await result in group {
                results.append(result)
                if let (index, account) = iterator.next() { group.addTask { (index, status(account)) } }
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    public static func duplicateAccounts(in statuses: [AccountStatus]) -> [(ManagedAccount, ManagedAccount)] {
        var seen: [String: ManagedAccount] = [:]
        var pairs: [(ManagedAccount, ManagedAccount)] = []
        for status in statuses {
            guard let digest = status.snapshot?.identityDigest else { continue }
            if let first = seen[digest] { pairs.append((first, status.account)) }
            else { seen[digest] = status.account }
        }
        return pairs
    }

    private func message(_ error: Error) -> String {
        if let error = error as? AccountError { return error.description }
        if let error = error as? ProbeError { return error.description }
        return AccountError.storageFailure.description
    }
}
