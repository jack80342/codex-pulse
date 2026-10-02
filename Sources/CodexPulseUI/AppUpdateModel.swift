import CodexPulseCore
import Combine
import Foundation

@MainActor
public final class AppUpdateModel: ObservableObject {
    @Published public private(set) var isChecking = false
    @Published public private(set) var availableRelease: AppRelease?
    @Published public private(set) var message: String?
    @Published public private(set) var error: String?
    private let currentVersion: String?
    private let fetch: @Sendable () async throws -> AppRelease

    public init(currentVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                fetch: @escaping @Sendable () async throws -> AppRelease = { try await AppUpdateClient().latestRelease() }) {
        self.currentVersion = currentVersion
        self.fetch = fetch
    }

    public func check() async {
        guard !isChecking else { return }
        isChecking = true
        error = nil
        message = nil
        availableRelease = nil
        defer { isChecking = false }
        do {
            guard let currentVersion, let current = AppVersion(currentVersion) else { throw AppUpdateError.invalidVersion }
            let release = try await fetch()
            if release.version > current {
                availableRelease = release
                message = PulseLocalization.text("update.available", release.version.text)
            } else {
                message = PulseLocalization.text("update.current", current.text)
            }
        } catch is CancellationError {
            // 被取消的检查不显示成功结果，允许再次手动查询。
        } catch let error as AppUpdateError {
            self.error = error.description
        } catch {
            self.error = PulseLocalization.text("update.error.network")
        }
    }
}
