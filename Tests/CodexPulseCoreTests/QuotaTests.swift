import CodexPulseCore
import Foundation
import Testing

struct QuotaTests {
    private let bucket = """
    {"limitId":"codex","primary":{"usedPercent":12.5,"windowDurationMins":300,"resetsAt":1900000000},
    "secondary":{"usedPercent":30,"windowDurationMins":10080,"resetsAt":1900600000}}
    """

    private func snapshot(allowed: String = "true", multi: String? = nil) throws -> QuotaSnapshot {
        let field = multi.map { ",\"rateLimitsByLimitId\":\($0)" } ?? ""
        return try QuotaSnapshot.decode(Data("{\"rateLimits\":\(bucket),\"ordinaryUsageAllowed\":\(allowed)\(field)}".utf8), email: "test@example.invalid")
    }

    @Test
    func testLegacyAndFractionalUsage() throws {
        let quota = try snapshot()
        #expect(quota.buckets["codex"]?.window(minutes: 300)?.usedPercent == 12.5)
        #expect(quota.buckets["codex"]?.window(minutes: 10080)?.usedPercent == 30)
        try quota.validateForProbe(limitID: "codex")
    }

    @Test
    func testPresentEmptyMultiBucketDoesNotFallback() throws {
        #expect(try snapshot(multi: "{}").buckets.isEmpty)
        expectThrows(try snapshot(multi: "{}").validateForProbe(limitID: "codex"))
    }

    @Test
    func testUnknownPermissionDoesNotAllowRequest() throws {
        expectThrows(try snapshot(allowed: "null").validateForProbe(limitID: "codex"))
        expectThrows(try snapshot(allowed: "false").validateForProbe(limitID: "codex"))
    }

    @Test
    func testMissingWeeklyWindowDoesNotBecomeZero() throws {
        let data = Data("{\"rateLimitsByLimitId\":{\"codex\":{\"primary\":{\"usedPercent\":1,\"windowDurationMins\":300}}},\"ordinaryUsageAllowed\":true}".utf8)
        let quota = try QuotaSnapshot.decode(data)
        #expect(quota.buckets["codex"]?.window(minutes: 10080) == nil)
        expectThrows(try quota.validateForProbe(limitID: "codex"))
    }

    @Test
    func testExhaustedWeeklyWindowBlocksRequest() throws {
        let data = Data("{\"rateLimits\":\(bucket.replacingOccurrences(of: "\"usedPercent\":30", with: "\"usedPercent\":100")),\"ordinaryUsageAllowed\":true}".utf8)
        expectThrows(try QuotaSnapshot.decode(data).validateForProbe(limitID: "codex"))
    }

    @Test
    func testInvalidUsageIsRejected() {
        let data = Data("{\"rateLimits\":\(bucket.replacingOccurrences(of: "12.5", with: "-1"))}".utf8)
        expectThrows(try QuotaSnapshot.decode(data))
    }

    @Test
    func testWindowTypesFollowDurationRatherThanPosition() throws {
        let reversed = bucket.replacingOccurrences(of: "300", with: "SWAP")
            .replacingOccurrences(of: "10080", with: "300").replacingOccurrences(of: "SWAP", with: "10080")
        let quota = try QuotaSnapshot.decode(Data("{\"rateLimits\":\(reversed)}".utf8))
        #expect(quota.buckets["codex"]?.window(minutes: 300)?.usedPercent == 30)
    }

    @Test
    func testUnchangedAndMissingResetsDoNotClaimStarted() {
        let old = QuotaWindow(usedPercent: 10, windowDurationMins: 300, resetsAt: 1900000000)
        let new = QuotaWindow(usedPercent: 10.5, windowDurationMins: 300, resetsAt: 1900000000)
        let comparison = WindowObservation.compare(before: old, after: new, minutes: 300)
        #expect(comparison.resetChange == "unchanged")
        #expect(comparison.usedPercentChange == 0.5)
        let missing = WindowObservation.compare(before: old, after: nil, minutes: 300)
        #expect(missing.usedPercentChange == nil)
        #expect(missing.resetChange == "resetUnavailable")
    }

    @Test
    func testContinuationRequiresResetTimeAndSameAccount() throws {
        let quota = try snapshot()
        var report = ProbeReport(account: "probe-1", limitID: "codex", model: "test", before: quota, previous: nil)
        report.after = quota
        report.status = "completed"
        expectThrows(try report.validateContinuation(account: "probe-1", snapshot: quota, now: Date(timeIntervalSince1970: 1899999999)))
        expectThrows(try report.validateContinuation(account: "probe-2", snapshot: quota, now: Date(timeIntervalSince1970: 1900000001)))
        try report.validateContinuation(account: "probe-1", snapshot: quota, now: Date(timeIntervalSince1970: 1900000001))
        let other = try QuotaSnapshot.decode(Data("{\"rateLimits\":\(bucket)}".utf8), email: "other@example.invalid")
        expectThrows(try report.validateContinuation(account: "probe-1", snapshot: other, now: Date(timeIntervalSince1970: 1900000001)))
    }

    @Test
    func testAccountPathRejectsTraversal() {
        expectThrows(try ProbePaths(account: "../.codex"))
        expectThrows(try ProbePaths(account: ""))
    }
}
