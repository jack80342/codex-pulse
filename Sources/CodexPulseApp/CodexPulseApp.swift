import CodexPulseUI
import SwiftUI
import AppKit

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    static let model = MenuBarModel.live()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await Self.model.startIfNeeded() }
    }
}

@main
struct CodexPulseApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    @StateObject private var model = ApplicationDelegate.model

    var body: some Scene {
        MenuBarExtra("Codex Pulse", systemImage: "waveform.path.ecg") {
            MenuBarPanel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
