import CodexPulseCore
@testable import CodexPulseUI
import Foundation
import Testing

@MainActor
struct AppUpdateModelTests {
    private func release(_ version: String) -> AppRelease {
        AppRelease(version: AppVersion(version)!, pageURL: URL(string: "https://github.com/jack80342/codex-pulse/releases/tag/v\(version)")!, downloadURL: nil)
    }

    @Test func manualOnlyAndNewVersionIsDisplayed() async {
        let latest = release("0.8.0")
        let model = AppUpdateModel(currentVersion: "0.7.1", fetch: { latest })
        #expect(!model.isChecking && model.message == nil && model.availableRelease == nil)
        await model.check()
        #expect(model.availableRelease?.version.text == "0.8.0")
        #expect(model.message?.contains("0.8.0") == true)
        #expect(model.error == nil && !model.isChecking)
    }

    @Test func equalAndOlderVersionsNeverOfferDowngrades() async {
        for version in ["0.7.1", "0.7.0"] {
            let latest = release(version)
            let model = AppUpdateModel(currentVersion: "0.7.1", fetch: { latest })
            await model.check()
            #expect(model.availableRelease == nil)
            #expect(model.message?.contains("0.7.1") == true)
            #expect(model.error == nil)
        }
    }

    @Test func failureClearsSuccessAndCanBeRetried() async {
        let queue = ReleaseQueue(release: release("0.8.0"))
        let model = AppUpdateModel(currentVersion: "0.7.1", fetch: { try await queue.next() })
        await model.check()
        #expect(model.availableRelease != nil)
        await model.check()
        #expect(model.availableRelease == nil && model.message == nil && model.error != nil)
        await model.check()
        #expect(model.availableRelease != nil && model.error == nil)
    }

    @Test func invalidInstalledVersionDoesNotQueryOrPretendSuccess() async {
        let model = AppUpdateModel(currentVersion: nil, fetch: { Issue.record("Must not query"); throw AppUpdateError.transport })
        await model.check()
        #expect(model.error != nil && model.message == nil && !model.isChecking)
    }

    @Test func concurrentClicksSendOnlyOneRequest() async {
        let gate = ReleaseGate()
        let latest = release("0.8.0")
        let model = AppUpdateModel(currentVersion: "0.7.1", fetch: { await gate.wait(); return latest })
        let first = Task { await model.check() }
        while !model.isChecking { await Task.yield() }
        await model.check()
        while await gate.calls == 0 { await Task.yield() }
        await gate.resume()
        await first.value
        #expect(await gate.calls == 1)
        #expect(!model.isChecking && model.availableRelease != nil)
    }
}

private actor ReleaseQueue {
    let release: AppRelease
    var calls = 0
    init(release: AppRelease) { self.release = release }
    func next() throws -> AppRelease {
        calls += 1
        if calls == 2 { throw AppUpdateError.rateLimited }
        return release
    }
}

private actor ReleaseGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    func wait() async {
        calls += 1
        await withCheckedContinuation { continuation = $0 }
    }
    func resume() { continuation?.resume(); continuation = nil }
}
