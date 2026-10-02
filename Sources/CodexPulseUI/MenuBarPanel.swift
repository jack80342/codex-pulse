import CodexPulseCore
import SwiftUI
import AppKit

// 使用传统 State 包装器，避免 CLT SDK 同名宏需要缺失的 SwiftUIMacros 插件。
private typealias ViewState<Value> = SwiftUI.State<Value>

public struct MenuBarPanel: View {
    @ObservedObject private var model: MenuBarModel
    @ObservedObject private var loginItem: LoginItemModel
    @ObservedObject private var accounts: AccountManagementModel
    @ObservedObject private var updates: AppUpdateModel
    @ViewState private var managing = false

    public init(model: MenuBarModel, loginItem: LoginItemModel = LoginItemModel(),
                accounts: AccountManagementModel? = nil, updates: AppUpdateModel = AppUpdateModel()) {
        self.model = model
        self.loginItem = loginItem
        self.accounts = accounts ?? AccountManagementModel.live(menu: model)
        self.updates = updates
    }

    private var headerStatus: String {
        if model.isRunningAutomatic { return PulseLocalization.text("ui.checkingAutomatic") }
        if model.isRefreshing { return PulseLocalization.text("ui.readingQuota") }
        return PulseLocalization.text(model.rows.count == 1 ? "ui.accounts.one" : "ui.accounts.many", model.rows.count)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Codex Pulse").font(.headline)
                    Text(headerStatus)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isRefreshing || updates.isChecking { ProgressView().controlSize(.small) }
                Menu {
                    Button(PulseLocalization.text(updates.isChecking ? "update.checking" : "update.check")) {
                        Task { await updates.check() }
                    }.disabled(updates.isChecking)
                    Divider()
                    Button(PulseLocalization.text("ui.quit")) { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body).foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(PulseLocalization.text("ui.more"))
                .accessibilityLabel(PulseLocalization.text("ui.more"))
            }
            if let error = model.globalError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if !managing {
                if model.rows.isEmpty && !model.isRefreshing && model.globalError == nil {
                    ContentUnavailableView(PulseLocalization.text("ui.noAccounts"), systemImage: "person.crop.circle.badge.plus",
                                           description: Text(PulseLocalization.text("ui.noAccountsDescription")))
                    Button(PulseLocalization.text("ui.addFirst")) {
                        managing = true
                        if accounts.executablePath != nil { Task { await accounts.add() } }
                    }
                    .disabled(accounts.isBusy)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(model.rows) { row in
                                AccountCard(row: row, refreshing: model.isRefreshing,
                                            automatic: model.automaticResults[row.id], runningAutomatic: model.isRunningAutomatic)
                            }
                        }
                    }
                    .frame(maxHeight: 440)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !model.duplicateNames.isEmpty {
                Label(PulseLocalization.text("ui.duplicates", model.duplicateNames.joined(separator: PulseLocalization.text("status.nameSeparator"))), systemImage: "person.2")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup(PulseLocalization.text("ui.manageAccounts"), isExpanded: $managing) {
                AccountManagementPanel(accounts: accounts, menu: model).padding(.top, 8)
            }
            Divider()
            Toggle(PulseLocalization.text("ui.launchAtLogin"), isOn: Binding(get: { loginItem.isEnabled }, set: { enabled in
                Task { await loginItem.setEnabled(enabled) }
            }))
                .toggleStyle(.switch).controlSize(.small)
                .disabled(loginItem.isChanging || !loginItem.isInstalled)
            if loginItem.isInstalled && loginItem.status == .requiresApproval {
                HStack {
                    Text(PulseLocalization.text("ui.loginApproval")).font(.caption2).foregroundStyle(.orange)
                    Spacer()
                    Button(PulseLocalization.text("ui.openSettings")) { loginItem.openSettings() }.controlSize(.small)
                }
            } else if loginItem.isInstalled && loginItem.status == .notFound {
                Text(PulseLocalization.text("ui.loginItemMissing"))
                    .font(.caption2).foregroundStyle(.orange)
            }
            if let error = loginItem.error {
                Text(error).font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button {
                    Task { await model.refresh() }
                } label: { Label(PulseLocalization.text("ui.refresh"), systemImage: "arrow.clockwise") }
                .disabled(model.isRefreshing || accounts.isBusy)
                .keyboardShortcut("r", modifiers: .command)
                Spacer()
            }
            if let date = model.lastCompletedAt {
                Text(PulseLocalization.text("ui.lastQuery", PulseLocalization.formatDate(date, dateStyle: .omitted, timeStyle: .standard)))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let error = updates.error {
                Text(error).font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else if let message = updates.message {
                Text(message).font(.caption2).foregroundStyle(.secondary)
                if let release = updates.availableRelease {
                    HStack {
                        Link(PulseLocalization.text("update.view"), destination: release.pageURL)
                        if let download = release.downloadURL {
                            Link(PulseLocalization.text("update.download"), destination: download)
                        } else {
                            Text(PulseLocalization.text("update.noInstaller")).foregroundStyle(.secondary)
                        }
                    }.font(.caption)
                }
            }
        }
        .padding(18)
        .frame(width: 390)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.locale, PulseLocalization.locale)
        .background {
            GeometryReader { geometry in
                MenuBarWindowSizer(size: geometry.size)
            }.allowsHitTesting(false)
        }
        .task { accounts.checkExecutable(); loginItem.refresh(); await model.startIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
            accounts.checkExecutable()
        }
    }
}

private struct AccountCard: View {
    let row: MenuAccountRow
    let refreshing: Bool
    let automatic: AutomaticRequestResult?
    let runningAutomatic: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.displayName).font(.subheadline.weight(.semibold))
                    .lineLimit(1).help(row.displayName)
                Text(row.plan).font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Spacer()
                Text(refreshing ? PulseLocalization.text("ui.refreshing") : row.statusText)
                    .font(.caption).foregroundStyle(row.isStale || row.status?.error != nil ? .orange : .secondary)
            }
            QuotaLine(title: PulseLocalization.text("quota.fiveHour"), window: row.bucket?.window(minutes: 300), stale: row.isStale || refreshing)
            QuotaLine(title: PulseLocalization.text("quota.weekly"), window: row.bucket?.window(minutes: 10080), stale: row.isStale || refreshing)
            if let error = row.status?.error {
                Text(error).font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else if row.status?.state == "notLoggedIn" {
                Text(PulseLocalization.text("ui.signInFirst"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if row.snapshot?.ordinaryUsageAllowed == false {
                Label(PulseLocalization.text("quota.restricted"), systemImage: "pause.circle")
                    .font(.caption2).foregroundStyle(.orange)
            }
            if let error = row.status?.usernameError {
                Text(error).font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if row.isStale, let date = row.snapshot?.capturedAt {
                Text(PulseLocalization.text("ui.lastSuccess", PulseLocalization.formatDate(date, dateStyle: .abbreviated, timeStyle: .standard)))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if runningAutomatic {
                Text(PulseLocalization.text("ui.checkingAutomatic")).font(.caption2).foregroundStyle(.secondary)
            } else if let automatic {
                Text(automatic.message).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let next = automatic.nextRequestAt {
                    Text(PulseLocalization.text("ui.nextAutomatic", PulseLocalization.formatDate(next, dateStyle: .abbreviated, timeStyle: .shortened)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct QuotaLine: View {
    let title: String
    let window: QuotaWindow?
    let stale: Bool

    private var remaining: Double? { window.map { 100 - $0.usedPercent } }
    private func remainingText(_ remaining: Double) -> String {
        let number = remaining.formatted(.number.precision(.fractionLength(0...1)).locale(PulseLocalization.locale))
        return PulseLocalization.text("quota.remaining", number)
    }
    private var tint: Color {
        guard !stale, let remaining else { return .secondary }
        return remaining > 50 ? .green : (remaining >= 20 ? .yellow : .red)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                if let remaining {
                    Text(remainingText(remaining))
                        .font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(tint)
                } else { Text(PulseLocalization.text("quota.unknown")).font(.caption).foregroundStyle(.secondary) }
            }
            if let remaining {
                ProgressView(value: remaining, total: 100).tint(tint)
                    .accessibilityLabel(title).accessibilityValue(remainingText(remaining))
            }
            if let reset = window?.resetsAt {
                let date = Date(timeIntervalSince1970: Double(reset))
                Text(PulseLocalization.text("quota.serverReset", PulseLocalization.formatDate(date, dateStyle: .abbreviated, timeStyle: .shortened)))
                    .font(.caption2).foregroundStyle(.secondary)
            } else { Text(PulseLocalization.text("quota.resetUnknown")).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}
