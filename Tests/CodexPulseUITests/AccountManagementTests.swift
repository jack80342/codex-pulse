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
    var savedOrder: [String]?
    var reorderFails = false
    var scheduledOrder: [String] = []

    func list() -> [ManagedAccount] {
        let map = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        return savedOrder?.compactMap { map[$0] } ?? accounts
    }
    func saveOrder(_ ids: [String]) throws {
        if reorderFails { throw AccountError.storageFailure }
        savedOrder = ids
    }
    func failReordering() { reorderFails = true }
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
        scheduledOrder = accounts.map(\.id)
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
    @Test
    func dropPositionsSupportMovingUpDownAndToEnds() {
        let ids = ["a", "b", "c"]
        #expect(AccountManagementModel.reorderedIDs(ids, moving: "c", relativeTo: "a", after: false) == ["c", "a", "b"])
        #expect(AccountManagementModel.reorderedIDs(ids, moving: "a", relativeTo: "c", after: true) == ["b", "c", "a"])
        #expect(AccountManagementModel.reorderedIDs(ids, moving: "c", relativeTo: "a", after: true) == ["a", "c", "b"])
        #expect(AccountManagementModel.reorderedIDs(ids, moving: "a", relativeTo: "a", after: true) == ids)
        #expect(AccountManagementModel.reorderedIDs(ids, moving: "external", relativeTo: "b", after: true) == ids)
    }

    @Test
    func reorderUpdatesBothViewsWithoutQueryingOrRequestingAndRefreshKeepsScheduleOrder() async {
        let fixture = ManagementFixture()
        let menu = menu(fixture)
        let manager = manager(fixture, menu: menu)
        for _ in 1...3 { await manager.add() }
        let original = menu.rows.map(\.id)
        let queries = await fixture.queries
        let automatic = await fixture.automaticCalls
        await manager.reorder(Array(original.reversed()))
        #expect(menu.rows.map(\.id) == Array(original.reversed()))
        #expect(await fixture.queries == queries)
        #expect(await fixture.automaticCalls == automatic)
        #expect(!manager.isBusy && !menu.isManagingAccounts)
        #expect(menu.nextAutomaticCheckAt != nil)
        await menu.refresh()
        #expect(menu.rows.map(\.id) == Array(original.reversed()))
        #expect(await fixture.scheduledOrder == original)
        let restarted = self.menu(fixture)
        await restarted.startIfNeeded()
        #expect(restarted.rows.map(\.id) == Array(original.reversed()))
    }

    @Test
    func failedReorderKeepsOriginalRowsAndReportsError() async {
        let fixture = ManagementFixture()
        let menu = menu(fixture)
        let manager = manager(fixture, menu: menu)
        for _ in 1...2 { await manager.add() }
        let original = menu.rows.map(\.id)
        await fixture.failReordering()
        await manager.reorder(Array(original.reversed()))
        #expect(menu.rows.map(\.id) == original)
        #expect(manager.error == AccountError.storageFailure.description)
        #expect(!manager.isBusy && !menu.isManagingAccounts)
    }

    @Test
    func reorderingIsBlockedDuringLogin() async {
        let fixture = ManagementFixture()
        let menu = menu(fixture)
        let manager = manager(fixture, menu: menu)
        for _ in 1...2 { await manager.add() }
        let gate = ManagementLoginGate()
        let blocked = self.manager(fixture, menu: menu, gate: gate)
        let original = menu.rows.map(\.id)
        let running = Task { await blocked.login(id: original[0]) }
        await gate.waitUntilStarted()
        await blocked.reorder(Array(original.reversed()))
        #expect(await fixture.savedOrder == nil)
        await gate.finish()
        await running.value
        #expect(menu.rows.map(\.id) == original)
    }

    @Test
    func generatedPendingLabelsAreLocalizedWithoutChangingTheStoredName() async {
        let id = "a1234567-b123-4123-8123-a12345678901"
        let account = ManagedAccount(id: id, name: id, usesGeneratedName: true)
        let menu = MenuBarModel(readAccounts: { [account] }, readStatuses: {
            [AccountStatus(account: account, state: "notLoggedIn", snapshot: nil, error: nil)]
        })
        await menu.refresh()
        #expect(menu.rows.first?.displayName == PulseLocalization.text("account.pendingName", "a1234567"))
        #expect(menu.rows.first?.account.name == id)
    }

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
            }, removeAccount: { try await fixture.remove($0) },
            saveDisplayOrder: { try await fixture.saveOrder($0) })
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
        #expect(manager.error == PulseLocalization.text("account.cliMissing"))
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
        #expect(menu.rows[0].statusText == PulseLocalization.text("status.notLoggedIn"))
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
        #expect(manager.message == PulseLocalization.text("account.loginCancelled"))
        #expect(!manager.isBusy && !menu.isManagingAccounts)
        #expect(menu.rows[0].statusText == PulseLocalization.text("status.notLoggedIn"))
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
        #expect(manager.error == AccountError.busy.description)
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
