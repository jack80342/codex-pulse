import CodexPulseCore
import Foundation
import Testing

struct AccountTests {
    private func withStore(_ body: (AccountStore) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexPulseAccounts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try body(AccountStore(root: root))
    }

    @Test
    func testRegistrySurvivesRestartAndRenameKeepsCredentials() throws {
        try withStore { store in
            let account = try store.add(name: "主账号", id: "probe-1")
            try store.withAccount(id: account.id) { _, paths in
                try Data("fixture-credential".utf8).write(to: paths.accountHome.appendingPathComponent("auth.json"))
            }
            try store.rename(id: account.id, name: "工作账号")
            let reloaded = AccountStore(root: store.root)
            #expect(try reloaded.list().first?.name == "工作账号")
            #expect(try reloaded.list().first?.id == "probe-1")
            let paths = try ProbePaths(account: account.id, root: store.root)
            #expect(try String(contentsOf: paths.accountHome.appendingPathComponent("auth.json"), encoding: .utf8) == "fixture-credential")
            let registry = store.root.appendingPathComponent("account-list.json")
            #expect(try FileManager.default.attributesOfItem(atPath: registry.path)[.posixPermissions] as? Int == 0o600)
            #expect(try FileManager.default.attributesOfItem(atPath: paths.accountHome.path)[.posixPermissions] as? Int == 0o700)
            #expect(!(try String(contentsOf: registry, encoding: .utf8).contains("fixture-credential")))
        }
    }

    @Test
    func testCapacityDuplicatesAndInvalidIDsDoNotChangeRegistry() throws {
        try withStore { store in
            for id in ["a", "b", "c"] { try store.add(name: id, id: id) }
            expectThrows(try store.add(name: "duplicate", id: "a"))
            expectThrows(try store.add(name: "fourth", id: "d"))
            expectThrows(try store.add(name: "traversal", id: "../.codex"))
            expectThrows(try store.rename(id: "a", name: "bad\nname"))
            expectThrows(try store.remove(id: "missing"))
            #expect(try store.list().map(\.id) == ["a", "b", "c"])
        }
    }

    @Test
    func testRemoveDeletesOnlySelectedCredentialsAndPreservesReports() throws {
        try withStore { store in
            for id in ["a", "b"] {
                try store.add(name: id, id: id)
                try store.withAccount(id: id) { _, paths in
                    try Data(id.utf8).write(to: paths.accountHome.appendingPathComponent("auth.json"))
                    try Data("report".utf8).write(to: paths.reports.appendingPathComponent("history.json"))
                }
            }
            try store.remove(id: "a")
            #expect(try store.list().map(\.id) == ["b"])
            #expect(!FileManager.default.fileExists(atPath: store.root.appendingPathComponent("accounts/a").path))
            #expect(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("accounts/b/auth.json").path))
            #expect(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("verification/a/reports/history.json").path))
        }
    }

    @Test
    func testDeletionCannotRaceActiveSessionAndOtherAccountStillWorks() throws {
        try withStore { store in
            try store.add(name: "A", id: "a")
            try store.add(name: "B", id: "b")
            try store.withAccount(id: "a") { _, _ in
                expectThrows(try store.remove(id: "a"))
                expectThrows(try store.withAccount(id: "a") { _, _ in })
                try store.withAccount(id: "b") { _, _ in }
            }
            try store.remove(id: "a")
        }
    }

    @Test
    func testUnsafeDeletionStaysPendingAndCanBeResumed() throws {
        try withStore { store in
            try store.add(name: "A", id: "a")
            let outside = store.root.appendingPathComponent("outside")
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            let sentinel = outside.appendingPathComponent("keep")
            try Data("keep".utf8).write(to: sentinel)
            let accounts = store.root.appendingPathComponent("accounts")
            try FileManager.default.createDirectory(at: accounts, withIntermediateDirectories: true)
            let home = accounts.appendingPathComponent("a")
            try FileManager.default.createSymbolicLink(at: home, withDestinationURL: outside)
            expectThrows(try store.remove(id: "a"))
            #expect(try AccountStore(root: store.root).list().first?.pendingDeletion == true)
            #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
            expectThrows(try store.withAccount(id: "a") { _, _ in })
            try FileManager.default.removeItem(at: home)
            try store.remove(id: "a")
            #expect(try store.list().isEmpty)
            #expect(FileManager.default.fileExists(atPath: sentinel.path))
        }
    }

    @Test
    func testCorruptAndLinkedRegistryAreNeverOverwritten() throws {
        try withStore { store in
            try store.add(name: "A", id: "a")
            let registry = store.root.appendingPathComponent("account-list.json")
            let corrupt = Data("broken-private-content".utf8)
            try corrupt.write(to: registry)
            expectThrows(try store.add(name: "B", id: "b"))
            #expect(try Data(contentsOf: registry) == corrupt)
            try FileManager.default.removeItem(at: registry)
            let outside = store.root.appendingPathComponent("outside.json")
            try corrupt.write(to: outside)
            try FileManager.default.createSymbolicLink(at: registry, withDestinationURL: outside)
            expectThrows(try store.list())
            #expect(try Data(contentsOf: outside) == corrupt)
        }
    }

    @Test
    func testSymlinkDirectoriesAndOfficialHomeAreRejected() throws {
        try withStore { store in
            try store.add(name: "A", id: "a")
            let outside = store.root.appendingPathComponent("outside")
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: store.root.appendingPathComponent("accounts"), withDestinationURL: outside)
            expectThrows(try store.withAccount(id: "a") { _, _ in })
            #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        }
        let official = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        expectThrows(try AccountStore(root: official).list())
    }
}
