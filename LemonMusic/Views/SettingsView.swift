//
//  SettingsView.swift
//  LemonMusic
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var session = SessionStore.shared
    @State private var serverInfo: ServerInfo?
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section("账号") {
                    LabeledContent("用户", value: session.user?.displayName ?? "—")
                    LabeledContent("角色", value: session.user?.role ?? "—")
                    if let email = session.user?.email, !email.isEmpty {
                        LabeledContent("邮箱", value: email)
                    }
                }

                Section("服务器") {
                    LabeledContent("地址", value: session.serverHost)
                    LabeledContent("版本", value: serverInfo?.appVersion ?? "—")
                    LabeledContent("API", value: serverInfo.map { "v\($0.apiVersion ?? 1)" } ?? "—")
                    Button {
                        Task { await loadServerInfo() }
                    } label: {
                        Label("刷新服务器信息", systemImage: "arrow.clockwise")
                    }
                }

                Section("连接") {
                    Toggle(isOn: Binding(
                        get: { session.allowSelfSigned },
                        set: { session.allowSelfSigned = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("允许自签名证书")
                            Text("重启 App 或重新登录后生效于流媒体连接")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("关于") {
                    LabeledContent("App 版本", value: appVersion)
                    Link(destination: URL(string: "https://github.com/jia070310/lemon-muisc")!) {
                        Label("服务端项目主页", systemImage: "link")
                    }
                    Text("本客户端通过柠檬音乐开放 API（/api/v1）连接你的自托管服务器，不内置任何音源。请仅用于个人已合法授权的音乐资源。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("退出登录", role: .destructive) {
                        showLogoutConfirm = true
                    }
                }
            }
            .navigationTitle("设置")
            .confirmationDialog("确定退出登录？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) {
                    Task { await session.logout() }
                }
                Button("取消", role: .cancel) {}
            }
        }
        .task { await loadServerInfo() }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func loadServerInfo() async {
        serverInfo = try? await LemonAPI.shared.serverInfo()
    }
}
