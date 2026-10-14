//
//  ArtistsView.swift
//  LemonMusic
//

import SwiftUI

struct ArtistsView: View {
    @StateObject private var loader = PagedLoader<Artist>(pageSize: 60) { page, limit, query in
        try await LemonAPI.shared.artists(page: page, limit: limit, q: query)
    }
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if loader.isLoading && loader.items.isEmpty {
                    LoadingRow()
                } else if let error = loader.errorMessage, loader.items.isEmpty {
                    ErrorView(message: error) { Task { await loader.reload() } }
                } else if loader.items.isEmpty {
                    EmptyListView(text: "暂无歌手")
                } else {
                    List {
                        ForEach(loader.items) { artist in
                            NavigationLink {
                                ArtistDetailView(artist: artist)
                            } label: {
                                HStack(spacing: 12) {
                                    CoverArtView(item: coverItem(for: artist),
                                                 cornerRadius: 22,
                                                 systemPlaceholder: "music.mic")
                                        .frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(artist.name)
                                            .lineLimit(1)
                                        Text("\(artist.trackCount ?? 0) 首 · \(artist.albumCount ?? 0) 张专辑")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .task {
                                if artist.id == loader.items.last?.id {
                                    await loader.loadMore()
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("歌手")
            .searchable(text: $searchText, prompt: "搜索歌手")
            .onChange(of: searchText) { newValue in
                loader.query = newValue.trimmingCharacters(in: .whitespaces)
                Task { await loader.reload() }
            }
            .refreshable { await loader.reload() }
        }
        .task {
            if loader.items.isEmpty { await loader.reload() }
        }
    }

    private func coverItem(for artist: Artist) -> PlayableItem? {
        guard let coverPath = artist.coverPath, !coverPath.isEmpty else { return nil }
        return PlayableItem(id: artist.id, title: artist.name, artist: artist.name,
                            album: "", coverLocalPath: coverPath)
    }
}

// MARK: - 歌手详情

struct ArtistDetailView: View {
    let artist: Artist
    @StateObject private var trackLoader: PagedLoader<Track>
    @StateObject private var albumLoader: PagedLoader<Album>
    @StateObject private var player = PlayerManager.shared

    init(artist: Artist) {
        self.artist = artist
        let name = artist.name
        _trackLoader = StateObject(wrappedValue: PagedLoader<Track>(pageSize: 100) { page, limit, _ in
            try await LemonAPI.shared.tracks(page: page, limit: limit, artist: name)
        })
        _albumLoader = StateObject(wrappedValue: PagedLoader<Album>(pageSize: 30) { page, limit, _ in
            try await LemonAPI.shared.albums(page: page, limit: limit, artist: name)
        })
    }

    var body: some View {
        List {
            if !albumLoader.items.isEmpty {
                Section("专辑") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(albumLoader.items) { album in
                                NavigationLink {
                                    AlbumDetailView(album: album)
                                } label: {
                                    AlbumCell(album: album)
                                        .frame(width: 130)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                Button {
                    player.play(trackLoader.items.map { PlayableItem(track: $0) }, startAt: 0)
                } label: {
                    Label("播放全部（\(trackLoader.total)）", systemImage: "play.fill")
                }
            }

            Section("歌曲") {
                if trackLoader.isLoading && trackLoader.items.isEmpty {
                    LoadingRow()
                } else {
                    ForEach(Array(trackLoader.items.enumerated()), id: \.element.id) { index, track in
                        TrackRow(track: PlayableItem(track: track), showCover: false,
                                 isCurrent: player.currentItem?.id == track.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                player.play(trackLoader.items.map { PlayableItem(track: $0) }, startAt: index)
                            }
                            .task {
                                if index == trackLoader.items.count - 5 {
                                    await trackLoader.loadMore()
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if trackLoader.items.isEmpty {
                await trackLoader.reload()
                await albumLoader.reload()
            }
        }
    }
}
