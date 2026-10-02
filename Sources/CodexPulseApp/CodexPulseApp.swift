import CodexPulseUI
import SwiftUI
import AppKit

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    static let model = MenuBarModel.live()
    static let loginItem = LoginItemModel()
    static let accounts = AccountManagementModel.live(menu: model)
    static let updates = AppUpdateModel()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var clockObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = Self.model
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in model.suspendForSleep() }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await model.resumeAfterWake() }
        })
        clockObserver = NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { _ in
            Task { @MainActor in await model.resumeAfterWake() }
        }
        Task {
            await Self.loginItem.applyDefaultIfNeeded()
            await Self.model.startIfNeeded()
        }
    }
}

@main
struct CodexPulseApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    @StateObject private var model = ApplicationDelegate.model

    var body: some Scene {
        MenuBarExtra("Codex Pulse", systemImage: "waveform.path.ecg") {
            MenuBarPanel(model: model, loginItem: ApplicationDelegate.loginItem, accounts: ApplicationDelegate.accounts,
                         updates: ApplicationDelegate.updates)
        }
        .menuBarExtraStyle(.window)
    }
}
