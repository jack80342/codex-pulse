import Foundation
import Darwin

public enum ProfileError: Error, CustomStringConvertible {
    case credentialsUnavailable, invalidResponse, timeout, transport, http(Int)

    public var description: String {
        switch self {
        case .credentialsUnavailable: PulseLocalization.text("error.profile.credentials")
        case .invalidResponse: PulseLocalization.text("error.profile.invalidResponse")
        case .timeout: PulseLocalization.text("error.profile.timeout")
        case .transport: PulseLocalization.text("error.profile.transport")
        case .http(let status): PulseLocalization.text("error.profile.http", status)
        }
    }
}

/// 仅访问用户授权的只读资料接口，凭据来自当前账号的独立 CODEX_HOME。
public struct AccountProfileClient: Sendable {
    private let timeout: TimeInterval
    private let transport: @Sendable (URLRequest, TimeInterval) throws -> Data

    public init(timeout: TimeInterval = 15) {
        self.timeout = timeout
        transport = { try Self.send($0, timeout: $1) }
    }

    public init(timeout: TimeInterval = 15, transport: @escaping @Sendable (URLRequest, TimeInterval) throws -> Data) {
        self.timeout = timeout
        self.transport = transport
    }

    public func readUsername(paths: ProbePaths) throws -> String {
        guard timeout.isFinite, timeout > 0, timeout <= 300 else { throw ProfileError.timeout }
        let credentials = try Self.credentials(at: paths.accountHome.appendingPathComponent("auth.json"))
        guard let url = URL(string: "https://chatgpt.com/backend-api/profiles/me") else { throw ProfileError.transport }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexPulse/0.3.0", forHTTPHeaderField: "User-Agent")
        let data: Data
        do { data = try transport(request, timeout) }
        catch let error as ProfileError { throw error }
        catch { throw ProfileError.transport }
        struct Response: Decodable {
            struct Details: Decodable { let username: String? }
            let profile_details: Details
        }
        guard data.count <= 1_048_576,
              let response = try? JSONDecoder().decode(Response.self, from: data),
              let value = response.profile_details.username else { throw ProfileError.invalidResponse }
        let username = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, username.count <= 64,
              !username.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ProfileError.invalidResponse
        }
        return username
    }

    private static func credentials(at url: URL) throws -> (token: String, accountID: String) {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ProfileError.credentialsUnavailable }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1, info.st_size > 0, info.st_size <= 1_048_576 else {
            throw ProfileError.credentialsUnavailable
        }
        struct Auth: Decodable {
            struct Tokens: Decodable { let access_token: String; let account_id: String }
            let tokens: Tokens
        }
        guard let data = try? file.read(upToCount: 1_048_577),
              let auth = try? JSONDecoder().decode(Auth.self, from: data),
              !auth.tokens.access_token.isEmpty, !auth.tokens.account_id.isEmpty,
              !auth.tokens.access_token.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !auth.tokens.account_id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ProfileError.credentialsUnavailable
        }
        return (auth.tokens.access_token, auth.tokens.account_id)
    }

    private static func send(_ request: URLRequest, timeout: TimeInterval) throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration, delegate: ProfileRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let result = ProfileRequestResult()
        let task = session.dataTask(with: request) { result.complete($0, $1, $2) }
        task.resume()
        let response = try result.wait(timeout: timeout)
        guard (200..<300).contains(response.1.statusCode) else { throw ProfileError.http(response.1.statusCode) }
        return response.0
    }
}

private final class ProfileRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private final class ProfileRequestResult: @unchecked Sendable {
    private let condition = NSCondition()
    private var result: Result<(Data, HTTPURLResponse), ProfileError>?

    func complete(_ data: Data?, _ response: URLResponse?, _ error: Error?) {
        condition.lock()
        defer { condition.unlock() }
        if let error = error as? URLError, error.code == .timedOut { result = .failure(.timeout) }
        else if error != nil { result = .failure(.transport) }
        else if let data, let response = response as? HTTPURLResponse { result = .success((data, response)) }
        else { result = .failure(.invalidResponse) }
        condition.broadcast()
    }

    func wait(timeout: TimeInterval) throws -> (Data, HTTPURLResponse) {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while result == nil {
            if !condition.wait(until: deadline), result == nil { throw ProfileError.timeout }
        }
        guard let result else { throw ProfileError.timeout }
        return try result.get()
    }
}
