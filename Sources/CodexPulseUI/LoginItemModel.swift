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

    public init(
        isInstalled: Bool = Bundle.main.bundleURL.resolvingSymlinksInPath().path == "/Applications/Codex Pulse.app",
        readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
        register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
        unregister: @escaping () async throws -> Void = { try await SMAppService.mainApp.unregister() }
    ) {
        self.isInstalled = isInstalled
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        status = readStatus()
    }

    public var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    public func refresh() { status = readStatus() }

    public func setEnabled(_ enabled: Bool) async {
        guard !isChanging else { return }
        error = nil
        guard isInstalled else {
            error = "请先将 Codex Pulse 安装到应用程序目录。"
            return
        }
        refresh()
        guard enabled != isEnabled else { return }
        isChanging = true
        defer { isChanging = false; refresh() }
        do {
            if enabled { try register() }
            else { try await unregister() }
            refresh()
            if enabled != isEnabled {
                error = "系统未完成登录启动设置，请检查系统登录项。"
            }
        } catch {
            self.error = "无法更改登录启动设置（错误代码 \((error as NSError).code)）。"
        }
    }

    public func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
