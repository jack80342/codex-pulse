import CodexPulseCore
import CodexPulseUI
import Foundation
import Testing

private actor FixtureLoader {
    var accounts: [ManagedAccount]
    var statuses: [AccountStatus]
    var fail = false
    var calls = 0

    init(_ statuses: [AccountStatus]) {
        self.statuses = statuses
        accounts = statuses.map(\.account)
    }

    func list() -> [ManagedAccount] { accounts }
    func fetch() throws -> [AccountStatus] {
        calls += 1
        if fail { throw AccountError.invalidStorage }
        return statuses
    }
    func update(_ statuses: [AccountStatus], removeMissing: Bool = false) {
        self.statuses = statuses
        if removeMissing { accounts = statuses.map(\.account) }
    }
    func failNext() { fail = true }
}

private actor RefreshGate {
    var calls = 0
    private var pending: CheckedContinuation<[AccountStatus], Never>?
    private var started: CheckedContinuation<Void, Never>?

    func fetch() async -> [AccountStatus] {
        calls += 1
        return await withCheckedContinuation { continuation in
            pending = continuation
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(_ statuses: [AccountStatus]) { pending?.resume(returning: statuses); pending = nil }
}

@MainActor
struct MenuBarModelTests {
    private func status(_ id: String, used: Double? = 40, identity: String? = nil, username: String? = nil) throws -> AccountStatus {
        let windows = used.map { ",\"primary\":{\"usedPercent\":\($0),\"windowDurationMins\":300,\"resetsAt\":1900000000}" } ?? ""
        let plan = used == nil ? "free" : "plus"
        let data = Data("{\"accountId\":\"\(identity ?? id)\",\"ordinaryUsageAllowed\":true,\"rateLimitsByLimitId\":{\"codex\":{\"planType\":\"\(plan)\"\(windows)}}}".utf8)
        let snapshot = try QuotaSnapshot.decode(data)
        return AccountStatus(account: ManagedAccount(id: id, name: id), state: "loggedIn", snapshot: snapshot, error: nil, username: username)
    }

    private func model(_ loader: FixtureLoader) -> MenuBarModel {
        MenuBarModel(readAccounts: { await loader.list() }, readStatuses: { try await loader.fetch() })
    }

    @Test
    func testProfileNameUpdatesDynamicallyAndFailureKeepsLastNameAndQuota() async throws {
        let first = try status("alias", username: "first-user")
        let loader = FixtureLoader([first])
        let model = model(loader)
        await model.refresh()
        #expect(model.rows[0].displayName == "first-user")
        await loader.update([AccountStatus(account: first.account, state: "loggedIn", snapshot: first.snapshot,
                                          error: nil, username: "renamed-user")])
        await model.refresh()
        #expect(model.rows[0].displayName == "renamed-user")
        await loader.update([AccountStatus(account: first.account, state: "loggedIn", snapshot: first.snapshot,
                                          error: nil, usernameError: "资料连接失败")])
        await model.refresh()
        #expect(model.rows[0].displayName == "renamed-user")
        #expect(model.rows[0].snapshot != nil)
        #expect(model.rows[0].status?.usernameError == "资料连接失败")
        #expect(model.rows[0].account.name == "alias")
    }

    @Test
    func testSwitchedIdentityDoesNotUsePreviousProfileName() async throws {
        let first = try status("alias", identity: "first", username: "first-user")
        let loader = FixtureLoader([first])
        let model = model(loader)
        await model.refresh()
        let changed = try status("alias", identity: "second")
        await loader.update([AccountStatus(account: first.account, state: "loggedIn", snapshot: changed.snapshot,
                                          error: nil, usernameError: "资料连接失败")])
        await model.refresh()
        #expect(model.rows[0].displayName == "alias")
        #expect(model.rows[0].lastUsername == nil)
    }

    @Test
    func testNewProfileNameWithFailedQuotaClearsOldQuota() async throws {
        let first = try status("alias", username: "first-user")
        let loader = FixtureLoader([first])
        let model = model(loader)
        await model.refresh()
        await loader.update([AccountStatus(account: first.account, state: "quotaError", snapshot: nil,
                                          error: "额度读取失败", username: "second-user")])
        await model.refresh()
        #expect(model.rows[0].displayName == "second-user")
        #expect(model.rows[0].snapshot == nil)
    }

    @Test
    func testFreeWindowsRemainUnknownAndDoNotBecomeZero() async throws {
        let loader = FixtureLoader([try status("plus"), try status("free", used: nil)])
        let model = model(loader)
        await model.refresh()
        #expect(model.rows.map(\.plan) == ["Plus", "Free"])
        #expect(model.rows[1].bucket?.window(minutes: 300) == nil)
        #expect(model.rows[1].bucket?.window(minutes: 10080) == nil)
        #expect(model.rows[1].statusText == "已登录")
        #expect(!model.rows[1].isStale)
    }

    @Test
    func testPartialFailureRetainsLastSuccessAndOtherAccountUpdates() async throws {
        let first = try status("a")
        let loader = FixtureLoader([first, try status("b")])
        let model = model(loader)
        await model.refresh()
        let failed = AccountStatus(account: first.account, state: "quotaError", snapshot: nil, error: "额度查询超时")
        await loader.update([failed, try status("b", used: 15)])
        await model.refresh()
        #expect(model.rows[0].snapshot?.buckets["codex"]?.window(minutes: 300)?.usedPercent == 40)
        #expect(model.rows[0].isStale)
        #expect(model.rows[0].status?.error == "额度查询超时")
        #expect(model.rows[0].statusText == "数据未更新")
        #expect(model.rows[1].snapshot?.buckets["codex"]?.window(minutes: 300)?.usedPercent == 15)
        #expect(!model.rows[1].isStale)
    }

    @Test
    func testGlobalFailureKeepsRowsAndMarksThemStale() async throws {
        let loader = FixtureLoader([try status("a")])
        let model = model(loader)
        await model.refresh()
        let lastCompletedAt = model.lastCompletedAt
        await loader.failNext()
        await model.refresh()
        #expect(model.globalError != nil)
        #expect(model.rows.count == 1)
        #expect(model.rows[0].isStale)
        #expect(model.lastCompletedAt == lastCompletedAt)
        #expect(!model.isRefreshing)
    }

    @Test
    func testRemovedAccountDoesNotLeaveCachedCard() async throws {
        let loader = FixtureLoader([try status("a"), try status("b")])
        let model = model(loader)
        await model.refresh()
        await loader.update([try status("b", used: 20)], removeMissing: true)
        await model.refresh()
        #expect(model.rows.map(\.id) == ["b"])
        #expect(model.rows[0].snapshot?.buckets["codex"]?.window(minutes: 300)?.usedPercent == 20)
    }

    @Test
    func testRecreatedIDDoesNotReusePreviousAccountsSnapshot() async throws {
        let original = try status("a", username: "old-user")
        let loader = FixtureLoader([original])
        let model = model(loader)
        await model.refresh()
        let recreated = ManagedAccount(id: "a", name: "新账号", createdAt: original.account.createdAt.addingTimeInterval(1))
        await loader.update([AccountStatus(account: recreated, state: "notLoggedIn", snapshot: nil, error: nil)], removeMissing: true)
        await model.refresh()
        #expect(model.rows[0].snapshot == nil)
        #expect(model.rows[0].statusText == "未登录")
        #expect(model.rows[0].displayName == "新账号")
        #expect(model.rows[0].lastUsername == nil)
    }

    @Test
    func testSecondRefreshWhileBusyDoesNotStartAnotherQuery() async throws {
        let account = ManagedAccount(id: "a", name: "A")
        let gate = RefreshGate()
        let model = MenuBarModel(readAccounts: { [account] }, readStatuses: { await gate.fetch() })
        let running = Task { await model.refresh() }
        await gate.waitUntilStarted()
        #expect(model.isRefreshing)
        await model.refresh()
        #expect(await gate.calls == 1)
        await gate.finish([try status("a")])
        await running.value
        #expect(!model.isRefreshing)
    }

    @Test
    func testReopeningPanelDoesNotAutoQueryAgainButManualRefreshDoes() async throws {
        let loader = FixtureLoader([try status("a")])
        let model = model(loader)
        await model.startIfNeeded()
        await model.startIfNeeded()
        #expect(await loader.calls == 1)
        await model.refresh()
        #expect(await loader.calls == 2)
    }

    @Test
    func testMissingExecutableShowsActionableMessageWithoutCLIFlags() async {
        let account = ManagedAccount(id: "a", name: "A")
        let model = MenuBarModel(readAccounts: { [account] }, readStatuses: { throw ProbeError.codexNotInstalled })
        await model.refresh()
        #expect(model.globalError?.contains("Codex CLI") == true)
        #expect(model.globalError?.contains("--codex") == false)
        #expect(model.rows.count == 1)
        #expect(model.rows[0].snapshot == nil)
        #expect(!model.isRefreshing)
    }

    @Test
    func testDuplicateLoginWarningUsesOnlyFreshSnapshots() async throws {
        let a = try status("a", identity: "same")
        let b = try status("b", identity: "same")
        let loader = FixtureLoader([a, b])
        let model = model(loader)
        await model.refresh()
        #expect(model.duplicateNames == ["a与b"])
        await loader.update([a, AccountStatus(account: b.account, state: "error", snapshot: nil, error: "失败")])
        await model.refresh()
        #expect(model.duplicateNames.isEmpty)
    }
}
