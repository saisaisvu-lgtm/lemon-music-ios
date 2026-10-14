//
//  OnlineSearchView.swift
//  LemonMusic
//
//  在线搜索 / 试听 / 服务器下载队列（依赖服务端已激活的音源脚本）
//

import SwiftUI

struct OnlineSearchView: View {
    @StateObject private var player = PlayerManager.shared

    @State private var keyword = ""
    @State private var songs: [OnlineSong] = []
    @State private var sources: [SourceOption] = []
    @State private var selectedSource = ""
    @State private var page = 1
    @State private var allPage = 1
    @State private var total = 0
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var didSearch = false
    @State private var toast: String?
    @State private var downloadTarget: OnlineSong?
    @State private var showQueue = false

    var body: some View {
        NavigationStack {
            Group {
                if sources.isEmpty && !isLoading {
                    EmptyListView(text: errorMessage ?? "没有可用的搜索平台\n请先在服务端「设置 → 音源管理」导入并激活音源脚本")
                } else if !didSearch {
                    EmptyListView(text: "输入关键词搜索在线歌曲\n（试听 / 下载依赖服务端音源）")
                } else if isLoading && songs.isEmpty {
                    LoadingRow()
                } else if let error = errorMessage, songs.isEmpty {
                    ErrorView(message: error) { Task { await search(reset: true) } }
                } else {
                    List {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            OnlineSongRow(song: song,
                                          isCurrent: player.currentItem?.id == song.playable().id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    player.play(songs.map { $0.playable() }, startAt: index)
                                }
                                .contextMenu {
                                    Button {
                                        player.play(songs.map { $0.playable() }, startAt: index)
                                    } label: { Label("播放", systemImage: "play.fill") }
                                    Button {
                                        player.playNext(song.playable())
                                        showToast("已加入下一首")
                                    } label: { Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") }
                                    Button {
                                        downloadTarget = song
                                    } label: { Label("下载到服务器", systemImage: "arrow.down.circle") }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button {
                                        downloadTarget = song
                                    } label: {
                                        Label("下载", systemImage: "arrow.down.circle")
                                    }
                                    .tint(.blue)
                                }
                                .task {
                                    if index == songs.count - 5 {
                                        await loadMore()
                                    }
                                }
                        }

                        if isLoadingMore {
                            LoadingRow()
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("在线搜索")
            .searchable(text: $keyword, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "歌名 / 歌手")
            .onSubmit(of: .search) {
                Task { await search(reset: true) }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        ForEach(sources) { src in
                            Button {
                                selectedSource = src.id
                                if didSearch { Task { await search(reset: true) } }
                            } label: {
                                if src.id == selectedSource {
                                    Label(src.name, systemImage: "checkmark")
                                } else {
                                    Text(src.name)
                                }
                            }
                        }
                    } label: {
                        Label(currentSourceName, systemImage: "globe")
                            .font(.subheadline)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showQueue = true
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                }
            }
            .confirmationDialog(
                "选择下载音质",
                isPresented: Binding(
                    get: { downloadTarget != nil },
                    set: { if !$0 { downloadTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                let qualities = downloadTarget?.qualitys ?? []
                if qualities.isEmpty {
                    Button("标准 320k") { Task { await download(downloadTarget, quality: "320k") } }
                } else {
                    ForEach(qualities, id: \.self) { q in
                        Button(qualityLabel(q)) {
                            Task { await download(downloadTarget, quality: q) }
                        }
                    }
                }
                Button("取消", role: .cancel) { downloadTarget = nil }
            }
            .sheet(isPresented: $showQueue) {
                DownloadQueueView()
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                }
            }
        }
        .task {
            await loadSources()
        }
    }

    private var currentSourceName: String {
        sources.first { $0.id == selectedSource }?.name ?? "平台"
    }

    private func qualityLabel(_ q: String) -> String {
        switch q {
        case "master": return "母带"
        case "atmos", "atmos_plus": return "全景声"
        case "hires": return "Hi-Res"
        case "flac24bit": return "FLAC 24bit"
        case "flac": return "FLAC 无损"
        case "320k": return "标准 320k"
        case "128k": return "流畅 128k"
        default: return q
        }
    }

    private func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            toast = nil
        }
    }

    private func loadSources() async {
        do {
            let list = try await LemonAPI.shared.availableSources()
            sources = list
            if selectedSource.isEmpty {
                selectedSource = list.first?.id ?? ""
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func search(reset: Bool) async {
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty, !selectedSource.isEmpty else { return }
        if reset {
            isLoading = true
            didSearch = true
            errorMessage = nil
        }
        defer { isLoading = false }
        do {
            let result = try await LemonAPI.shared.onlineSearch(
                keyword: kw, source: selectedSource, page: 1, limit: 30)
            songs = result.songs
            total = result.total
            allPage = result.allPage
            page = 1
        } catch {
            if reset { errorMessage = error.localizedDescription }
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, page < allPage else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return }
        do {
            let result = try await LemonAPI.shared.onlineSearch(
                keyword: kw, source: selectedSource, page: page + 1, limit: 30)
            let existing = Set(songs.map { $0.id })
            songs.append(contentsOf: result.songs.filter { !existing.contains($0.id) })
            allPage = result.allPage
            page += 1
        } catch { }
    }

    private func download(_ song: OnlineSong?, quality: String) async {
        guard let song else { return }
        downloadTarget = nil
        do {
            let result = try await LemonAPI.shared.addDownloadTasks([song.downloadTask(quality: quality)])
            if result.added > 0 {
                showToast("已加入下载队列（\(qualityLabel(quality))）")
            } else {
                showToast("任务已存在，跳过重复")
            }
        } catch {
            showToast("下载失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - 搜索结果行

struct OnlineSongRow: View {
    let song: OnlineSong
    var isCurrent = false

    var body: some View {
        HStack(spacing: 12) {
            CoverArtView(item: song.playable(), cornerRadius: 6)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(song.displayTitle)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                Text("\(song.displayArtist) · \(song.album.isEmpty ? "未知专辑" : song.album)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !song.qualitys.isEmpty {
                Text(qualityBadge)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }

    private var qualityBadge: String {
        let q = song.qualitys.first ?? ""
        switch q {
        case "master": return "母带"
        case "atmos", "atmos_plus": return "全景声"
        case "hires": return "Hi-Res"
        case "flac24bit", "flac": return "无损"
        default: return "标准"
        }
    }
}

// MARK: - 下载队列

struct DownloadQueueView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [DownloadTaskRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && rows.isEmpty {
                    LoadingRow()
                } else if let error = errorMessage, rows.isEmpty {
                    ErrorView(message: error) { Task { await reload() } }
                } else if rows.isEmpty {
                    EmptyListView(text: "下载队列为空")
                } else {
                    List {
                        ForEach(rows) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.name)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        Text(row.singer.isEmpty ? row.album : row.singer)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(row.statusLabel)
                                        .font(.caption)
                                        .foregroundStyle(row.status == "failed" ? .red
                                                         : row.status == "completed" ? .green : .secondary)
                                }
                                if row.isActive, let p = row.progress {
                                    ProgressView(value: min(max(p, 0), p > 1 ? 100 : 1),
                                                 total: p > 1 ? 100 : 1)
                                        .progressViewStyle(.linear)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("下载队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("清空已完成") {
                        Task {
                            try? await LemonAPI.shared.clearCompletedDownloads()
                            await reload()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            rows = try await LemonAPI.shared.downloadTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
