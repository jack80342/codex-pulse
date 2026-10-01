import Foundation
import CryptoKit

public struct QuotaWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let windowDurationMins: Int?
    public let resetsAt: Int64?

    public init(usedPercent: Double, windowDurationMins: Int?, resetsAt: Int64?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
}

public struct QuotaBucket: Codable, Sendable {
    public let limitId: String?
    public let planType: String?
    public let primary: QuotaWindow?
    public let secondary: QuotaWindow?
    public let rateLimitReachedType: String?
    public let spendControlReached: Bool?

    public var windows: [QuotaWindow] { [primary, secondary].compactMap { $0 } }
    public func window(minutes: Int) -> QuotaWindow? {
        windows.first { $0.windowDurationMins == minutes }
    }
}

private struct RateLimitsResponse: Decodable {
    let rateLimits: QuotaBucket?
    let rateLimitsByLimitId: [String: QuotaBucket]?
    let ordinaryUsageAllowed: Bool?
    let accountId: String?
}

public struct QuotaSnapshot: Codable, Sendable {
    public let capturedAt: Date
    public let identityDigest: String?
    public let ordinaryUsageAllowed: Bool?
    public let buckets: [String: QuotaBucket]

    public static func decode(_ data: Data, email: String? = nil, at date: Date = Date()) throws -> Self {
        let response: RateLimitsResponse
        do { response = try JSONDecoder().decode(RateLimitsResponse.self, from: data) }
        catch { throw ProbeError.invalidResponse }
        let buckets: [String: QuotaBucket]
        if let multi = response.rateLimitsByLimitId {
            buckets = multi
        } else if let legacy = response.rateLimits {
            buckets = [legacy.limitId ?? "legacy": legacy]
        } else {
            throw ProbeError.invalidResponse
        }
        for window in buckets.values.flatMap(\.windows) {
            guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent),
                  window.windowDurationMins.map({ $0 > 0 }) ?? true,
                  window.resetsAt.map({ $0 > 0 }) ?? true else { throw ProbeError.invalidResponse }
        }
        let identity = response.accountId ?? email
        let digest = identity.map {
            SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        return Self(capturedAt: date, identityDigest: digest,
                    ordinaryUsageAllowed: response.ordinaryUsageAllowed, buckets: buckets)
    }

    public func validateForProbe(limitID: String) throws {
        guard let bucket = buckets[limitID], let fiveHour = bucket.window(minutes: 300),
              let weekly = bucket.window(minutes: 10080) else { throw ProbeError.unknownQuota }
        if ordinaryUsageAllowed == false || bucket.rateLimitReachedType != nil ||
            bucket.spendControlReached == true || fiveHour.usedPercent >= 100 || weekly.usedPercent >= 100 {
            throw ProbeError.exhaustedQuota
        }
        guard ordinaryUsageAllowed == true else { throw ProbeError.unknownQuota }
    }
}

public struct WindowObservation: Codable, Sendable {
    public let durationMinutes: Int
    public let beforeUsedPercent: Double?
    public let afterUsedPercent: Double?
    public let usedPercentChange: Double?
    public let beforeResetsAt: Int64?
    public let afterResetsAt: Int64?
    public let resetChange: String

    public static func compare(before: QuotaWindow?, after: QuotaWindow?, minutes: Int) -> Self {
        let resetChange: String
        switch (before?.resetsAt, after?.resetsAt) {
        case (nil, nil): resetChange = "unknown"
        case (nil, .some): resetChange = "newResetObserved"
        case (.some, nil): resetChange = "resetUnavailable"
        case let (.some(old), .some(new)):
            resetChange = new > old ? "advanced" : (new == old ? "unchanged" : "movedEarlier")
        }
        return Self(
            durationMinutes: minutes, beforeUsedPercent: before?.usedPercent,
            afterUsedPercent: after?.usedPercent,
            usedPercentChange: before.flatMap { old in after.map { $0.usedPercent - old.usedPercent } },
            beforeResetsAt: before?.resetsAt, afterResetsAt: after?.resetsAt, resetChange: resetChange
        )
    }
}

public struct ProbeReport: Codable, Sendable {
    public let schemaVersion: Int
    public let accountAlias: String
    public let limitID: String
    public let model: String
    public let phase: String
    public let before: QuotaSnapshot
    public let previousReportPath: String?
    public var after: QuotaSnapshot?
    public var status: String
    public var failure: String?
    public var observations: [WindowObservation]
    public let conclusion: String

    public init(account: String, limitID: String, model: String, before: QuotaSnapshot, previous: URL?) {
        schemaVersion = 1
        accountAlias = account
        self.limitID = limitID
        self.model = model
        phase = previous == nil ? "initial" : "afterReset"
        self.before = before
        previousReportPath = previous?.path
        status = "pending"
        observations = []
        conclusion = "仅记录观测；不能据此承诺请求必定启动五小时窗口。"
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func load(from url: URL) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: Data(contentsOf: url))
    }

    public func validateContinuation(account: String, snapshot: QuotaSnapshot, now: Date = Date()) throws {
        guard status == "completed", accountAlias == account, let after,
              let identity = after.identityDigest, identity == snapshot.identityDigest,
              let reset = after.buckets[limitID]?.window(minutes: 300)?.resetsAt else {
            throw ProbeError.invalidArgument("原报告不完整或账号不一致，不能用于重置后验证。")
        }
        guard now.timeIntervalSince1970 >= Double(reset) else {
            throw ProbeError.invalidArgument("尚未到达服务端记录的五小时重置时间，请到期后再执行。")
        }
    }
}
