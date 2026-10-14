//
//  Models.swift
//  LemonMusic
//
//  服务端 /api/v1 数据模型（对齐 lemon-music 开放 API）
//

import Foundation

// MARK: - 通用 JSON 值（用于歌单透传写回，保留未知字段）

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法解码的 JSON 值")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n):
            if n.truncatingRemainder(dividingBy: 1) == 0 && abs(n) < 1e15 {
                try container.encode(Int64(n))
            } else {
                try container.encode(n)
            }
        case .bool(let b): try container.encode(b)
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        if case .number(let n) = self {
            return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int64(n)) : String(n)
        }
        return nil
    }

    var numberValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    var intValue: Int? { numberValue.map { Int($0) } }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }

    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
}

// MARK: - 用户

struct LemonUser: Codable, Identifiable, Equatable {
    var id: String?
    var username: String?
    var role: String?
    var email: String?
    var nickname: String?

    enum CodingKeys: String, CodingKey {
        case id, username, role, email, nickname
    }

    /// 宽松解码：id 可能是字符串或数字，其余字段类型不符时置 nil
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let n = try? c.decode(Int64.self, forKey: .id) {
            id = String(n)
        } else if let d = try? c.decode(Double.self, forKey: .id) {
            id = String(Int64(d))
        } else {
            id = nil
        }
        username = (try? c.decodeIfPresent(String.self, forKey: .username)) ?? nil
        role = (try? c.decodeIfPresent(String.self, forKey: .role)) ?? nil
        email = (try? c.decodeIfPresent(String.self, forKey: .email)) ?? nil
        nickname = (try? c.decodeIfPresent(String.self, forKey: .nickname)) ?? nil
    }

    var displayName: String {
        if let nickname, !nickname.isEmpty { return nickname }
        return username ?? "未知用户"
    }
}

// MARK: - 曲库曲目（GET /library/tracks）

struct Track: Codable, Identifiable, Hashable {
    var serverId: String?
    var trackId: String?
    var filePath: String?
    var fileName: String?
    var title: String?
    var artist: String?
    var albumArtist: String?
    var album: String?
    var year: String?
    var genre: String?
    var duration: Double?
    var format: String?
    var trackNo: String?
    var hasPicture: Bool?
    var hasLyrics: Bool?
    var mtime: Double?
    var size: Double?

    enum CodingKeys: String, CodingKey {
        case serverId = "id"
        case trackId
        case filePath
        case fileName
        case title
        case artist
        case albumArtist
        case album
        case year
        case genre
        case duration
        case format
        case trackNo = "track"
        case hasPicture
        case hasLyrics
        case mtime
        case size
    }

    var id: String {
        trackId ?? serverId ?? filePath ?? "\(title ?? "")-\(artist ?? "")-\(fileName ?? "")"
    }

    var displayTitle: String {
        if let t = title, !t.isEmpty { return t }
        if let f = fileName, !f.isEmpty {
            return (f as NSString).deletingPathExtension
        }
        return "未知歌曲"
    }

    var displayArtist: String {
        if let a = artist, !a.isEmpty { return a }
        return "未知艺术家"
    }

    var displayAlbum: String {
        if let a = album, !a.isEmpty { return a }
        return "未知专辑"
    }
}

// MARK: - 专辑 / 歌手聚合（GET /library/albums、/library/artists）

struct Album: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var artist: String?
    var trackCount: Int?
    var latestMtime: Double?
    var year: String?
    var genre: String?
    var coverPath: String?

    var displayArtist: String { artist?.isEmpty == false ? artist! : "未知艺术家" }
}

struct Artist: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var trackCount: Int?
    var albumCount: Int?
    var latestMtime: Double?
    var coverPath: String?
}

// MARK: - 分页响应

struct PagedResponse<Item: Codable>: Codable {
    var ok: Bool?
    var data: [Item]?
    var total: Int?
    var page: Int?
    var limit: Int?

    var items: [Item] { data ?? [] }
}

// MARK: - 用户歌单（GET /library/playlists）

/// 歌单对象需原样透传写回（PUT /library/playlists 为整体覆盖），
/// 因此用 JSONValue 保留全部字段，只把常用字段映射成强类型访问器。
struct LemonPlaylist: Codable, Identifiable, Equatable {
    var raw: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        raw = try container.decode([String: JSONValue].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    init(raw: [String: JSONValue]) {
        self.raw = raw
    }

    var id: String {
        raw["id"]?.stringValue ?? raw["name"]?.stringValue ?? UUID().uuidString
    }

    var name: String {
        raw["name"]?.stringValue ?? "未命名歌单"
    }

    var trackKeys: [String] {
        raw["trackKeys"]?.arrayValue?.compactMap { $0.stringValue } ?? []
    }

    var trackSnapshots: [String: JSONValue] {
        raw["trackSnapshots"]?.objectValue ?? [:]
    }

    var coverUrl: String? { raw["coverUrl"]?.stringValue }
    var playlistType: String? { raw["playlistType"]?.stringValue }

    var count: Int {
        if let n = raw["count"]?.intValue { return n }
        return trackKeys.count
    }
}

// MARK: - 播放地址（POST /play/url）

struct PlayURLResponse: Codable {
    var ok: Bool?
    var url: String?
    var local: Bool?
    var smooth: Bool?
    var format: String?
    var quality: String?
    var source: String?
}

// MARK: - 歌词（POST /play/lyric）

struct LyricResponse: Codable {
    var ok: Bool?
    var lyric: String?
    var tlyric: String?
    var rlyric: String?
    var ylyric: String?
}

// MARK: - 登录

struct LoginResponse: Codable {
    var ok: Bool?
    var token: String?
    var expiresAt: Double?
    var remember: Bool?
    var user: LemonUser?
}

struct MeResponse: Codable {
    var user: LemonUser?
    var token: String?
}

// MARK: - 服务器元信息（GET /api/v1）

struct ServerInfo: Codable {
    var ok: Bool?
    var name: String?
    var appVersion: String?
    var apiVersion: Int?
}

// MARK: - 可播放条目（统一本地曲目 / 在线曲目 / 歌单快照）

struct PlayableItem: Identifiable, Hashable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    /// 本地曲目：服务器绝对路径
    var localPath: String?
    var trackId: String?
    /// 在线曲目
    var songId: String?
    var source: String?
    var quality: String?
    /// 封面：本地路径（走 /tag/cover）或远程 URL（走 /play/cover-img）
    var coverLocalPath: String?
    var coverRemoteURL: String?

    static func == (lhs: PlayableItem, rhs: PlayableItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(id: String, title: String, artist: String, album: String, duration: Double = 0,
         localPath: String? = nil, trackId: String? = nil, songId: String? = nil,
         source: String? = nil, quality: String? = nil,
         coverLocalPath: String? = nil, coverRemoteURL: String? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.localPath = localPath
        self.trackId = trackId
        self.songId = songId
        self.source = source
        self.quality = quality
        self.coverLocalPath = coverLocalPath
        self.coverRemoteURL = coverRemoteURL
    }

    init(track: Track) {
        self.init(
            id: track.id,
            title: track.displayTitle,
            artist: track.displayArtist,
            album: track.displayAlbum,
            duration: track.duration ?? 0,
            localPath: track.filePath,
            trackId: track.trackId ?? track.serverId,
            coverLocalPath: (track.hasPicture ?? false) ? track.filePath : nil
        )
    }

    /// 歌单快照条目（trackSnapshots[key]）
    init?(snapshotKey: String, snapshot: JSONValue) {
        guard let obj = snapshot.objectValue else { return nil }
        let title = obj["name"]?.stringValue ?? obj["title"]?.stringValue ?? "未知歌曲"
        let singer = obj["singer"]?.stringValue ?? obj["artist"]?.stringValue ?? "未知艺术家"
        let album = obj["album"]?.stringValue ?? "未知专辑"
        let duration = obj["duration"]?.numberValue ?? 0
        let localPath = obj["localPath"]?.stringValue ?? obj["filePath"]?.stringValue
        let trackId = obj["trackId"]?.stringValue
        let songId = obj["songId"]?.stringValue ?? obj["songmid"]?.stringValue ?? obj["hash"]?.stringValue
        let source = obj["source"]?.stringValue
        let pic = obj["picUrl"]?.stringValue ?? obj["img"]?.stringValue ?? obj["cover"]?.stringValue
        var coverLocal: String?
        var coverRemote: String?
        if let pic, !pic.isEmpty {
            if pic.hasPrefix("http") { coverRemote = pic } else if pic.hasPrefix("/") { coverLocal = pic }
        }
        if coverLocal == nil && coverRemote == nil {
            coverLocal = (obj["hasPicture"]?.boolValue ?? false) ? localPath : nil
        }
        self.init(
            id: snapshotKey,
            title: title,
            artist: singer,
            album: album,
            duration: duration,
            localPath: localPath,
            trackId: trackId,
            songId: songId,
            source: source,
            coverLocalPath: coverLocal,
            coverRemoteURL: coverRemote
        )
    }
}

// MARK: - 工具

func formatDuration(_ seconds: Double) -> String {
    guard seconds > 0, seconds.isFinite else { return "--:--" }
    let total = Int(seconds.rounded())
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
