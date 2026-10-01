import CodexPulseCore
import Foundation
import Testing

@Suite(.serialized)
struct AutomaticRequestTests {
    private let date = Date(timeIntervalSince1970: 1_900_000_000)

    private func service(_ store: AccountStore, at date: Date, mode: String = "normal") throws -> AutomaticRequestService {
        let python = try #require(["/usr/bin/python3", "/opt/homebrew/bin/python3"].first(where: FileManager.default.isExecutableFile(atPath:)))
        let fixture = try #require(Bundle.module.url(forResource: "app-server", withExtension: "py", subdirectory: "Fixtures"))
        return AutomaticRequestService(store: store, now: { date }, turnTimeout: 0.1) { paths in
            try AppServerClient(executable: URL(fileURLWithPath: python), arguments: [fixture.path, mode],
                                codexHome: paths.accountHome, workspace: paths.workspace, timeout: 2)
        }
    }

    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CodexPulseAuto-\(UUID().uuidString)")
    }

    private func quota(_ store: AccountStore, id: String = "a", _ values: [String: Any]) throws {
        try store.withAccount(id: id) { _, paths in
            try JSONSerialization.data(withJSONObject: values).write(to: paths.accountHome.appendingPathComponent("fixture-quota.json"))
        }
    }

    private func identity(_ id: String = "a") throws -> String {
        try #require(QuotaSnapshot.decode(Data("{\"accountId\":\"fixture-\(id)\",\"rateLimitsByLimitId\":{}}".utf8)).identityDigest)
    }

    private func attempts(_ root: URL, id: String = "a") throws -> Int {
        let file = root.appendingPathComponent("accounts/\(id)/fixture-methods")
        guard FileManager.default.fileExists(atPath: file.path) else { return 0 }
        return try String(contentsOf: file, encoding: .utf8).split(separator: "\n").filter { $0 == "turn/start" }.count
    }

    @Test
    func startupRefreshAndRestartOnlyRequestOncePerWindow() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(root: root)
        try store.add(name: "A", id: "a")
        try quota(store, ["reset": 1_900_000_120])
        let first = try service(store, at: date).process(id: "a", expectedIdentity: identity())
        #expect(first.message == "最小请求已完成")
        #expect(first.nextRequestAt == date.addingTimeInterval(120))
        #expect(first.snapshot?.buckets["codex"]?.window(minutes: 300)?.usedPercent == 10.5)
        let restarted = try service(store, at: date.addingTimeInterval(10)).process(id: "a", expectedIdentity: identity())
        #expect(restarted.message == "自动请求已就绪")
        #expect(try attempts(root) == 1)
        let checkpoint = root.appendingPathComponent("scheduling/a.json")
        let permissions = try FileManager.default.attributesOfItem(atPath: checkpoint.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        let contents = try String(contentsOf: checkpoint, encoding: .utf8)
        #expect(!contents.contains("probe@example"))
        #expect(!contents.contains("token"))
        let report = try ProbeReport.load(from: root.appendingPathComponent("verification/a/reports/automatic-latest.json"))
        #expect(report.status == "completed")
    }

    @Test
    func overdueWakeSendsOneRequestAndUsesActualNewServerReset() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(root: root)
        try store.add(name: "A", id: "a")
        try quota(store, ["reset": 1_900_000_010])
        _ = try service(store, at: date).process(id: "a", expectedIdentity: identity())
        // 模拟休眠越过多轮窗口；只允许一次新请求，不补发错过的轮次。
        let waking = date.addingTimeInterval(100_000)
        try quota(store, ["reset": 1_900_000_010, "afterReset": 1_900_118_000])
        let result = try service(store, at: waking).process(id: "a", expectedIdentity: identity())
        #expect(result.message == "最小请求已完成")
        #expect(result.nextRequestAt == Date(timeIntervalSince1970: 1_900_118_000))
        _ = try service(store, at: waking).process(id: "a", expectedIdentity: identity())
        #expect(try attempts(root) == 2)
    }

    @Test
    func unknownExhaustedDeniedAndMissingResetNeverRequest() throws {
        for values: [String: Any] in [
            ["five": NSNull(), "weekly": NSNull()], ["weekly": 100],
            ["five": 100], ["reset": NSNull()]
        ] {
            let root = root()
            defer { try? FileManager.default.removeItem(at: root) }
            let store = AccountStore(root: root)
            try store.add(name: "A", id: "a")
            try quota(store, values.merging(["reset": 1_900_000_120]) { old, _ in old })
            let result = try service(store, at: date).process(id: "a", expectedIdentity: identity())
            #expect(try attempts(root) == 0)
            #expect(result.nextRequestAt == (values["five"] as? Int == 100 ? date.addingTimeInterval(120) : nil))
        }
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(root: root)
        try store.add(name: "A", id: "a")
        try quota(store, ["reset": 1_900_000_120])
        let denied = try service(store, at: date, mode: "quota-denied").process(id: "a", expectedIdentity: identity())
        #expect(denied.nextRequestAt == nil)
        #expect(try attempts(root) == 0)
    }

    @Test
    func unknownResetAfterSuccessDoesNotRepeatAndCanAdoptLaterServerReset() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(root: root)
        try store.add(name: "A", id: "a")
        try quota(store, ["reset": 1_900_000_120, "afterReset": NSNull()])
        let first = try service(store, at: date).process(id: "a", expectedIdentity: identity())
        #expect(first.message.contains("请求完成"))
        #expect(first.nextRequestAt == nil)
        try quota(store, ["reset": 1_900_000_220])
        let recovered = try service(store, at: date).process(id: "a", expectedIdentity: identity())
        #expect(recovered.message == "请求已完成，等待服务端重置")
        #expect(recovered.nextRequestAt == date.addingTimeInterval(220))
        #expect(try attempts(root) == 1)
    }

    @Test
    func identityChangedImmediatelyBeforeTurnNeverRequests() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(root: root)
        try store.add(name: "A", id: "a")
        try quota(store, ["reset": 1_900_000_120, "afterReadIdentity": "changed"])
        let result = try service(store, at: date).process(id: "a", expectedIdentity: identity())
        #expect(!result.message.contains("已完成"))
        #expect(try attempts(root) == 0)
    }

    @Test
    func weeklyExhaustedByRequestStopsScheduling() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(root: root)
        try store.add(name: "A", id: "a")
        try quota(store, ["reset": 1_900_000_120, "weekly": 99, "afterWeekly": 100])
        let result = try service(store, at: date).process(id: "a", expectedIdentity: identity())
        #expect(result.message.contains("周额度已耗尽"))
        #expect(result.nextRequestAt == nil)
        _ = try service(store, at: date.addingTimeInterval(130)).process(id: "a", expectedIdentity: identity())
        #expect(try attempts(root) == 1)
    }

    @Test
    func uncertainTurnIsNotRetriedBeforeReset() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(root: root)
        try store.add(name: "A", id: "a")
        try quota(store, ["reset": 1_900_000_120])
        let failed = try service(store, at: date, mode: "turn-timeout").process(id: "a", expectedIdentity: identity())
        #expect(failed.nextRequestAt == date.addingTimeInterval(120))
        #expect(!failed.message.contains("已完成"))
        _ = try service(store, at: date).process(id: "a", expectedIdentity: identity())
        #expect(try attempts(root) == 1)
        let methods = try String(contentsOf: root.appendingPathComponent("accounts/a/fixture-methods"), encoding: .utf8)
        #expect(methods.contains("turn/interrupt"))
        let report = try ProbeReport.load(from: root.appendingPathComponent("verification/a/reports/automatic-latest.json"))
        #expect(report.status == "incomplete")
    }

    @Test
    func crashCheckpointAdoptsServerWindowWithoutResending() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(root: root)
        try store.add(name: "A", id: "a")
        try quota(store, ["reset": 1_900_000_120])
        let account = try #require(store.list().first)
        let scheduling = root.appendingPathComponent("scheduling")
        try FileManager.default.createDirectory(at: scheduling, withIntermediateDirectories: false)
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "createdAt": account.createdAt.timeIntervalSinceReferenceDate,
            "identityDigest": identity(), "attemptedAt": date.timeIntervalSinceReferenceDate, "outcome": "pending"
        ])
        try data.write(to: scheduling.appendingPathComponent("a.json"))
        let result = try service(store, at: date).process(id: "a", expectedIdentity: identity())
        #expect(result.nextRequestAt == date.addingTimeInterval(120))
        #expect(result.message.contains("待确认"))
        #expect(try attempts(root) == 0)
    }

    @Test
    func corruptCheckpointFailsClosedAndIsPreserved() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(root: root)
        try store.add(name: "A", id: "a")
        try quota(store, ["reset": 1_900_000_120])
        let scheduling = root.appendingPathComponent("scheduling")
        try FileManager.default.createDirectory(at: scheduling, withIntermediateDirectories: false)
        let file = scheduling.appendingPathComponent("a.json")
        try Data("invalid-checkpoint".utf8).write(to: file)
        let result = try service(store, at: date).process(id: "a", expectedIdentity: identity())
        #expect(result.nextRequestAt == nil)
        #expect(try attempts(root) == 0)
        #expect(try String(contentsOf: file, encoding: .utf8) == "invalid-checkpoint")
    }

    @Test
    func changedIdentityAndBusyLeaseBlockRequests() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(root: root)
        try store.add(name: "A", id: "a")
        try quota(store, ["reset": 1_900_000_120, "identity": "changed"])
        let changed = try service(store, at: date).process(id: "a", expectedIdentity: identity())
        #expect(changed.message.contains("身份已变化"))
        #expect(try attempts(root) == 0)
        let paths = try ProbePaths(account: "a", root: root)
        let lease = try paths.acquireLease()
        let blocked = try service(store, at: date).process(id: "a", expectedIdentity: identity())
        #expect(blocked.message.contains("另一操作"))
        #expect(try attempts(root) == 0)
        withExtendedLifetime(lease) {}
    }

    @Test
    func recreatedAccountDoesNotReuseOldCheckpoint() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(root: root)
        try store.add(name: "A", id: "a")
        try quota(store, ["reset": 1_900_000_120])
        _ = try service(store, at: date).process(id: "a", expectedIdentity: identity())
        try store.remove(id: "a")
        try store.add(name: "New", id: "a")
        try quota(store, ["reset": 1_900_000_120])
        let result = try service(store, at: date).process(id: "a", expectedIdentity: identity())
        #expect(result.message == "最小请求已完成")
        #expect(try attempts(root) == 1) // 旧账号目录随删除清理，新条目拥有新的尝试。
    }

    @Test
    func threeAccountsIsolateUnknownWindowAndDuplicateIdentity() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(root: root)
        for id in ["a", "b", "c"] { try store.add(name: id, id: id) }
        try quota(store, id: "a", ["reset": 1_900_000_120])
        try quota(store, id: "b", ["five": NSNull(), "weekly": NSNull()])
        try quota(store, id: "c", ["reset": 1_900_000_220])
        let accounts = try store.list()
        let statuses = try accounts.map { account in
            AccountStatus(account: account, state: "loggedIn", snapshot: try QuotaSnapshot.decode(Data("{\"accountId\":\"fixture-\(account.id)\",\"rateLimitsByLimitId\":{}}".utf8)), error: nil)
        }
        let service = try service(store, at: date)
        let results = await service.run(statuses: statuses)
        #expect(results.map(\.accountID) == ["a", "b", "c"])
        #expect(try attempts(root, id: "a") == 1)
        #expect(try attempts(root, id: "b") == 0)
        #expect(try attempts(root, id: "c") == 1)
        #expect(results[1].nextRequestAt == nil)
        let duplicate = AccountStatus(account: accounts[1], state: "loggedIn", snapshot: statuses[0].snapshot, error: nil)
        let second = await service.run(statuses: [statuses[0], duplicate])
        #expect(second[1].message.contains("重复登录"))
        #expect(try attempts(root, id: "b") == 0)
    }
}
