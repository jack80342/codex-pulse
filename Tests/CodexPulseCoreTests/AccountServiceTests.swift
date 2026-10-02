import CodexPulseCore
import Foundation
import Testing

@Suite(.serialized)
struct AccountServiceTests {
    private func service(root: URL, modes: [String: String],
                         readUsername: (@Sendable (ProbePaths) throws -> String)? = nil) throws -> AccountService {
        let python = try #require(["/usr/bin/python3", "/opt/homebrew/bin/python3"].first(where: FileManager.default.isExecutableFile(atPath:)))
        let fixture = try #require(Bundle.module.url(forResource: "app-server", withExtension: "py", subdirectory: "Fixtures"))
        return AccountService(store: AccountStore(root: root), readUsername: readUsername) { paths in
            let mode = modes[paths.accountHome.lastPathComponent] ?? "normal"
            return try AppServerClient(executable: URL(fileURLWithPath: python),
                                arguments: [fixture.path, mode],
                                codexHome: paths.accountHome, workspace: paths.workspace, timeout: mode == "timeout" ? 0.1 : 2)
        }
    }

    @Test
    func testProfileQueriesUseIndependentHomesAndFailureDoesNotLoseQuota() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexPulseProfile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try service(root: root, modes: [:], readUsername: { paths in
            let id = paths.accountHome.lastPathComponent
            if id == "b" { throw ProfileError.http(401) }
            return "profile-\(id)"
        })
        for id in ["a", "b", "c"] { try service.store.add(name: id, id: id) }
        let results = try await service.statuses()
        #expect(results.map(\.username) == ["profile-a", nil, "profile-c"])
        #expect(results.map(\.state) == ["loggedIn", "loggedIn", "loggedIn"])
        #expect(results.allSatisfy { $0.snapshot != nil && $0.error == nil })
        #expect(results[1].usernameError?.contains("401") == true)
    }

    @Test
    func testThreeAccountResultsKeepOrderAndIsolateFailuresWithoutModelRequests() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexPulseService-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try service(root: root, modes: ["b": "account-unlogged", "c": "account-quota-error"])
        for id in ["a", "b", "c"] { try service.store.add(name: id, id: id) }
        let results = try await service.statuses()
        #expect(results.map { $0.account.id } == ["a", "b", "c"])
        #expect(results.map(\.state) == ["loggedIn", "notLoggedIn", "quotaError"])
        #expect(results[0].snapshot?.buckets["codex"]?.window(minutes: 300)?.usedPercent == 10)
        #expect(results[1].snapshot == nil)
        #expect(results[2].error?.contains("401") == true)
        #expect(results[2].error?.contains("private-token") == false)
        for id in ["a", "b", "c"] {
            let methods = try String(contentsOf: root.appendingPathComponent("accounts/\(id)/fixture-methods"), encoding: .utf8)
            #expect(!methods.contains("turn/start"))
            #expect(!methods.contains("account/login/start"))
        }
    }

    @Test
    func testTimeoutDoesNotLoseHealthyAccounts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexPulseService-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try service(root: root, modes: ["b": "timeout"])
        for id in ["a", "b", "c"] { try service.store.add(name: id, id: id) }
        let results = try await service.statuses()
        #expect(results.map(\.state) == ["loggedIn", "error", "loggedIn"])
        #expect(results[0].snapshot?.identityDigest != results[2].snapshot?.identityDigest)
        try service.store.remove(id: "b") // 超时后子进程及账号租约已释放。
    }

    @Test
    func testLoginSurvivesNewServerAndDoesNotOpenBrowserAgain() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexPulseLogin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try service(root: root, modes: ["a": "login-wrong-event"])
        try service.store.add(name: "A", id: "a")
        var opened = 0
        try service.login(id: "a") { url in
            #expect(url.host == "auth.openai.com")
            opened += 1
        }
        #expect(opened == 1)
        #expect(try service.status(id: "a").state == "loggedIn")
        try service.login(id: "a") { _ in opened += 1 }
        #expect(opened == 1)
    }

    @Test
    func testForcedLoginOpensBrowserAgainWithoutChangingOtherAccount() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexPulseReauth-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try service(root: root, modes: ["a": "login-success"])
        for id in ["a", "b"] { try service.store.add(name: id, id: id) }
        var opened = 0
        try service.login(id: "a") { _ in opened += 1 }
        try service.login(id: "a", forceReauthentication: true) { _ in opened += 1 }
        #expect(opened == 2)
        #expect(try service.status(id: "a").state == "loggedIn")
        #expect(try service.status(id: "b").state == "loggedIn")
        let methods = try String(contentsOf: root.appendingPathComponent("accounts/a/fixture-methods"), encoding: .utf8)
        #expect(methods.contains("account/logout"))
        #expect(!methods.contains("turn/start"))
    }

    @Test
    func testLoginCancellationReleasesActiveServerAndLease() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexPulseCancel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try service(root: root, modes: ["a": "login-timeout"])
        try service.store.add(name: "A", id: "a")
        let cancellation = LoginCancellation()
        let start = Date()
        expectThrows(try service.login(id: "a", cancellation: cancellation) { _ in cancellation.cancel() })
        #expect(cancellation.isCancelled)
        #expect(Date().timeIntervalSince(start) < 5)
        try service.store.remove(id: "a")
        #expect(try service.store.list().isEmpty)
    }

    @Test
    func testMoreThanThreeStatusesPreserveOrderAndIsolateErrors() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexPulseMany-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try service(root: root, modes: ["b": "account-quota-error", "f": "account-unlogged"])
        let ids = ["a", "b", "c", "d", "e", "f", "g"]
        for id in ids { try service.store.add(name: id, id: id) }
        let results = try await service.statuses()
        #expect(results.map { $0.account.id } == ids)
        #expect(results.map(\.state) == ["loggedIn", "quotaError", "loggedIn", "loggedIn", "loggedIn", "notLoggedIn", "loggedIn"])
    }

    @Test
    func testFailedAndUnsafeLoginCancelAndReleaseLease() throws {
        for mode in ["login-failed", "login-invalid-url"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexPulseLogin-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let service = try service(root: root, modes: ["a": mode])
            try service.store.add(name: "A", id: "a")
            var opened = false
            expectThrows(try service.login(id: "a") { _ in opened = true })
            #expect(opened == (mode == "login-failed"))
            let methods = try String(contentsOf: root.appendingPathComponent("accounts/a/fixture-methods"), encoding: .utf8)
            #expect(methods.contains("account/login/cancel"))
            try service.store.remove(id: "a")
        }
    }
}
