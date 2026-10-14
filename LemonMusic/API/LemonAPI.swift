//
//  LemonAPI.swift
//  LemonMusic
//
//  /api/v1 开放 API 客户端（Bearer 鉴权、自签名证书可选信任）
//

import Foundation

enum LemonAPIError: LocalizedError {
    case invalidURL
    case network(String)
    case server(String, Int)
    case decode(String)
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "服务器地址无效"
        case .network(let m): return "网络错误：\(m)"
        case .server(let m, let code): return code > 0 ? "服务端错误(\(code))：\(m)" : m
        case .decode(let m): return "数据解析失败：\(m)"
        case .notLoggedIn: return "未登录"
        }
    }
}

// MARK: - 服务端错误体 { error: "..." }

private struct ServerErrorBody: Decodable {
    let error: String?
    let message: String?
}

final class TrustAllDelegate: NSObject, URLSessionDelegate {
    /// 用户显式开启「允许自签名证书」时才生效
    var allowSelfSigned = false

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if allowSelfSigned,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - API 客户端

final class LemonAPI {
    static let shared = LemonAPI()

    private(set) var baseURL: URL = URL(string: "http://localhost:7983")!
    var token: String?
    private let trustDelegate = TrustAllDelegate()
    private var session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config, delegate: trustDelegate, delegateQueue: nil)
    }

    /// 输入主机地址（可省略 http://，可带端口/路径前缀），归一化为 API 根地址
    func configure(host: String) throws {
        var s = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { throw LemonAPIError.invalidURL }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "http://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host != nil else { throw LemonAPIError.invalidURL }
        baseURL = url
    }

    var allowSelfSigned: Bool {
        get { trustDelegate.allowSelfSigned }
        set {
            trustDelegate.allowSelfSigned = newValue
            if newValue {
                let config = session.configuration
                session = URLSession(configuration: config, delegate: trustDelegate, delegateQueue: nil)
            }
        }
    }

    // MARK: 基础请求

    private func makeURL(_ path: String, query: [URLQueryItem] = []) -> URL? {
        let root = baseURL.appendingPathComponent("api/v1")
        guard var comps = URLComponents(url: root.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            return nil
        }
        if !query.isEmpty { comps.queryItems = query }
        return comps.url
    }

    private func request(_ path: String,
                         method: String = "GET",
                         query: [URLQueryItem] = [],
                         body: [String: JSONValue]? = nil) async throws -> Data {
        guard let url = makeURL(path, query: query) else { throw LemonAPIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw LemonAPIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw LemonAPIError.network("无响应")
        }
        if http.statusCode == 401 { throw LemonAPIError.notLoggedIn }
        if !(200..<300).contains(http.statusCode) {
            let msg = (try? JSONDecoder().decode(ServerErrorBody.self, from: data))?.error
                ?? (try? JSONDecoder().decode(ServerErrorBody.self, from: data))?.message
                ?? String(data: data, encoding: .utf8) ?? "未知错误"
            throw LemonAPIError.server(msg, http.statusCode)
        }
        return data
    }

    private func get<T: Decodable>(_ type: T.Type, _ path: String,
                                   query: [URLQueryItem] = []) async throws -> T {
        let data = try await request(path, query: query)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LemonAPIError.decode(error.localizedDescription)
        }
    }

    // MARK: 服务器 / 鉴权

    func serverInfo() async throws -> ServerInfo {
        // 元信息不需要鉴权前缀 /api/v1 即为资源路径 "/"
        let root = baseURL.appendingPathComponent("api/v1")
        var req = URLRequest(url: root)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await session.data(for: req)
        return try JSONDecoder().decode(ServerInfo.self, from: data)
    }

    func login(username: String, password: String, remember: Bool = true) async throws -> LoginResponse {
        let body: [String: JSONValue] = [
            "username": .string(username),
            "password": .string(password),
            "remember": .bool(remember),
        ]
        let data = try await request("auth/login", method: "POST", body: body)
        let resp = try JSONDecoder().decode(LoginResponse.self, from: data)
        if let t = resp.token { token = t }
        return resp
    }

    func me() async throws -> MeResponse {
        try await get(MeResponse.self, "auth/me")
    }

    func logout() async throws {
        _ = try? await request("auth/logout", method: "POST")
        token = nil
    }

    // MARK: 曲库

    func tracks(page: Int = 1, limit: Int = 100, q: String? = nil,
                sort: String? = nil, artist: String? = nil, album: String? = nil) async throws -> PagedResponse<Track> {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let q, !q.isEmpty { query.append(.init(name: "q", value: q)) }
        if let sort, !sort.isEmpty { query.append(.init(name: "sort", value: sort)) }
        if let artist, !artist.isEmpty { query.append(.init(name: "artist", value: artist)) }
        if let album, !album.isEmpty { query.append(.init(name: "album", value: album)) }
        return try await get(PagedResponse<Track>.self, "library/tracks", query: query)
    }

    func albums(page: Int = 1, limit: Int = 60, q: String? = nil,
                artist: String? = nil) async throws -> PagedResponse<Album> {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let q, !q.isEmpty { query.append(.init(name: "q", value: q)) }
        if let artist, !artist.isEmpty { query.append(.init(name: "artist", value: artist)) }
        return try await get(PagedResponse<Album>.self, "library/albums", query: query)
    }

    func artists(page: Int = 1, limit: Int = 60, q: String? = nil) async throws -> PagedResponse<Artist> {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let q, !q.isEmpty { query.append(.init(name: "q", value: q)) }
        return try await get(PagedResponse<Artist>.self, "library/artists", query: query)
    }

    // MARK: 用户歌单

    func playlists() async throws -> [LemonPlaylist] {
        struct Wrap: Decodable {
            let ok: Bool?
            let data: [LemonPlaylist]?
        }
        let wrap = try await get(Wrap.self, "library/playlists")
        return wrap.data ?? []
    }

    /// 整体覆盖写回（与 Web 端语义一致）
    func savePlaylists(_ playlists: [LemonPlaylist]) async throws {
        struct Wrap: Decodable { let ok: Bool? }
        let body: [String: JSONValue] = ["playlists": .array(playlists.map { .object($0.raw) })]
        let data = try await request("library/playlists", method: "PUT", body: body)
        _ = try? JSONDecoder().decode(Wrap.self, from: data)
    }

    // MARK: 播放

    func playURL(for item: PlayableItem) async throws -> URL {
        var body: [String: JSONValue] = [:]
        if let trackId = item.trackId, !trackId.isEmpty {
            body["trackId"] = .string(trackId)
        }
        if let localPath = item.localPath, !localPath.isEmpty {
            body["localPath"] = .string(localPath)
            body["key"] = .string("local:\(localPath)")
        }
        if let songId = item.songId, !songId.isEmpty {
            body["songId"] = .string(songId)
        }
        if let source = item.source, !source.isEmpty {
            body["source"] = .string(source)
        }
        if let quality = item.quality, !quality.isEmpty {
            body["quality"] = .string(quality)
        }
        let data = try await request("play/url", method: "POST", body: body)
        let resp = try JSONDecoder().decode(PlayURLResponse.self, from: data)
        guard let urlString = resp.url, !urlString.isEmpty else {
            throw LemonAPIError.server("服务端未返回播放地址", 0)
        }
        return absoluteStreamURL(urlString)
    }

    func absoluteStreamURL(_ pathOrURL: String) -> URL {
        if pathOrURL.lowercased().hasPrefix("http") {
            return URL(string: pathOrURL) ?? baseURL
        }
        // 相对路径可能以 "/api/..." 开头（含 /api/play/...），直接拼 host
        if pathOrURL.hasPrefix("/") {
            return URL(string: pathOrURL, relativeTo: baseURL)?.absoluteURL ?? baseURL
        }
        return baseURL.appendingPathComponent(pathOrURL)
    }

    // MARK: 封面

    /// 本地曲目内嵌封面（GET /api/v1/tag/cover?path=...）
    func localCoverURL(_ serverPath: String) -> URL? {
        guard let comps = URLComponents(url: baseURL.appendingPathComponent("api/v1/tag/cover"),
                                        resolvingAgainstBaseURL: false) else { return nil }
        var c = comps
        c.queryItems = [URLQueryItem(name: "path", value: serverPath)]
        return c.url
    }

    /// 远程封面（GET /api/v1/play/cover-img?url=...&w=...）
    func remoteCoverURL(_ remote: String, width: Int = 300) -> URL? {
        guard let comps = URLComponents(url: baseURL.appendingPathComponent("api/v1/play/cover-img"),
                                        resolvingAgainstBaseURL: false) else { return nil }
        var c = comps
        c.queryItems = [
            URLQueryItem(name: "url", value: remote),
            URLQueryItem(name: "w", value: String(width)),
        ]
        return c.url
    }

    /// 带鉴权拉取二进制（封面等）
    func fetchData(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("image/*", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw LemonAPIError.server("资源不可用", http.statusCode)
            }
            return data
        } catch let e as LemonAPIError {
            throw e
        } catch {
            throw LemonAPIError.network(error.localizedDescription)
        }
    }

    // MARK: 歌词

    func lyric(for item: PlayableItem) async throws -> LyricResponse {
        var body: [String: JSONValue] = [
            "name": .string(item.title),
            "singer": .string(item.artist),
        ]
        if let localPath = item.localPath {
            body["localPath"] = .string(localPath)
            body["source"] = .string("local")
        }
        if let songId = item.songId {
            body["songId"] = .string(songId)
            if let source = item.source {
                body["source"] = .string(source)
            }
        }
        let data = try await request("play/lyric", method: "POST", body: body)
        return try JSONDecoder().decode(LyricResponse.self, from: data)
    }
}
