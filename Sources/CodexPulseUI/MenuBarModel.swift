import CodexPulseCore
import Combine
import Foundation

public struct MenuAccountRow: Identifiable, Sendable {
    public var account: ManagedAccount
    public var status: AccountStatus?
    public var lastSnapshot: QuotaSnapshot?
    public var lastUsername: String?
    public var isStale = false
    public var id: String { account.id }
    public var displayName: String {
        status?.username ?? lastUsername ?? (account.usesGeneratedName == true
            ? PulseLocalization.text("account.pendingName", String(account.id.prefix(8))) : account.name)
    }
    public var snapshot: QuotaSnapshot? { status?.snapshot ?? lastSnapshot }
    public var bucket: QuotaBucket? {
        guard let snapshot else { return nil }
        return snapshot.buckets["codex"] ?? (snapshot.buckets.count == 1 ? snapshot.buckets.values.first : nil)
    }
    public var plan: String { bucket?.planType?.capitalized ?? PulseLocalization.text("status.planUnknown") }
    public var statusText: String {
        if account.pendingDeletion { return PulseLocalization.text("status.pendingDeletion") }
        if isStale { return PulseLocalization.text("status.stale") }
        switch status?.state {
        case "loggedIn": return PulseLocalization.text("status.loggedIn")
        case "notLoggedIn": return PulseLocalization.text("status.notLoggedIn")
        case "quotaError": return PulseLocalization.text("status.quotaError")
        case "pendingDeletion": return PulseLocalization.text("status.pendingDeletion")
        case "error": return PulseLocalization.text("status.error")
        default: return PulseLocalization.text("status.waiting")
        }
    }
}

@MainActor
public final class MenuBarModel: ObservableObject {
    @Published public private(set) var rows: [MenuAccountRow] = []
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var isManagingAccounts = false
    @Published public private(set) var globalError: String?
    @Published public private(set) var lastCompletedAt: Date?
    @Published public private(set) var automaticResults: [String: AutomaticRequestResult] = [:]
    @Published public private(set) var isRunningAutomatic = false
    @Published public private(set) var nextAutomaticCheckAt: Date?
    private var started = false
    private var isSleeping = false
    private var recoveryPending = false
    private var timer: Timer?
    private let readAccounts: @Sendable () async throws -> [ManagedAccount]
    private let readStatuses: @Sendable () async throws -> [AccountStatus]
    private let runAutomatic: (@Sendable ([AccountStatus]) async throws -> [AutomaticRequestResult])?
    private let now: @Sendable () -> Date
    private let timersEnabled: Bool

    public init(
        readAccounts: @escaping @Sendable () async throws -> [ManagedAccount],
        readStatuses: @escaping @Sendable () async throws -> [AccountStatus],
        runAutomatic: (@Sendable ([AccountStatus]) async throws -> [AutomaticRequestResult])? = nil,
        now: @escaping @Sendable () -> Date = { Date() }, timersEnabled: Bool = false
    ) {
        self.readAccounts = readAccounts
        self.readStatuses = readStatuses
        self.runAutomatic = runAutomatic
        self.now = now
        self.timersEnabled = timersEnabled
    }

    public static func live(store: AccountStore = AccountStore()) -> MenuBarModel {
        MenuBarModel(readAccounts: {
            try await Task.detached(priority: .userInitiated) { try store.list() }.value
        }, readStatuses: {
            try await Task.detached(priority: .userInitiated) {
                let executable = try CodexExecutable.resolve()
                return try await AccountService(store: store, executable: executable, readUsername: {
                    try AccountProfileClient().readUsername(paths: $0)
                }).statuses()
            }.value
        }, runAutomatic: { statuses in
            try await Task.detached(priority: .utility) {
                let executable = try CodexExecutable.resolve()
                return await AutomaticRequestService(store: store, executable: executable).run(statuses: statuses)
            }.value
        }, timersEnabled: true)
    }

    public func startIfNeeded() async {
        guard !started else { return }
        started = true
        await refresh()
    }

    public func refresh() async {
        guard !isRefreshing, !isSleeping, !isManagingAccounts else { return }
        started = true
        isRefreshing = true
        globalError = nil
        timer?.invalidate()
        timer = nil
        defer {
            isRunningAutomatic = false
            isRefreshing = false
            scheduleNextCheck()
            if recoveryPending {
                recoveryPending = false
                Task { await self.refresh() }
            }
        }
        do {
            let accounts = try await readAccounts()
            let previous = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            rows = accounts.map { account in
                let saved = previous[account.id].flatMap { $0.account.createdAt == account.createdAt ? $0 : nil }
                var row = saved ?? MenuAccountRow(account: account)
                row.account = account
                return row
            }
            let accountIDs = Set(accounts.map(\.id))
            automaticResults = automaticResults.filter { accountIDs.contains($0.key) }
            if accounts.isEmpty { lastCompletedAt = now(); return }
            let statuses = try await readStatuses()
            let current = Dictionary(uniqueKeysWithValues: statuses.map { ($0.account.id, $0) })
            rows = accounts.map { account in
                let saved = previous[account.id].flatMap { $0.account.createdAt == account.createdAt ? $0 : nil }
                var row = saved ?? MenuAccountRow(account: account)
                row.account = account
                row.status = current[account.id]
                if let username = row.status?.username {
                    if let previousName = row.lastUsername, previousName != username, row.status?.snapshot == nil {
                        row.lastSnapshot = nil
                    }
                    row.lastUsername = username
                }
                else if row.status?.state == "notLoggedIn" { row.lastUsername = nil; row.lastSnapshot = nil }
                if let oldIdentity = row.lastSnapshot?.identityDigest, let newIdentity = row.status?.snapshot?.identityDigest,
                   oldIdentity != newIdentity, row.status?.username == nil { row.lastUsername = nil }
                if let snapshot = row.status?.snapshot {
                    row.lastSnapshot = snapshot
                    row.isStale = false
                } else {
                    row.isStale = row.lastSnapshot != nil
                }
                return row
            }
            if let runAutomatic, !isSleeping {
                isRunningAutomatic = true
                let results = try await runAutomatic(statuses)
                automaticResults = Dictionary(uniqueKeysWithValues: results.map { ($0.accountID, $0) })
                for index in rows.indices {
                    guard let snapshot = automaticResults[rows[index].id]?.snapshot else { continue }
                    let previous = rows[index].status
                    let sameIdentity = previous?.snapshot?.identityDigest == snapshot.identityDigest
                    if !sameIdentity { rows[index].lastUsername = nil }
                    rows[index].status = AccountStatus(account: rows[index].account, state: "loggedIn", snapshot: snapshot,
                        error: nil, username: sameIdentity ? previous?.username : nil, usernameError: previous?.usernameError)
                    rows[index].lastSnapshot = snapshot
                    rows[index].isStale = false
                }
            }
            lastCompletedAt = now()
        } catch {
            globalError = Self.message(error)
            for index in rows.indices { rows[index].isStale = true }
            automaticResults = Dictionary(uniqueKeysWithValues: rows.map {
                ($0.id, AutomaticRequestResult(accountID: $0.id, message: PulseLocalization.text("automatic.queryFailed")))
            })
        }
    }

    public func beginAccountManagement() -> Bool {
        guard !isRefreshing, !isManagingAccounts else { return false }
        isManagingAccounts = true
        timer?.invalidate()
        timer = nil
        nextAutomaticCheckAt = nil
        return true
    }

    public func showRegisteredAccount(_ account: ManagedAccount) {
        rows.append(MenuAccountRow(account: account))
    }

    public func removeRegisteredAccount(id: String) {
        rows.removeAll { $0.id == id }
        automaticResults.removeValue(forKey: id)
    }

    public func clearAccountCache(id: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index] = MenuAccountRow(account: rows[index].account)
        automaticResults.removeValue(forKey: id)
    }

    public func endAccountManagement() async {
        isManagingAccounts = false
        await refresh()
    }

    public func suspendForSleep() {
        isSleeping = true
        timer?.invalidate()
        timer = nil
        nextAutomaticCheckAt = nil
    }

    public func resumeAfterWake() async {
        isSleeping = false
        if isRefreshing { recoveryPending = true; return }
        await refresh()
    }

    private func scheduleNextCheck() {
        timer?.invalidate()
        timer = nil
        nextAutomaticCheckAt = nil
        guard runAutomatic != nil, !isSleeping, !isManagingAccounts else { return }
        let date = now()
        guard let next = automaticResults.values.compactMap(\.nextRequestAt).filter({ $0 > date }).min() else { return }
        nextAutomaticCheckAt = next
        guard timersEnabled else { return }
        let timer = Timer(timeInterval: max(1, next.timeIntervalSince(date)), repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public var duplicateNames: [String] {
        let names = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.displayName) })
        return AccountService.duplicateAccounts(in: rows.filter { !$0.isStale }.compactMap(\.status))
            .map { PulseLocalization.text("status.duplicatePair", names[$0.0.id] ?? $0.0.name, names[$0.1.id] ?? $0.1.name) }
    }

    private static func message(_ error: Error) -> String {
        if let error = error as? AccountError { return error.description }
        if let error = error as? ProbeError {
            if case .codexNotInstalled = error { return PulseLocalization.text("account.cliMissingRefresh") }
            return error.description
        }
        return PulseLocalization.text("ui.queryFailed")
    }
}
