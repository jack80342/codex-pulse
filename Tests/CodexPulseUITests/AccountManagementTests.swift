import CodexPulseCore
import CodexPulseUI
import Foundation
import Testing

private actor ManagementFixture {
    var accounts: [ManagedAccount] = []
    var authenticated = Set<String>()
    var loginFails = false
    var removalFails = false
    var queries = 0
    var automaticCalls = 0
    var forced = false

    func list() -> [ManagedAccount] { accounts }
    func statuses() -> [AccountStatus] {
        queries += 1
        return accounts.map {
            AccountStatus(account: $0, state: authenticated.contains($0.id) ? "loggedIn" : "notLoggedIn",
                          snapshot: nil, error: nil, username: authenticated.contains($0.id) ? "profile-\($0.name)" : nil)
        }
    }
    func add() -> ManagedAccount {
        let account = ManagedAccount(id: UUID().uuidString, name: "待登录账号 \(accounts.count + 1)")
        accounts.append(account)
        return account
    }
    func login(_ id: String, force: Bool) throws {
        forced = force
        if loginFails { throw ProbeError.loginFailed }
        authenticated.insert(id)
    }
    func remove(_ id: String) throws {
        if removalFails { throw AccountError.busy }
        accounts.removeAll { $0.id == id }
        authenticated.remove(id)
    }
    func failLogin() { loginFails = true }
    func failRemoval() { removalFails = true }
    func automatic() -> [AutomaticRequestResult] {
        automaticCalls += 1
        return accounts.map { AutomaticRequestResult(accountID: $0.id, message: "等待", nextRequestAt: Date().addingTimeInterval(300)) }
    }
}

private actor ManagementLoginGate {
    var token: LoginCancellation?
    private var pending: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func wait(_ cancellation: LoginCancellation) async throws {
        token = cancellation
        await withCheckedContinuation { continuation in
            pending = continuation
            started?.resume()
            started = nil
        }
        if cancellation.isCancelled { throw CancellationError() }
    }
    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish() { pending?.resume(); pending = nil }
}

@MainActor
struct AccountManagementTests {
    private func menu(_ fixture: ManagementFixture) -> MenuBarModel {
        MenuBarModel(readAccounts: { await fixture.list() }, readStatuses: { await fixture.statuses() },
                     runAutomatic: { _ in await fixture.automatic() })
    }
    private func manager(_ fixture: ManagementFixture, menu: MenuBarModel,
                         missingCLI: Bool = false, gate: ManagementLoginGate? = nil) -> AccountManagementModel {
        AccountManagementModel(menu: menu, resolveExecutable: {
            if missingCLI { throw ProbeError.codexNotInstalled }
            return URL(fileURLWithPath: "/fixture/codex")
        }, addAccount: { await fixture.add() },
            loginAccount: { id, force, token in
                if let gate { try await gate.wait(token) }
                try await fixture.login(id, force: force)
            }, removeAccount: { try await fixture.remove($0) })
    }

    @Test
    func firstAddReadsProfileAndSchedulesImmediatelyAndCanRemoveLastAccount() async throws {
        let fixture = ManagementFixture()
        let menu = menu(fixture)
        let manager = manager(fixture, menu: menu)
        await menu.startIfNeeded()
        #expect(menu.rows.isEmpty)
        await manager.add()
        #expect(menu.rows.count == 1)
        #expect(menu.rows[0].displayName == "profile-待登录账号 1")
        #expect(menu.nextAutomaticCheckAt != nil)
        #expect(await fixture.automaticCalls == 1)
        let id = try #require(menu.rows.first?.id)
        await manager.remove(id: id)
        #expect(menu.rows.isEmpty)
        #expect(menu.automaticResults.isEmpty)
        #expect(menu.nextAutomaticCheckAt == nil)
        #expect(!menu.isManagingAccounts && !manager.isBusy)
    }

    @Test
    func missingCLIStopsBeforeAccountCreationAndReportsInstallation() async {
        let fixture = ManagementFixture()
        let menu = menu(fixture)
        let manager = manager(fixture, menu: menu, missingCLI: true)
        #expect(manager.executablePath == nil)
        await manager.add()
        #expect(await fixture.list().isEmpty)
        #expect(manager.error?.contains("安装") == true)
        #expect(!manager.isBusy)
    }

    @Test
    func failedLoginKeepsEntryForRetryOrDeletion() async throws {
        let fixture = ManagementFixture()
        await fixture.failLogin()
        let menu = menu(fixture)
        let manager = manager(fixture, menu: menu)
        await manager.add()
        #expect(manager.error != nil)
        #expect(menu.rows.count == 1)
        #expect(menu.rows[0].account.name == "待登录账号 1")
        #expect(menu.rows[0].statusText == "未登录")
        let id = try #require(menu.rows.first?.id)
        await manager.remove(id: id)
        #expect(menu.rows.isEmpty)
    }

    @Test
    func cancellationBlocksOverlappingRefreshAndReleasesManagementState() async {
        let fixture = ManagementFixture()
        let gate = ManagementLoginGate()
        let menu = menu(fixture)
        let manager = manager(fixture, menu: menu, gate: gate)
        let running = Task { await manager.add() }
        await gate.waitUntilStarted()
        #expect(manager.isLoggingIn && menu.isManagingAccounts)
        #expect(menu.rows.count == 1)
        await manager.add()
        await menu.refresh()
        #expect(await fixture.list().count == 1)
        #expect(await fixture.queries == 0)
        manager.cancelLogin()
        #expect(await gate.token?.isCancelled == true)
        await gate.finish()
        await running.value
        #expect(manager.error == nil)
        #expect(manager.message?.contains("已取消") == true)
        #expect(!manager.isBusy && !menu.isManagingAccounts)
        #expect(menu.rows[0].statusText == "未登录")
    }

    @Test
    func forceReauthenticationUsesExplicitServiceOption() async throws {
        let fixture = ManagementFixture()
        let menu = menu(fixture)
        let manager = manager(fixture, menu: menu)
        await manager.add()
        let id = try #require(menu.rows.first?.id)
        await manager.login(id: id, force: true)
        #expect(await fixture.forced)
        #expect(menu.rows[0].displayName == "profile-待登录账号 1")
    }

    @Test
    func failedRemovalPreservesRowAndReportsError() async throws {
        let fixture = ManagementFixture()
        let menu = menu(fixture)
        let manager = manager(fixture, menu: menu)
        await manager.add()
        await fixture.failRemoval()
        let id = try #require(menu.rows.first?.id)
        await manager.remove(id: id)
        #expect(menu.rows.count == 1)
        #expect(manager.error?.contains("使用") == true)
        #expect(menu.nextAutomaticCheckAt != nil)
    }

    @Test
    func fourthAndFurtherAccountsAreVisibleWithoutLimit() async {
        let fixture = ManagementFixture()
        let menu = menu(fixture)
        let manager = manager(fixture, menu: menu)
        for _ in 1...6 { await manager.add() }
        #expect(menu.rows.count == 6)
        #expect(menu.rows.map(\.displayName) == (1...6).map { "profile-待登录账号 \($0)" })
        #expect(manager.error == nil)
    }
}
