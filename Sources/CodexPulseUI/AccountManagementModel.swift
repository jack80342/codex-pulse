import CodexPulseCore
import Combine
import Foundation

@MainActor
public final class AccountManagementModel: ObservableObject {
    @Published public private(set) var isBusy = false
    @Published public private(set) var isLoggingIn = false
    @Published public private(set) var message: String?
    @Published public private(set) var error: String?
    @Published public private(set) var executablePath: String?
    private let menu: MenuBarModel
    private let resolveExecutable: @Sendable () throws -> URL
    private let addAccount: @Sendable () async throws -> ManagedAccount
    private let loginAccount: @Sendable (String, Bool, LoginCancellation) async throws -> Void
    private let removeAccount: @Sendable (String) async throws -> Void
    private var cancellation: LoginCancellation?

    public init(menu: MenuBarModel,
                resolveExecutable: @escaping @Sendable () throws -> URL,
                addAccount: @escaping @Sendable () async throws -> ManagedAccount,
                loginAccount: @escaping @Sendable (String, Bool, LoginCancellation) async throws -> Void,
                removeAccount: @escaping @Sendable (String) async throws -> Void) {
        self.menu = menu
        self.resolveExecutable = resolveExecutable
        self.addAccount = addAccount
        self.loginAccount = loginAccount
        self.removeAccount = removeAccount
        checkExecutable()
    }

    public static func live(menu: MenuBarModel, store: AccountStore = AccountStore()) -> AccountManagementModel {
        AccountManagementModel(menu: menu, resolveExecutable: { try CodexExecutable.resolve() },
            addAccount: {
                try await Task.detached {
                    let id = UUID().uuidString.lowercased()
                    return try store.add(name: id, id: id, usesGeneratedName: true)
                }.value
            }, loginAccount: { id, force, cancellation in
                try await Task.detached(priority: .userInitiated) {
                    let executable = try CodexExecutable.resolve()
                    try AccountService(store: store, executable: executable).login(
                        id: id, forceReauthentication: force, cancellation: cancellation, openURL: LoginBrowser.open)
                }.value
            }, removeAccount: { id in
                try await Task.detached { try store.remove(id: id) }.value
            })
    }

    public func checkExecutable() {
        do { executablePath = try resolveExecutable().path }
        catch { executablePath = nil }
    }

    public func add() async {
        guard begin() else { return }
        do {
            executablePath = try resolveExecutable().path
            let account = try await addAccount()
            menu.showRegisteredAccount(account)
            try await authenticate(id: account.id, force: false)
        } catch { handle(error) }
        await finish()
    }

    public func login(id: String, force: Bool = false) async {
        guard begin() else { return }
        do {
            executablePath = try resolveExecutable().path
            if force { menu.clearAccountCache(id: id) }
            try await authenticate(id: id, force: force)
        } catch { handle(error) }
        await finish()
    }

    public func remove(id: String) async {
        guard begin() else { return }
        do {
            try await removeAccount(id)
            menu.removeRegisteredAccount(id: id)
            message = PulseLocalization.text("account.removed")
        } catch { handle(error) }
        await finish()
    }

    public func cancelLogin() {
        guard isLoggingIn else { return }
        cancellation?.cancel()
        message = PulseLocalization.text("account.cancelling")
    }

    private func authenticate(id: String, force: Bool) async throws {
        let token = LoginCancellation()
        cancellation = token
        isLoggingIn = true
        message = PulseLocalization.text("account.awaitingLogin")
        try await loginAccount(id, force, token)
        if token.isCancelled { throw CancellationError() }
        message = PulseLocalization.text("account.loginCompleted")
    }

    private func begin() -> Bool {
        guard !isBusy, menu.beginAccountManagement() else { return false }
        isBusy = true
        error = nil
        message = nil
        return true
    }

    private func finish() async {
        isLoggingIn = false
        cancellation = nil
        await menu.endAccountManagement()
        isBusy = false
    }

    private func handle(_ error: Error) {
        if cancellation?.isCancelled == true || error is CancellationError {
            message = PulseLocalization.text("account.loginCancelled")
        } else {
            message = nil
            self.error = Self.message(error)
        }
    }

    private static func message(_ error: Error) -> String {
        if let error = error as? AccountError { return error.description }
        if let error = error as? ProbeError {
            if case .codexNotInstalled = error { return PulseLocalization.text("account.cliMissing") }
            return error.description
        }
        return PulseLocalization.text("account.operationFailed")
    }
}
