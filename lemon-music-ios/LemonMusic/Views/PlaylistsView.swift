//
//  PlaylistsView.swift
//  LemonMusic
//

import SwiftUI

struct PlaylistsView: View {
    @State private var playlists: [LemonPlaylist] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateAlert = false
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && playlists.isEmpty {
                    LoadingRow()
                } else if let error = errorMessage, playlists.isEmpty {
                    ErrorView(message: error) { Task { await reload() } }
                } else if playlists.isEmpty {
                    EmptyListView(text: "暂无歌单\n点右上角新建歌单")
                } else {
                    List {
                        ForEach(playlists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(playlist: playlist)
                            } label: {
                                HStack(spacing: 12) {
                                    CoverArtView(item: playlistCoverItem(playlist),
                                                 cornerRadius: 8,
                                                 systemPlaceholder: "list.bullet.rectangle")
                                        .frame(width: 48, height: 48)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(playlist.name)
                                            .lineLimit(1)
                                        Text("\(playlist.count) 首")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("歌单")
            .refreshable { await reload() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newPlaylistName = ""
                        showCreateAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("新建歌单", isPresented: $showCreateAlert) {
                TextField("歌单名称", text: $newPlaylistName)
                Button("创建") { Task { await createPlaylist() } }
                Button("取消", role: .cancel) {}
            }
        }
        .task { await reload() }
    }

    private func playlistCoverItem(_ playlist: LemonPlaylist) -> PlayableItem? {
        if let remote = playlist.coverUrl, !remote.isEmpty {
            return PlayableItem(id: playlist.id, title: playlist.name, artist: "", album: "",
                                coverRemoteURL: remote)
        }
        return nil
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            playlists = try await LemonAPI.shared.playlists()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createPlaylist() async {
        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var raw: [String: JSONValue] = [
            "id": .string(UUID().uuidString),
            "name": .string(name),
            "trackKeys": .array([]),
            "trackSnapshots": .object([:]),
            "coverUrl": .string(""),
            "coverMode": .string("auto"),
            "playlistType": .string("custom"),
            "createdAt": .number(Double(Date().timeIntervalSince1970 * 1000)),
            "updatedAt": .number(Double(Date().timeIntervalSince1970 * 1000)),
        ]
        raw["lastSyncedAt"] = .number(0)
        let new = LemonPlaylist(raw: raw)
        do {
            try await LemonAPI.shared.savePlaylists([new] + playlists)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 歌单详情

struct PlaylistDetailView: View {
    let playlist: LemonPlaylist
    @StateObject private var player = PlayerManager.shared

    private var tracks: [PlayableItem] {
        let snapshots = playlist.trackSnapshots
        return playlist.trackKeys.compactMap { key in
            guard let snap = snapshots[key] else { return nil }
            return PlayableItem(snapshotKey: key, snapshot: snap)
        }
    }

    var body: some View {
        let items = tracks
        Group {
            if items.isEmpty {
                EmptyListView(text: "歌单为空")
            } else {
                List {
                    Section {
                        Button {
                            player.play(items, startAt: 0)
                        } label: {
                            Label("播放全部（\(items.count)）", systemImage: "play.fill")
                        }
                    }
                    .listRowBackground(Color.clear)

                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        TrackRow(track: item, isCurrent: player.currentItem?.id == item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                player.play(items, startAt: index)
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 加入歌单

struct AddToPlaylistSheet: View {
    let items: [PlayableItem]
    @Environment(\.dismiss) private var dismiss

    @State private var playlists: [LemonPlaylist] = []
    @State private var isLoading = true
    @State private var message: String?
    @State private var showCreateAlert = false
    @State private var newPlaylistName = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    LoadingRow()
                } else {
                    List {
                        Section {
                            Button {
                                showCreateAlert = true
                            } label: {
                                Label("新建歌单", systemImage: "plus")
                            }
                        }
                        Section("选择歌单") {
                            ForEach(playlists) { playlist in
                                Button {
                                    Task { await add(to: playlist) }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(playlist.name)
                                                .foregroundStyle(.primary)
                                            Text("\(playlist.count) 首")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if message == "已加入「\(playlist.name)」" {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("加入歌单（\(items.count) 首）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("新建歌单", isPresented: $showCreateAlert) {
                TextField("歌单名称", text: $newPlaylistName)
                Button("创建并加入") { Task { await createAndAdd() } }
                Button("取消", role: .cancel) {}
            }
            .overlay {
                if let message {
                    Text(message)
                        .font(.footnote)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 40)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .task {
            do {
                playlists = try await LemonAPI.shared.playlists()
            } catch {
                message = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func snapshot(for item: PlayableItem) -> (key: String, value: JSONValue) {
        let key: String
        if let localPath = item.localPath, !localPath.isEmpty {
            key = "local:\(localPath)"
        } else if let songId = item.songId, !songId.isEmpty {
            key = "\(item.source ?? ""):\(songId)"
        } else {
            key = item.id
        }
        var obj: [String: JSONValue] = [
            "key": .string(key),
            "name": .string(item.title),
            "singer": .string(item.artist),
            "album": .string(item.album),
            "duration": .number(item.duration),
        ]
        if let localPath = item.localPath {
            obj["localPath"] = .string(localPath)
            obj["filePath"] = .string(localPath)
        }
        if let trackId = item.trackId { obj["trackId"] = .string(trackId) }
        if let songId = item.songId { obj["songId"] = .string(songId) }
        if let source = item.source { obj["source"] = .string(source) }
        if let remote = item.coverRemoteURL {
            obj["picUrl"] = .string(remote)
            obj["img"] = .string(remote)
        }
        return (key, .object(obj))
    }

    private func add(to playlist: LemonPlaylist) async {
        do {
            var updated = playlist
            var keys = updated.trackKeys
            var snaps = updated.trackSnapshots
            for item in items {
                let (key, value) = snapshot(for: item)
                if !keys.contains(key) {
                    keys.append(key)
                    snaps[key] = value
                }
            }
            updated.raw["trackKeys"] = .array(keys.map { .string($0) })
            updated.raw["trackSnapshots"] = .object(snaps)
            updated.raw["count"] = .number(Double(keys.count))

            let all = try await LemonAPI.shared.playlists()
            let merged = all.map { $0.id == updated.id ? updated : $0 }
            try await LemonAPI.shared.savePlaylists(merged)
            playlists = merged
            message = "已加入「\(playlist.name)」"
        } catch {
            message = error.localizedDescription
        }
    }

    private func createAndAdd() async {
        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var raw: [String: JSONValue] = [
            "id": .string(UUID().uuidString),
            "name": .string(name),
            "trackKeys": .array([]),
            "trackSnapshots": .object([:]),
            "coverUrl": .string(""),
            "coverMode": .string("auto"),
            "playlistType": .string("custom"),
            "createdAt": .number(Double(Date().timeIntervalSince1970 * 1000)),
            "updatedAt": .number(Double(Date().timeIntervalSince1970 * 1000)),
        ]
        let created = LemonPlaylist(raw: raw)
        do {
            let all = try await LemonAPI.shared.playlists()
            try await LemonAPI.shared.savePlaylists([created] + all)
            playlists = [created] + all
            await add(to: created)
        } catch {
            message = error.localizedDescription
        }
    }
}
