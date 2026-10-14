//
//  OnlineModels.swift
//  LemonMusic
//
//  在线搜索 / 下载模型（落雪兼容音源，字段按平台透传保留）
//

import Foundation

// MARK: - 在线歌曲（各平台字段差异大：整体透传 + 强类型访问器）

struct OnlineSong: Identifiable, Equatable {
    var raw: [String: JSONValue]

    static func == (lhs: OnlineSong, rhs: OnlineSong) -> Bool {
        lhs.raw == rhs.raw
    }

    init(raw: [String: JSONValue]) {
        self.raw = raw
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        raw = try container.decode([String: JSONValue].self)
    }

    private func str(_ keys: String...) -> String {
        for k in keys {
            if let s = raw[k]?.stringValue, !s.isEmpty { return s }
        }
        return ""
    }

    var id: String { songKey }

    /// 播放/下载用的平台歌曲 ID（不同平台字段不同）
    var songKey: String {
        str("songId", "id", "songmid", "hash", "musicId", "copyrightId", "rid")
    }

    var name: String { str("name", "title", "SONGNAME") }
    var singer: String { str("singer", "artist", "ARTIST") }
    var album: String { str("album", "albumName", "ALBUM") }
    var source: String { str("source") }
    var img: String { str("img", "picUrl", "cover") }

    /// 时长："03:45" 或秒数字符串
    var duration: Double {
        let s = str("interval", "duration")
        if s.contains(":") {
            let parts = s.split(separator: ":").compactMap { Double($0) }
            if parts.count == 2 { return parts[0] * 60 + parts[1] }
            if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
            return 0
        }
        return Double(s) ?? 0
    }

    /// 可用音质（如 ["flac","320k","128k"]）
    var qualitys: [String] {
        raw["qualitys"]?.arrayValue?.compactMap { $0.stringValue } ?? []
    }

    var displayTitle: String { name.isEmpty ? "未知歌曲" : name }
    var displayArtist: String { singer.isEmpty ? "未知艺术家" : singer }

    func playable() -> PlayableItem {
        PlayableItem(
            id: "\(source):\(songKey)",
            title: displayTitle,
            artist: displayArtist,
            album: album,
            duration: duration,
            songId: songKey,
            source: source.isEmpty ? nil : source,
            quality: qualitys.contains("320k") ? "320k" : qualitys.first,
            coverRemoteURL: img.isEmpty ? nil : img
        )
    }

    /// 生成服务端下载任务（保留全部平台字段，覆盖 quality）
    func downloadTask(quality: String) -> [String: JSONValue] {
        var task = raw
        task["name"] = .string(displayTitle)
        task["singer"] = .string(displayArtist)
        task["album"] = .string(album)
        if !songKey.isEmpty {
            task["songId"] = .string(songKey)
        }
        if source.isEmpty {
            task.removeValue(forKey: "source")
        } else {
            task["source"] = .string(source)
        }
        task["quality"] = .string(quality)
        return task
    }
}

// MARK: - 在线搜索结果

struct OnlineSearchResult {
    var songs: [OnlineSong] = []
    var total = 0
    var allPage = 0
}

// MARK: - 可用平台

struct SourceOption: Identifiable, Hashable {
    var id: String
    var name: String
    var qualitys: [String]
}

// MARK: - 下载队列条目

struct DownloadTaskRow: Identifiable, Equatable {
    var raw: [String: JSONValue]

    static func == (lhs: DownloadTaskRow, rhs: DownloadTaskRow) -> Bool {
        lhs.id == rhs.id
    }

    init(raw: [String: JSONValue]) {
        self.raw = raw
    }

    var id: String {
        raw["id"]?.stringValue ?? UUID().uuidString
    }

    var name: String { raw["name"]?.stringValue ?? "未知歌曲" }
    var singer: String { raw["singer"]?.stringValue ?? "" }
    var album: String { raw["album"]?.stringValue ?? "" }
    var quality: String { raw["quality"]?.stringValue ?? "" }
    var status: String { raw["status"]?.stringValue ?? "waiting" }

    var progress: Double? {
        if let n = raw["progress"]?.numberValue { return n }
        if let s = raw["progress"]?.stringValue { return Double(s) }
        return nil
    }

    var statusLabel: String {
        switch status {
        case "waiting": return "排队中"
        case "downloading": return "下载中"
        case "completed", "done", "success": return "已完成"
        case "failed", "error": return "失败"
        case "paused": return "已暂停"
        case "skipped": return "已跳过"
        default: return status
        }
    }

    var isActive: Bool { status == "waiting" || status == "downloading" }
}
