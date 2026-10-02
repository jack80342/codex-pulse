import Foundation

public struct AppVersion: Comparable, Equatable, Sendable {
    public let text: String
    private let components: [Int]

    public init?(_ value: String) {
        let value = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  part.count == 1 || part.first != "0", let number = Int(part) else { return nil }
            numbers.append(number)
        }
        text = value
        components = numbers
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

public struct AppRelease: Sendable {
    public let version: AppVersion
    public let pageURL: URL
    public let downloadURL: URL?

    public init(version: AppVersion, pageURL: URL, downloadURL: URL?) {
        self.version = version
        self.pageURL = pageURL
        self.downloadURL = downloadURL
    }
}

public enum AppUpdateError: Error, CustomStringConvertible {
    case invalidVersion, invalidResponse, transport, timeout, rateLimited, http(Int)

    public var description: String {
        switch self {
        case .invalidVersion: PulseLocalization.text("update.error.version")
        case .invalidResponse: PulseLocalization.text("update.error.response")
        case .transport: PulseLocalization.text("update.error.network")
        case .timeout: PulseLocalization.text("update.error.timeout")
        case .rateLimited: PulseLocalization.text("update.error.rateLimit")
        case .http(let status): PulseLocalization.text("update.error.http", status)
        }
    }
}

/// 手动查询公开正式 Release，不携带账号凭据、Cookie 或认证信息。
public struct AppUpdateClient: Sendable {
    public static let endpoint = URL(string: "https://api.github.com/repos/jack80342/codex-pulse/releases/latest")!
    private let transport: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public init(transport: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse) = { try await Self.send($0) }) {
        self.transport = transport
    }

    public func latestRelease() async throws -> AppRelease {
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Codex-Pulse", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: HTTPURLResponse
        do { (data, response) = try await transport(request) }
        catch let error as URLError where error.code == .timedOut { throw AppUpdateError.timeout }
        catch is CancellationError { throw CancellationError() }
        catch { throw AppUpdateError.transport }
        if response.statusCode == 429 || (response.statusCode == 403 && response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0") {
            throw AppUpdateError.rateLimited
        }
        guard response.statusCode == 200 else { throw AppUpdateError.http(response.statusCode) }
        struct Release: Decodable {
            struct Asset: Decodable {
                let name: String
                let state: String
                let size: Int
                let browser_download_url: String
            }
            let tag_name: String
            let html_url: String
            let draft: Bool
            let prerelease: Bool
            let assets: [Asset]
        }
        guard data.count <= 2_097_152,
              let release = try? JSONDecoder().decode(Release.self, from: data),
              !release.draft, !release.prerelease,
              let version = AppVersion(release.tag_name),
              let page = Self.githubURL(release.html_url, prefix: "/jack80342/codex-pulse/releases/tag/") else {
            throw AppUpdateError.invalidResponse
        }
        let asset = release.assets.first { $0.name == "Codex-Pulse-\(version.text).dmg" && $0.state == "uploaded" && $0.size > 0 }
        var download: URL?
        if let asset {
            guard let url = Self.githubURL(asset.browser_download_url, prefix: "/jack80342/codex-pulse/releases/download/") else {
                throw AppUpdateError.invalidResponse
            }
            download = url
        }
        return AppRelease(version: version, pageURL: page, downloadURL: download)
    }

    private static func githubURL(_ string: String, prefix: String) -> URL? {
        guard let url = URL(string: string), url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
              url.path.hasPrefix(prefix), url.path.count > prefix.count,
              !url.path.split(separator: "/").contains("..") else { return nil }
        return url
    }

    public static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AppUpdateError.invalidResponse }
        return (data, response)
    }
}
