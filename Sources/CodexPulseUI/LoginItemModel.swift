import CodexPulseCore
import Combine
import Foundation
import ServiceManagement

@MainActor
public final class LoginItemModel: ObservableObject {
    @Published public private(set) var status: SMAppService.Status
    @Published public private(set) var isChanging = false
    @Published public private(set) var error: String?
    public let isInstalled: Bool
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () async throws -> Void
    private let readDefaultApplied: () -> Bool
    private let saveDefaultApplied: () -> Void

    public init(
        isInstalled: Bool = Bundle.main.bundleURL.resolvingSymlinksInPath().path == "/Applications/Codex Pulse.app",
        readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
        register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
        unregister: @escaping () async throws -> Void = { try await SMAppService.mainApp.unregister() },
        readDefaultApplied: @escaping () -> Bool = { UserDefaults.standard.bool(forKey: "loginItemDefaultApplied") },
        saveDefaultApplied: @escaping () -> Void = { UserDefaults.standard.set(true, forKey: "loginItemDefaultApplied") }
    ) {
        self.isInstalled = isInstalled
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        self.readDefaultApplied = readDefaultApplied
        self.saveDefaultApplied = saveDefaultApplied
        status = readStatus()
    }

    public var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    public func refresh() { status = readStatus() }

    public func applyDefaultIfNeeded() async {
        guard isInstalled, !isChanging, !readDefaultApplied() else { return }
        // 只在首次正式运行时尝试，避免覆盖用户后来关闭的系统登录项。
        saveDefaultApplied()
        await setEnabled(true)
    }

    public func setEnabled(_ enabled: Bool) async {
        guard !isChanging else { return }
        error = nil
        guard isInstalled else {
            error = PulseLocalization.text("loginItem.installRequired")
            return
        }
        if !readDefaultApplied() { saveDefaultApplied() }
        refresh()
        guard enabled != isEnabled else { return }
        isChanging = true
        defer { isChanging = false; refresh() }
        do {
            if enabled { try register() }
            else { try await unregister() }
            refresh()
            if enabled != isEnabled {
                error = PulseLocalization.text("loginItem.transitionFailed")
            }
        } catch {
            self.error = PulseLocalization.text("loginItem.error", (error as NSError).code)
        }
    }

    public func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
