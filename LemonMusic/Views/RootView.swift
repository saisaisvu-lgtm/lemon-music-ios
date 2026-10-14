//
//  RootView.swift
//  LemonMusic
//

import SwiftUI

struct RootView: View {
    @StateObject private var session = SessionStore.shared
    @StateObject private var player = PlayerManager.shared
    @State private var showNowPlaying = false

    var body: some View {
        Group {
            if session.loggedIn {
                mainUI
            } else {
                LoginView()
            }
        }
        .task {
            await session.restore()
        }
        .animation(.default, value: session.loggedIn)
    }

    private var mainUI: some View {
        ZStack(alignment: .bottom) {
            TabView {
                SongsView()
                    .tabItem { Label("歌曲", systemImage: "music.note.list") }
                AlbumsView()
                    .tabItem { Label("专辑", systemImage: "square.stack") }
                ArtistsView()
                    .tabItem { Label("歌手", systemImage: "music.mic") }
                PlaylistsView()
                    .tabItem { Label("歌单", systemImage: "list.bullet.rectangle") }
                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape") }
            }

            if player.currentItem != nil {
                MiniPlayerView(showNowPlaying: $showNowPlaying)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 49) // TabBar 高度近似值
            }
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
    }
}

// MARK: - 迷你播放条

struct MiniPlayerView: View {
    @Binding var showNowPlaying: Bool
    @StateObject private var player = PlayerManager.shared

    var body: some View {
        HStack(spacing: 12) {
            CoverArtView(item: player.currentItem, cornerRadius: 6)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentItem?.title ?? "")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(player.currentItem?.artist ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                player.togglePlay()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { showNowPlaying = true }
    }
}
