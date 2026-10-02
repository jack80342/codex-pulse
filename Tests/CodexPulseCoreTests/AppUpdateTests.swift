@testable import CodexPulseCore
import Foundation
import Testing

struct AppUpdateTests {
    private func fixture(tag: String = "v0.8.0", draft: Bool = false, prerelease: Bool = false,
                         page: String = "https://github.com/jack80342/codex-pulse/releases/tag/v0.8.0",
                         assetURL: String = "https://github.com/jack80342/codex-pulse/releases/download/v0.8.0/Codex-Pulse-0.8.0.dmg",
                         assetName: String = "Codex-Pulse-0.8.0.dmg", assetState: String = "uploaded") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["tag_name": tag, "draft": draft, "prerelease": prerelease,
            "html_url": page, "assets": [["name": assetName, "state": assetState, "size": 1024,
                                         "browser_download_url": assetURL]]])
    }

    @Test func numericVersionComparisonAndInvalidVersions() throws {
        #expect(try #require(AppVersion("0.7.10")) > #require(AppVersion("v0.7.9")))
        #expect(AppVersion("v1.0.0") == AppVersion("1.0.0"))
        #expect(try #require(AppVersion("1.0.0")) > #require(AppVersion("0.99.99")))
        for value in ["", "1.2", "1.2.3.4", "1.2.3-beta.1", "1.02.3", "-1.2.3", "１.2.3", "1.2.99999999999999999999999"] {
            #expect(AppVersion(value) == nil)
        }
    }

    @Test func readsPublicReleaseWithoutCredentials() async throws {
        let data = try fixture()
        let release = try await AppUpdateClient { request in
            #expect(request.url == AppUpdateClient.endpoint)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.timeoutInterval == 15)
            return (data, HTTPURLResponse(url: AppUpdateClient.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }.latestRelease()
        #expect(release.version.text == "0.8.0")
        #expect(release.downloadURL?.lastPathComponent == "Codex-Pulse-0.8.0.dmg")
    }

    @Test func rejectsDraftPrereleaseMalformedDataAndExternalLinks() async throws {
        let cases = try [fixture(draft: true), fixture(prerelease: true), fixture(tag: "v0.8.0-rc.1"),
                         fixture(page: "https://example.com/release"),
                         fixture(assetURL: "https://github.com.attacker.test/jack80342/codex-pulse/releases/download/a"),
                         fixture(assetURL: "http://github.com/jack80342/codex-pulse/releases/download/a"),
                         fixture(assetURL: "https://user:password@github.com/jack80342/codex-pulse/releases/download/a"),
                         Data("{}".utf8)]
        for data in cases {
            await #expect(throws: AppUpdateError.self) {
                try await AppUpdateClient { _ in
                    (data, HTTPURLResponse(url: AppUpdateClient.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }.latestRelease()
            }
        }
    }

    @Test func missingOrIncompleteInstallerStillOffersReleasePage() async throws {
        for data in try [fixture(assetName: "Source.zip"), fixture(assetState: "starter")] {
            let release = try await AppUpdateClient { _ in
                (data, HTTPURLResponse(url: AppUpdateClient.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }.latestRelease()
            #expect(release.downloadURL == nil)
            #expect(release.pageURL.host == "github.com")
        }
    }

    @Test func HTTPAndTransportFailuresAreReportedAccurately() async throws {
        for (status, remaining, expected) in [(403, "0", "rate"), (429, "1", "rate"), (403, "1", "http"), (404, "1", "http")] {
            do {
                _ = try await AppUpdateClient { _ in
                    (Data(), HTTPURLResponse(url: AppUpdateClient.endpoint, statusCode: status, httpVersion: nil,
                                             headerFields: ["X-RateLimit-Remaining": remaining])!)
                }.latestRelease()
                Issue.record("Expected HTTP error")
            } catch let error as AppUpdateError {
                switch error {
                case .rateLimited: #expect(expected == "rate")
                case .http(let code): #expect(expected == "http" && code == status)
                default: Issue.record("Unexpected error: \(error)")
                }
            }
        }
        do {
            _ = try await AppUpdateClient { _ in throw URLError(.timedOut) }.latestRelease()
            Issue.record("Expected timeout")
        } catch let error as AppUpdateError {
            guard case .timeout = error else { Issue.record("Unexpected error: \(error)"); return }
        }
    }
}
