//
//  Components.swift
//  LemonMusic
//

import SwiftUI

// MARK: - 曲目行

struct TrackRow: View {
    let track: PlayableItem
    var showCover = true
    var isCurrent = false

    var body: some View {
        HStack(spacing: 12) {
            if showCover {
                CoverArtView(item: track, cornerRadius: 6)
                    .frame(width: 44, height: 44)
            } else {
                Text("")
                    .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if track.duration > 0 {
                Text(formatDuration(track.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 状态视图

struct LoadingRow: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView("加载中…")
            Spacer()
        }
        .padding(.vertical, 24)
    }
}

struct ErrorView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let retry {
                Button("重试", action: retry)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

struct EmptyListView: View {
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - 简单分页加载器

@MainActor
final class PagedLoader<Item>: ObservableObject {
    @Published var items: [Item] = []
    @Published var total = 0
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?

    /// 搜索关键词（reload 前设置）
    var query = ""

    private var page = 0
    private let pageSize: Int
    private let fetch: (Int, Int, String) async throws -> PagedResponse<Item>

    init(pageSize: Int = 100, fetch: @escaping (Int, Int, String) async throws -> PagedResponse<Item>) {
        self.pageSize = pageSize
        self.fetch = fetch
    }

    var canLoadMore: Bool { items.count < total }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let resp = try await fetch(1, pageSize, query)
            items = resp.items
            total = resp.total ?? resp.items.count
            page = 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMore() async {
        guard canLoadMore, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let resp = try await fetch(page + 1, pageSize, query)
            items.append(contentsOf: resp.items)
            if let t = resp.total { total = t }
            page += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
