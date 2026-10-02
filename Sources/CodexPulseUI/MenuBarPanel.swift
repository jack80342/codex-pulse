import CodexPulseCore
import SwiftUI
import AppKit

public struct MenuBarPanel: View {
    @ObservedObject private var model: MenuBarModel
    @StateObject private var loginItem = LoginItemModel()

    public init(model: MenuBarModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Codex Pulse").font(.headline)
                    Text(model.isRunningAutomatic ? "正在检查自动请求…" : (model.isRefreshing ? "正在读取账号额度…" : "\(model.rows.count) 个账号"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isRefreshing { ProgressView().controlSize(.small) }
            }
            if let error = model.globalError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if model.rows.isEmpty && !model.isRefreshing && model.globalError == nil {
                ContentUnavailableView("尚未添加账号", systemImage: "person.crop.circle.badge.plus",
                                       description: Text("添加账号后，额度会显示在这里。"))
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.rows) { row in
                            AccountCard(row: row, refreshing: model.isRefreshing,
                                        automatic: model.automaticResults[row.id], runningAutomatic: model.isRunningAutomatic)
                        }
                    }
                }
                .frame(maxHeight: 580)
                .fixedSize(horizontal: false, vertical: true)
            }
            if !model.duplicateNames.isEmpty {
                Label("\(model.duplicateNames.joined(separator: "、"))使用同一账号，额度共享。", systemImage: "person.2")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Toggle("登录时启动", isOn: Binding(get: { loginItem.isEnabled }, set: { enabled in
                Task { await loginItem.setEnabled(enabled) }
            }))
                .toggleStyle(.switch).controlSize(.small)
                .disabled(loginItem.isChanging || !loginItem.isInstalled)
            if !loginItem.isInstalled {
                Text("安装到应用程序目录后可设置登录启动。")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if loginItem.status == .requiresApproval {
                HStack {
                    Text("登录启动等待系统批准").font(.caption2).foregroundStyle(.orange)
                    Spacer()
                    Button("前往系统设置") { loginItem.openSettings() }.controlSize(.small)
                }
            } else if loginItem.status == .notFound {
                Text("系统找不到登录项，请重新安装应用。")
                    .font(.caption2).foregroundStyle(.orange)
            }
            if let error = loginItem.error {
                Text(error).font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button {
                    Task { await model.refresh() }
                } label: { Label("立即刷新", systemImage: "arrow.clockwise") }
                .disabled(model.isRefreshing)
                .keyboardShortcut("r", modifiers: .command)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            if let date = model.lastCompletedAt {
                Text("上次查询完成 \(date.formatted(date: .omitted, time: .standard))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 390)
        .task { loginItem.refresh(); await model.startIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
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
                Text(refreshing ? "刷新中" : row.statusText)
                    .font(.caption).foregroundStyle(row.isStale || row.status?.error != nil ? .orange : .secondary)
            }
            QuotaLine(title: "五小时额度", window: row.bucket?.window(minutes: 300), stale: row.isStale || refreshing)
            QuotaLine(title: "周额度", window: row.bucket?.window(minutes: 10080), stale: row.isStale || refreshing)
            if let error = row.status?.error {
                Text(error).font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else if row.status?.state == "notLoggedIn" {
                Text("请先完成此账号的登录。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if row.snapshot?.ordinaryUsageAllowed == false {
                Label("服务端当前限制使用", systemImage: "pause.circle")
                    .font(.caption2).foregroundStyle(.orange)
            }
            if let error = row.status?.usernameError {
                Text(error).font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if row.isStale, let date = row.snapshot?.capturedAt {
                Text("上次成功更新 \(date.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if runningAutomatic {
                Text("正在检查自动请求…").font(.caption2).foregroundStyle(.secondary)
            } else if let automatic {
                Text(automatic.message).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let next = automatic.nextRequestAt {
                    Text("下次自动请求 \(next.formatted(date: .abbreviated, time: .shortened))")
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
                    Text("剩余 \(remaining.formatted(.number.precision(.fractionLength(0...1))))%")
                        .font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(tint)
                } else { Text("未知").font(.caption).foregroundStyle(.secondary) }
            }
            if let remaining {
                ProgressView(value: remaining, total: 100).tint(tint)
                    .accessibilityLabel(title).accessibilityValue("剩余 \(remaining)%")
            }
            if let reset = window?.resetsAt {
                let date = Date(timeIntervalSince1970: Double(reset))
                Text("服务端重置 \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            } else { Text("重置时间未知").font(.caption2).foregroundStyle(.secondary) }
        }
    }
}
