import CodexPulseCore
import Foundation
import Testing

struct AccountProfileTests {
    private func fixture(_ body: (ProbePaths) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CodexPulseProfile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try ProbePaths(account: "test", root: root)
        try paths.prepare()
        try Data(#"{"tokens":{"access_token":"private-test-token","account_id":"test-account"}}"#.utf8)
            .write(to: paths.accountHome.appendingPathComponent("auth.json"))
        try body(paths)
    }

    @Test
    func testReadOnlyRequestUsesSelectedCredentialsAndRealProfileUsername() throws {
        try fixture { paths in
            let client = AccountProfileClient { request, _ in
                #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/profiles/me")
                #expect(request.httpMethod == "GET")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer private-test-token")
                #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-ID") == "test-account")
                #expect(request.httpBody == nil)
                return Data(#"{"profile_details":{"username":"actual-user","display_name":"Other name","email":"different@example.invalid"},"viewer_access":{}}"#.utf8)
            }
            let username = try client.readUsername(paths: paths)
            #expect(username == "actual-user")
        }
    }

    @Test
    func testMissingInvalidUsernameNeverUsesEmailOrDisplayName() throws {
        try fixture { paths in
            for response in [#"{"profile_details":{"display_name":"Someone","email":"prefix@example.invalid"}}"#,
                             #"{"profile_details":{"username":""}}"#, #"{"profile_details":{"username":12}}"#, "not-json"] {
                let client = AccountProfileClient { _, _ in Data(response.utf8) }
                #expect(throws: ProfileError.self) { try client.readUsername(paths: paths) }
            }
        }
    }

    @Test
    func testLinkedOrMalformedCredentialsAreRejectedBeforeNetwork() throws {
        try fixture { paths in
            let url = paths.accountHome.appendingPathComponent("auth.json")
            let client = AccountProfileClient { _, _ in
                Issue.record("无效凭据不得发送网络请求")
                return Data()
            }
            try Data(#"{"tokens":{"access_token":"token\nheader","account_id":"id"}}"#.utf8).write(to: url)
            #expect(throws: ProfileError.self) { try client.readUsername(paths: paths) }
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: paths.root.appendingPathComponent("outside"))
            #expect(throws: ProfileError.self) { try client.readUsername(paths: paths) }
        }
    }

    @Test
    func testUnexpectedTransportErrorsDoNotExposePrivateDetails() throws {
        try fixture { paths in
            let client = AccountProfileClient { _, _ in
                throw NSError(domain: "private-test-token", code: 7, userInfo: [NSLocalizedDescriptionKey: "private response"])
            }
            do {
                _ = try client.readUsername(paths: paths)
                Issue.record("请求应失败")
            } catch {
                #expect(String(describing: error) == ProfileError.transport.description)
                #expect(!String(describing: error).contains("private"))
            }
        }
    }
}
