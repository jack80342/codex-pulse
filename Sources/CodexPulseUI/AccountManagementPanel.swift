import CodexPulseCore
import SwiftUI

// 使用传统 State 包装器，避免 CLT SDK 同名宏需要缺失的 SwiftUIMacros 插件。
private typealias ViewState<Value> = SwiftUI.State<Value>

struct AccountManagementPanel: View {
    @ObservedObject var accounts: AccountManagementModel
    @ObservedObject var menu: MenuBarModel
    @ViewState private var confirmation: Confirmation?

    private struct Confirmation {
        let row: MenuAccountRow
        let removing: Bool
    }

    private var disabled: Bool { accounts.isBusy || menu.isRefreshing }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if accounts.executablePath == nil {
                Text(PulseLocalization.text("account.cliMissing"))
                    .font(.caption).foregroundStyle(.orange)
                HStack {
                    Link(PulseLocalization.text("account.installGuide"), destination: URL(string: "https://github.com/openai/codex#installing-and-running-codex-cli")!)
                    Button(PulseLocalization.text("account.detectAgain")) {
                        accounts.checkExecutable()
                        Task { await menu.refresh() }
                    }.disabled(disabled)
                }.font(.caption).disabled(confirmation != nil)
            }
            Button(PulseLocalization.text("account.add")) { Task { await accounts.add() } }
                .disabled(disabled || accounts.executablePath == nil || confirmation != nil)
            Text(PulseLocalization.text("account.loginGuide"))
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let message = accounts.message {
                Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            if let error = accounts.error {
                Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if accounts.isLoggingIn {
                HStack {
                    ProgressView().controlSize(.small)
                    Button(PulseLocalization.text("account.cancelLogin")) { accounts.cancelLogin() }.controlSize(.small)
                }
            }
            if let target = confirmation {
                VStack(alignment: .leading, spacing: 10) {
                    Text(target.removing ? PulseLocalization.text("account.deleteTitle") : PulseLocalization.text("account.reloginTitle")).font(.headline)
                    Text(target.removing
                         ? PulseLocalization.text("account.deleteDescription", target.row.displayName)
                         : PulseLocalization.text("account.reloginDescription", target.row.displayName))
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button(PulseLocalization.text("account.cancel"), role: .cancel) { confirmation = nil }
                        Button(target.removing ? PulseLocalization.text("account.delete") : PulseLocalization.text("account.relogin"), role: .destructive) {
                            confirmation = nil
                            Task {
                                if target.removing { await accounts.remove(id: target.row.id) }
                                else { await accounts.login(id: target.row.id, force: true) }
                            }
                        }.disabled(disabled)
                    }
                }
                .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            } else if !menu.rows.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(menu.rows) { row in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.displayName).lineLimit(1)
                                    Text(row.statusText).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !row.account.pendingDeletion {
                                    Button(row.status?.state == "notLoggedIn" || row.status == nil ? PulseLocalization.text("account.login") : PulseLocalization.text("account.relogin")) {
                                        if row.status?.state == "notLoggedIn" || row.status == nil {
                                            Task { await accounts.login(id: row.id) }
                                        } else {
                                            confirmation = Confirmation(row: row, removing: false)
                                        }
                                    }
                                }
                                Button(row.account.pendingDeletion ? PulseLocalization.text("account.retryDelete") : PulseLocalization.text("account.delete"), role: .destructive) {
                                    confirmation = Confirmation(row: row, removing: true)
                                }
                            }
                            .controlSize(.small).disabled(disabled)
                        }
                    }
                }
                .frame(maxHeight: 180).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { accounts.checkExecutable() }
    }
}
