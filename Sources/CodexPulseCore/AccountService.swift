import Foundation

public struct AccountStatus: Sendable {
    public let account: ManagedAccount
    public let state: String
    public let snapshot: QuotaSnapshot?
    public let error: String?
}

public struct AccountService: Sendable {
    public let store: AccountStore
    private let makeClient: @Sendable (ProbePaths) throws -> AppServerClient

    public init(store: AccountStore, executable: URL, timeout: TimeInterval = 15) {
        self.init(store: store) { paths in
            try AppServerClient(executable: executable, arguments: ProbePaths.serverArguments,
                                codexHome: paths.accountHome, workspace: paths.workspace, timeout: timeout)
        }
    }

    public init(store: AccountStore, makeClient: @escaping @Sendable (ProbePaths) throws -> AppServerClient) {
        self.store = store
        self.makeClient = makeClient
    }

    public func login(id: String, openURL: (URL) throws -> Void) throws {
        try store.withAccount(id: id) { _, paths in
            let client = try makeClient(paths)
            defer { client.close() }
            try client.initialize()
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
                do {
                    let snapshot = try session.readQuota()
                    return AccountStatus(account: current, state: "loggedIn", snapshot: snapshot, error: nil)
                } catch {
                    return AccountStatus(account: current, state: "quotaError", snapshot: nil, error: message(error))
                }
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
            for (index, account) in accounts.enumerated() {
                group.addTask { (index, status(account)) }
            }
            var results: [(Int, AccountStatus)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func message(_ error: Error) -> String {
        if let error = error as? AccountError { return error.description }
        if let error = error as? ProbeError { return error.description }
        return AccountError.storageFailure.description
    }
}
