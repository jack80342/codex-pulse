import CodexPulseCore
import Foundation
import Testing

struct ProtocolTests {
    private func withClient(
        mode: String, timeout: TimeInterval = 2,
        body: (AppServerClient, ProbePaths) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexPulseTests-\(UUID().uuidString)")
        let paths = try ProbePaths(account: "test", root: root)
        try paths.prepare()
        defer { try? FileManager.default.removeItem(at: root) }
        let python = ["/usr/bin/python3", "/opt/homebrew/bin/python3"].first(where: FileManager.default.isExecutableFile(atPath:))
        let executable = try #require(python)
        let fixture = try #require(Bundle.module.url(forResource: "app-server", withExtension: "py", subdirectory: "Fixtures"))
        let client = try AppServerClient(executable: URL(fileURLWithPath: executable), arguments: [fixture.path, mode],
                                         codexHome: paths.accountHome, workspace: paths.workspace, timeout: timeout)
        defer { client.close(); #expect(!(client.isRunning)) }
        try body(client, paths)
    }

    @Test
    func testFragmentedFramesAndInitialize() throws {
        try withClient(mode: "fragmented") { client, _ in
            try client.initialize()
            let result = try client.request("ping")
            #expect(result["echo"] as? String == "ping")
        }
    }

    @Test
    func testTimeoutIsBoundedAndProcessCloses() throws {
        try withClient(mode: "timeout", timeout: 0.1) { client, _ in
            let start = Date()
            expectThrows(try client.initialize()) { error in
                guard case ProbeError.timeout = error else { Issue.record("应返回超时"); return }
            }
            #expect(Date().timeIntervalSince(start) < 1)
        }
    }

    @Test
    func testMalformedJSONAndClosedStream() throws {
        for mode in ["malformed", "eof"] {
            try withClient(mode: mode) { client, _ in expectThrows(try client.initialize()) }
        }
    }

    @Test
    func testServerErrorDoesNotExposePrivateMessage() throws {
        try withClient(mode: "rpc-error") { client, _ in
            expectThrows(try client.initialize()) { error in
                #expect(!(String(describing: error).contains("private-token")))
                #expect(String(describing: error).contains("401"))
            }
        }
    }

    @Test
    func testStderrIsDrainedWithoutBlocking() throws {
        try withClient(mode: "stderr") { client, _ in try client.initialize() }
    }

    @Test
    func testProbeWaitsForCompletedTurnAndKeepsSnapshots() throws {
        try withClient(mode: "normal") { client, paths in
            try client.initialize()
            let file = paths.reports.appendingPathComponent("probe.json")
            let report = try ProbeSession(client: client).runProbe(account: "test", limitID: "codex", model: nil,
                                                                  workspace: paths.workspace, reportURL: file)
            #expect(report.status == "completed")
            #expect(report.observations.first?.resetChange == "unchanged")
            #expect(report.observations.first?.usedPercentChange == 0.5)
            let stored = try String(contentsOf: file, encoding: .utf8)
            #expect(!(stored.contains("probe@example.invalid")))
            #expect(!(stored.contains("accessToken")))
            #expect(try ProbeReport.load(from: file).status == "completed")
            let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
            #expect(permissions == 0o600)
        }
    }

    @Test
    func testFailedTurnAndUnexpectedToolsNeverProduceSuccess() throws {
        for mode in ["failed-turn", "tool-item", "tool-request"] {
            try withClient(mode: mode) { client, paths in
                try client.initialize()
                let file = paths.reports.appendingPathComponent("failure.json")
                expectThrows(try ProbeSession(client: client).runProbe(account: "test", limitID: "codex", model: nil,
                                                                               workspace: paths.workspace, reportURL: file))
                #expect(try ProbeReport.load(from: file).status == "incomplete")
            }
        }
    }

    @Test
    func testQuotaDenialDoesNotStartProbe() throws {
        try withClient(mode: "quota-denied") { client, paths in
            try client.initialize()
            let file = paths.reports.appendingPathComponent("blocked.json")
            expectThrows(try ProbeSession(client: client).runProbe(account: "test", limitID: "codex", model: nil,
                                                                           workspace: paths.workspace, reportURL: file))
            #expect(!(FileManager.default.fileExists(atPath: file.path)))
        }
    }
}
