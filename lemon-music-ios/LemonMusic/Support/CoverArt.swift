//
//  CoverArt.swift
//  LemonMusic
//
//  带鉴权的封面加载（内嵌封面 /api/v1/tag/cover，远程封面 /api/v1/play/cover-img）
//

import Foundation
import SwiftUI
import UIKit

@MainActor
final class CoverStore: ObservableObject {
    static let shared = CoverStore()

    private let cache = NSCache<NSURL, UIImage>()
    private var inflight: [URL: Task<UIImage?, Never>] = [:]

    func image(for item: PlayableItem) async -> UIImage? {
        guard let url = coverURL(for: item) else { return nil }
        return await image(url: url)
    }

    func image(localPath: String?) async -> UIImage? {
        guard let localPath, !localPath.isEmpty,
              let url = LemonAPI.shared.localCoverURL(localPath) else { return nil }
        return await image(url: url)
    }

    func coverURL(for item: PlayableItem) -> URL? {
        if let local = item.coverLocalPath, !local.isEmpty {
            return LemonAPI.shared.localCoverURL(local)
        }
        if let remote = item.coverRemoteURL, !remote.isEmpty {
            return LemonAPI.shared.remoteCoverURL(remote)
        }
        return nil
    }

    func image(url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let task = inflight[url] {
            return await task.value
        }
        let task = Task<UIImage?, Never> { [weak self] in
            do {
                let data = try await LemonAPI.shared.fetchData(url)
                let image = UIImage(data: data)
                if let image {
                    self?.cache.setObject(image, forKey: url as NSURL)
                }
                return image
            } catch {
                return nil
            }
        }
        inflight[url] = task
        let result = await task.value
        inflight[url] = nil
        return result
    }
}

// MARK: - 封面视图

struct CoverArtView: View {
    let item: PlayableItem?
    var localPath: String?
    var cornerRadius: CGFloat = 8
    var systemPlaceholder = "music.note"

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                Image(systemName: systemPlaceholder)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: item?.id ?? localPath ?? "") {
            image = nil
            if let item {
                image = await CoverStore.shared.image(for: item)
            } else if let localPath {
                image = await CoverStore.shared.image(localPath: localPath)
            }
        }
    }
}
