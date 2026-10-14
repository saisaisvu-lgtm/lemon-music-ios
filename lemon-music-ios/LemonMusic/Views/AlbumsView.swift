//
//  AlbumsView.swift
//  LemonMusic
//

import SwiftUI

struct AlbumsView: View {
    @StateObject private var loader = PagedLoader<Album>(pageSize: 60) { page, limit, query in
        try await LemonAPI.shared.albums(page: page, limit: limit, q: query)
    }
    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if loader.isLoading && loader.items.isEmpty {
                    LoadingRow()
                } else if let error = loader.errorMessage, loader.items.isEmpty {
                    ErrorView(message: error) { Task { await loader.reload() } }
                } else if loader.items.isEmpty {
                    EmptyListView(text: "暂无专辑")
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(loader.items) { album in
                                NavigationLink {
                                    AlbumDetailView(album: album)
                                } label: {
                                    AlbumCell(album: album)
                                }
                                .buttonStyle(.plain)
                                .task {
                                    if album.id == loader.items.last?.id {
                                        await loader.loadMore()
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("专辑")
            .searchable(text: $searchText, prompt: "搜索专辑")
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
}

struct AlbumCell: View {
    let album: Album

    private var coverItem: PlayableItem? {
        guard let coverPath = album.coverPath, !coverPath.isEmpty else { return nil }
        return PlayableItem(id: album.id, title: album.name, artist: album.displayArtist,
                            album: album.name, coverLocalPath: coverPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverArtView(item: coverItem, cornerRadius: 10, systemPlaceholder: "square.stack")
                .aspectRatio(1, contentMode: .fit)
            Text(album.name)
                .font(.subheadline)
                .lineLimit(1)
            Text(album.displayArtist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - 专辑详情

struct AlbumDetailView: View {
    let album: Album
    @StateObject private var loader: PagedLoader<Track>
    @StateObject private var player = PlayerManager.shared

    init(album: Album) {
        self.album = album
        let artistName = album.displayArtist
        let albumName = album.name
        _loader = StateObject(wrappedValue: PagedLoader<Track>(pageSize: 100) { page, limit, _ in
            try await LemonAPI.shared.tracks(page: page, limit: limit, artist: artistName, album: albumName)
        })
    }

    var body: some View {
        Group {
            if loader.isLoading && loader.items.isEmpty {
                LoadingRow()
            } else if let error = loader.errorMessage, loader.items.isEmpty {
                ErrorView(message: error) { Task { await loader.reload() } }
            } else {
                List {
                    Section {
                        HStack(spacing: 16) {
                            CoverArtView(item: coverItem, cornerRadius: 10, systemPlaceholder: "square.stack")
                                .frame(width: 110, height: 110)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(album.name)
                                    .font(.title3.bold())
                                    .lineLimit(2)
                                Text(album.displayArtist)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let year = album.year, !year.isEmpty {
                                    Text("\(year) · \(loader.items.count) 首")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section {
                        Button {
                            player.play(loader.items.map { PlayableItem(track: $0) }, startAt: 0)
                        } label: {
                            Label("播放全部", systemImage: "play.fill")
                        }
                    }

                    Section("曲目") {
                        ForEach(Array(loader.items.enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: PlayableItem(track: track), showCover: false,
                                     isCurrent: player.currentItem?.id == track.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    player.play(loader.items.map { PlayableItem(track: $0) }, startAt: index)
                                }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if loader.items.isEmpty { await loader.reload() }
        }
    }

    private var coverItem: PlayableItem? {
        guard let coverPath = album.coverPath, !coverPath.isEmpty else { return nil }
        return PlayableItem(id: album.id, title: album.name, artist: album.displayArtist,
                            album: album.name, coverLocalPath: coverPath)
    }
}
