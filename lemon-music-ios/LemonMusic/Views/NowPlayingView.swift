//
//  NowPlayingView.swift
//  LemonMusic
//

import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = PlayerManager.shared

    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0
    @State private var showQueue = false
    @State private var showAddToPlaylist = false
    @State private var showLyrics = false
    @State private var lyricLines: [LyricLine] = []
    @State private var lyricError: String?
    @State private var lyricLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 8)

                if showLyrics {
                    lyricsPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    coverSection
                    Spacer(minLength: 12)
                }

                infoSection
                progressSection
                controlSection
                bottomBar
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddToPlaylist = true
                    } label: {
                        Image(systemName: "text.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showQueue) { QueueSheet() }
            .sheet(isPresented: $showAddToPlaylist) {
                if let item = player.currentItem {
                    AddToPlaylistSheet(items: [item])
                }
            }
        }
        .task(id: player.currentItem?.id) {
            await loadLyrics()
        }
    }

    // MARK: 封面

    private var coverSection: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            CoverArtView(item: player.currentItem, cornerRadius: 16, systemPlaceholder: "music.note")
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
        }
        .frame(maxHeight: 380)
    }

    // MARK: 歌词

    private var lyricsPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    if lyricLoading {
                        ProgressView("加载歌词…")
                            .padding(.top, 60)
                    } else if lyricLines.isEmpty {
                        Text(lyricError ?? "暂无歌词")
                            .foregroundStyle(.secondary)
                            .padding(.top, 60)
                    } else {
                        ForEach(Array(lyricLines.enumerated()), id: \.element.id) { index, line in
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(index == currentLyricIndex ? .title3.bold() : .body)
                                .foregroundStyle(index == currentLyricIndex ? Color.primary : Color.secondary)
                                .multilineTextAlignment(.center)
                                .id(index)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            .onChange(of: currentLyricIndex) { newIndex in
                guard let newIndex else { return }
                withAnimation(.easeInOut) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    private var currentLyricIndex: Int? {
        LyricsParser.currentIndex(in: lyricLines, at: player.currentTime)
    }

    // MARK: 信息

    private var infoSection: some View {
        VStack(spacing: 6) {
            Text(player.currentItem?.title ?? "")
                .font(.title2.bold())
                .lineLimit(1)
            Text(player.currentItem?.artist ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let album = player.currentItem?.album, !album.isEmpty {
                Text(album)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.top, 18)
    }

    // MARK: 进度

    private var progressSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubTime : player.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(player.duration, 1)
            ) { editing in
                if editing {
                    isScrubbing = true
                    scrubTime = player.currentTime
                } else {
                    isScrubbing = false
                    player.seek(to: scrubTime)
                }
            }

            HStack {
                Text(formatDuration(isScrubbing ? scrubTime : player.currentTime))
                Spacer()
                Text(formatDuration(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    // MARK: 控制

    private var controlSection: some View {
        HStack(spacing: 36) {
            Button {
                player.shuffle.toggle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(player.shuffle ? Color.accentColor : Color.secondary)
            }

            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.title)
            }

            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 68))
            }

            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.title)
            }

            Button {
                let modes = PlayerManager.RepeatMode.allCases
                if let idx = modes.firstIndex(of: player.repeatMode) {
                    player.repeatMode = modes[(idx + 1) % modes.count]
                }
            } label: {
                Image(systemName: player.repeatMode.iconName)
                    .font(.title3)
                    .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.accentColor)
            }
        }
        .padding(.top, 10)
    }

    private var bottomBar: some View {
        HStack {
            Button {
                showLyrics.toggle()
            } label: {
                Label(showLyrics ? "封面" : "歌词", systemImage: showLyrics ? "photo" : "text.quote")
                    .font(.subheadline)
            }
            Spacer()
            Text(player.repeatMode.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                showQueue = true
            } label: {
                Label("播放列表", systemImage: "list.bullet")
                    .font(.subheadline)
            }
        }
        .padding(.top, 18)
    }

    // MARK: 歌词加载

    private func loadLyrics() async {
        guard let item = player.currentItem else {
            lyricLines = []
            return
        }
        lyricLoading = true
        lyricError = nil
        defer { lyricLoading = false }
        do {
            let resp = try await LemonAPI.shared.lyric(for: item)
            let text = resp.lyric ?? ""
            let parsed = LyricsParser.parse(text)
            if parsed.isEmpty && !text.isEmpty {
                lyricError = "歌词格式无法解析"
            }
            lyricLines = parsed
        } catch {
            lyricError = "歌词加载失败"
            lyricLines = []
        }
    }
}

// MARK: - 播放队列

struct QueueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = PlayerManager.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, item in
                    TrackRow(track: item, isCurrent: index == player.currentIndex)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            player.jumpTo(index)
                        }
                }
            }
            .listStyle(.plain)
            .navigationTitle("播放列表（\(player.queue.count)）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("清空") {
                        player.clearQueue()
                        dismiss()
                    }
                    .disabled(player.queue.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
