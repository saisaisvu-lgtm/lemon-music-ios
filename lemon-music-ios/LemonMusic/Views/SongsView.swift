//
//  SongsView.swift
//  LemonMusic
//

import SwiftUI

struct SongsView: View {
    @StateObject private var loader = PagedLoader<Track>(pageSize: 100) { page, limit, query in
        try await LemonAPI.shared.tracks(page: page, limit: limit, q: query)
    }
    @StateObject private var player = PlayerManager.shared
    @State private var searchText = ""
    @State private var currentQuery = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if loader.isLoading && loader.items.isEmpty {
                    LoadingRow()
                } else if let error = loader.errorMessage, loader.items.isEmpty {
                    ErrorView(message: error) {
                        Task { await loader.reload() }
                    }
                } else if loader.items.isEmpty {
                    EmptyListView(text: currentQuery.isEmpty ? "曲库为空\n请在服务器端扫描音乐目录" : "没有匹配「\(currentQuery)」的歌曲")
                } else {
                    List {
                        Section {
                            Button {
                                player.play(loader.items.map { PlayableItem(track: $0) }, startAt: 0)
                            } label: {
                                Label("播放全部（\(loader.total)）", systemImage: "play.fill")
                            }
                        }
                        .listRowBackground(Color.clear)

                        ForEach(Array(loader.items.enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: PlayableItem(track: track),
                                     isCurrent: player.currentItem?.id == track.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    player.play(loader.items.map { PlayableItem(track: $0) }, startAt: index)
                                }
                                .task {
                                    if index == loader.items.count - 5 {
                                        await loader.loadMore()
                                    }
                                }
                        }

                        if loader.isLoadingMore {
                            LoadingRow()
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("歌曲")
            .searchable(text: $searchText, prompt: "搜索歌曲 / 歌手 / 专辑")
            .onChange(of: searchText) { newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if Task.isCancelled { return }
                    currentQuery = newValue.trimmingCharacters(in: .whitespaces)
                    loader.query = currentQuery
                    await loader.reload()
                }
            }
            .refreshable { await loader.reload() }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await loader.reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .task {
            if loader.items.isEmpty { await loader.reload() }
        }
    }
}
