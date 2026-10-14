//
//  LoginView.swift
//  LemonMusic
//

import SwiftUI

struct LoginView: View {
    @StateObject private var session = SessionStore.shared

    @State private var host = ""
    @State private var username = ""
    @State private var password = ""
    @State private var allowSelfSigned = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("🍋")
                            .font(.system(size: 56))
                            .foregroundStyle(.yellow)
                            .padding(.top, 24)
                        Text("柠檬音乐")
                            .font(.largeTitle.bold())
                        Text("连接你的自托管音乐服务器")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 14) {
                        labeledField("服务器地址") {
                            TextField("http://192.168.1.10:7983", text: $host)
                                .textContentType(.URL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        labeledField("用户名") {
                            TextField("用户名", text: $username)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        labeledField("密码") {
                            SecureField("密码", text: $password)
                                .textContentType(.password)
                        }

                        Toggle(isOn: $allowSelfSigned) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("允许自签名证书")
                                    .font(.subheadline)
                                Text("仅当服务器使用自签名 HTTPS 时开启")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal)

                    if let error = session.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Button {
                        Task {
                            session.allowSelfSigned = allowSelfSigned
                            await session.login(host: host, username: username, password: password)
                        }
                    } label: {
                        Group {
                            if session.isBusy {
                                ProgressView()
                            } else {
                                Text("登录").font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(host.isEmpty || username.isEmpty || password.isEmpty || session.isBusy)
                    .padding(.horizontal)

                    Text("首次使用？请先在服务器端（NAS / Docker）部署柠檬音乐，并在浏览器中完成初始账号设置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            host = session.serverHost
            username = session.username
            allowSelfSigned = session.allowSelfSigned
        }
    }

    @ViewBuilder
    private func labeledField<Content: View>(_ title: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
                .padding(12)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
