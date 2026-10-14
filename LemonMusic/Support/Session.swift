//
//  Session.swift
//  LemonMusic
//
//  登录状态管理：服务器地址 / token / 偏好设置（Keychain + UserDefaults）
//

import Foundation
import Combine
import Security

@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published var serverHost: String {
        didSet { UserDefaults.standard.set(serverHost, forKey: "serverHost") }
    }
    @Published var username: String {
        didSet { UserDefaults.standard.set(username, forKey: "username") }
    }
    @Published var allowSelfSigned: Bool {
        didSet {
            UserDefaults.standard.set(allowSelfSigned, forKey: "allowSelfSigned")
            LemonAPI.shared.allowSelfSigned = allowSelfSigned
        }
    }
    @Published var loggedIn = false
    @Published var user: LemonUser?
    @Published var isBusy = false
    @Published var lastError: String?

    private init() {
        serverHost = UserDefaults.standard.string(forKey: "serverHost") ?? ""
        username = UserDefaults.standard.string(forKey: "username") ?? ""
        allowSelfSigned = UserDefaults.standard.bool(forKey: "allowSelfSigned")
        LemonAPI.shared.allowSelfSigned = allowSelfSigned
    }

    // MARK: Keychain

    private func keychainKey() -> String {
        "com.lemonmusic.token.\(serverHost)"
    }

    private func saveToken(_ token: String) {
        let key = keychainKey().data(using: .utf8)!
        let value = token.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = value
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private func loadToken() -> String? {
        let key = keychainKey().data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    private func deleteToken() {
        let key = keychainKey().data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: 登录 / 恢复

    func login(host: String, username: String, password: String) async {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            try LemonAPI.shared.configure(host: host)
            let resp = try await LemonAPI.shared.login(username: username, password: password)
            guard let token = resp.token else {
                lastError = "登录失败：未返回 token"
                return
            }
            self.serverHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            self.username = username
            saveToken(token)
            LemonAPI.shared.token = token
            self.user = resp.user
            self.loggedIn = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 启动时尝试用保存的 token 恢复会话
    func restore() async {
        guard !serverHost.isEmpty else { return }
        guard let token = loadToken() else { return }
        do {
            try LemonAPI.shared.configure(host: serverHost)
            LemonAPI.shared.token = token
            let me = try await LemonAPI.shared.me()
            if let t = me.token, t != token {
                saveToken(t)
                LemonAPI.shared.token = t
            }
            self.user = me.user
            self.loggedIn = true
        } catch let e as LemonAPIError {
            if case .notLoggedIn = e {
                deleteToken()
                LemonAPI.shared.token = nil
            }
            self.loggedIn = false
        } catch {
            // 网络失败也保持已保存的服务器地址，方便重试
            self.loggedIn = false
        }
    }

    func logout() async {
        try? await LemonAPI.shared.logout()
        deleteToken()
        user = nil
        loggedIn = false
    }
}
