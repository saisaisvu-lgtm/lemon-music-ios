//
//  PlayerManager.swift
//  LemonMusic
//
//  播放内核：AVPlayer 流式播放 + 后台音频 + 锁屏/控制中心遥控
//

import Foundation
import AVFoundation
import MediaPlayer
import Combine

@MainActor
final class PlayerManager: ObservableObject {
    static let shared = PlayerManager()

    @Published var queue: [PlayableItem] = []
    @Published var currentIndex: Int = -1
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off

    enum RepeatMode: Int, CaseIterable {
        case off, all, one
        var iconName: String {
            switch self {
            case .off: return "repeat"
            case .all: return "repeat"
            case .one: return "repeat.1"
            }
        }
        var label: String {
            switch self {
            case .off: return "不循环"
            case .all: return "列表循环"
            case .one: return "单曲循环"
            }
        }
    }

    var currentItem: PlayableItem? {
        guard currentIndex >= 0 && currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var playWhenReady = false

    private init() {
        configureAudioSession()
        setupRemoteCommands()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                if let item = self.player.currentItem {
                    let d = item.duration.seconds
                    if d.isFinite && d > 0 { self.duration = d }
                }
                self.updateNowPlayingElapsed()
            }
        }
    }

    // MARK: 音频会话

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    // MARK: 队列控制

    func play(_ items: [PlayableItem], startAt index: Int = 0) {
        guard !items.isEmpty else { return }
        queue = items
        shuffle = false
        loadAndPlay(index: max(0, min(index, items.count - 1)))
    }

    func appendToQueue(_ items: [PlayableItem]) {
        queue.append(contentsOf: items)
    }

    func playNext(_ item: PlayableItem) {
        let insertAt = currentIndex >= 0 ? currentIndex + 1 : 0
        queue.insert(item, at: min(insertAt, queue.count))
    }

    func jumpTo(_ index: Int) {
        guard index >= 0 && index < queue.count else { return }
        loadAndPlay(index: index)
    }

    func next(manual: Bool = true) {
        guard !queue.isEmpty else { return }
        if repeatMode == .one && !manual {
            seek(to: 0)
            player.play()
            return
        }
        if shuffle {
            let newIndex = queue.count > 1
                ? (0..<queue.count).filter { $0 != currentIndex }.randomElement() ?? 0
                : 0
            loadAndPlay(index: newIndex)
            return
        }
        var nextIndex = currentIndex + 1
        if nextIndex >= queue.count {
            if repeatMode == .all || manual {
                nextIndex = 0
            } else {
                pause()
                return
            }
        }
        loadAndPlay(index: nextIndex)
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        var prevIndex = currentIndex - 1
        if prevIndex < 0 { prevIndex = queue.count - 1 }
        loadAndPlay(index: prevIndex)
    }

    func togglePlay() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func resume() {
        if player.currentItem == nil && currentItem != nil {
            loadAndPlay(index: max(currentIndex, 0), autoplay: true)
            return
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingElapsed()
    }

    func seek(to seconds: Double) {
        let target = max(0, min(seconds, duration > 0 ? duration : seconds))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target
        updateNowPlayingElapsed()
    }

    func clearQueue() {
        pause()
        queue = []
        currentIndex = -1
        currentTime = 0
        duration = 0
        player.replaceCurrentItem(with: nil)
    }

    // MARK: 加载

    private func loadAndPlay(index: Int, autoplay: Bool = true) {
        guard index >= 0 && index < queue.count else { return }
        currentIndex = index
        let item = queue[index]
        isLoading = true
        errorMessage = nil
        currentTime = 0
        duration = item.duration

        Task {
            do {
                let url = try await LemonAPI.shared.playURL(for: item)
                await MainActor.run {
                    self.attach(url: url, item: item, autoplay: autoplay)
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    self.isPlaying = false
                }
            }
        }
    }

    private func attach(url: URL, item: PlayableItem, autoplay: Bool) {
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }

        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        statusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] pi, _ in
            Task { @MainActor in
                guard let self else { return }
                switch pi.status {
                case .readyToPlay:
                    self.isLoading = false
                    let d = pi.duration.seconds
                    if d.isFinite && d > 0 { self.duration = d }
                    self.updateNowPlayingInfo()
                    if autoplay {
                        self.player.play()
                        self.isPlaying = true
                    }
                case .failed:
                    self.isLoading = false
                    self.errorMessage = pi.error?.localizedDescription ?? "播放失败"
                    self.isPlaying = false
                default:
                    break
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.next(manual: false)
            }
        }

        player.replaceCurrentItem(with: playerItem)
        updateNowPlayingInfo()
    }

    // MARK: 锁屏 / 控制中心

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
    }

    private func updateNowPlayingInfo() {
        guard let item = currentItem else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: item.artist,
            MPMediaItemPropertyAlbumTitle: item.album,
            MPMediaItemPropertyPlaybackDuration: duration > 0 ? duration : item.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused

        let baseInfo = info
        Task {
            if let image = await CoverStore.shared.image(for: item) {
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                var info2 = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? baseInfo
                info2[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info2
            }
        }
    }

    private func updateNowPlayingElapsed() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
