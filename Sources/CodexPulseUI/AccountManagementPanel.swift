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
                Text("未找到本机 Codex CLI，请安装后重新检测。")
                    .font(.caption).foregroundStyle(.orange)
                HStack {
                    Link("安装说明", destination: URL(string: "https://github.com/openai/codex#installing-and-running-codex-cli")!)
                    Button("重新检测") {
                        accounts.checkExecutable()
                        Task { await menu.refresh() }
                    }.disabled(disabled)
                }.font(.caption).disabled(confirmation != nil)
            }
            Button("添加账号") { Task { await accounts.add() } }
                .disabled(disabled || accounts.executablePath == nil || confirmation != nil)
            Text("在浏览器中确认目标账号。登录后自动读取真实用户名及额度，并启用符合条件账号的最小请求调度；请求会消耗额度。")
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
                    Button("取消登录") { accounts.cancelLogin() }.controlSize(.small)
                }
            }
            if let target = confirmation {
                VStack(alignment: .leading, spacing: 10) {
                    Text(target.removing ? "删除本地账号？" : "重新登录账号？").font(.headline)
                    Text(target.removing
                         ? "将删除 \(target.row.displayName) 在本工具中的登录数据并停止调度，保留历史验证报告。不会删除 ChatGPT 账号。"
                         : "将退出 \(target.row.displayName) 在本工具中的当前登录，再打开浏览器授权。取消或失败后可重试登录。")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("取消", role: .cancel) { confirmation = nil }
                        Button(target.removing ? "删除" : "重新登录", role: .destructive) {
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
                                    Button(row.status?.state == "notLoggedIn" || row.status == nil ? "登录" : "重新登录") {
                                        if row.status?.state == "notLoggedIn" || row.status == nil {
                                            Task { await accounts.login(id: row.id) }
                                        } else {
                                            confirmation = Confirmation(row: row, removing: false)
                                        }
                                    }
                                }
                                Button(row.account.pendingDeletion ? "重试删除" : "删除", role: .destructive) {
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
