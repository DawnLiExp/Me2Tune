//
//  PlayerViewModel.swift
//  Me2Tune
//
//  播放器视图模型 - 薄壳转发到 PlaybackCoordinator
//

import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class PlayerViewModel {
    private let coordinator: PlaybackCoordinator

    private(set) var isPlaylistLoaded = false

    // ⚠️ 双向绑定：ScrollView 会将顶部可见 item 的 ID 写回此字段。
    // 移动歌曲后如不清除，SwiftUI 会自动滚回锚点曲目，导致新第 1 首不可见。
    var lastScrollTrackId: UUID?

    @ObservationIgnored
    let playbackProgressState: PlaybackProgressState

    let playlistManager: PlaylistManager
    let playbackStateManager: PlaybackStateManager

    typealias PlayingSource = PlaybackStateManager.PlayingSource
    typealias RepeatMode = Me2Tune.RepeatMode

    var isPlaying: Bool {
        coordinator.isPlaying
    }

    var duration: TimeInterval {
        coordinator.duration
    }

    var currentArtwork: NSImage? {
        coordinator.currentArtwork
    }

    var repeatMode: RepeatMode {
        get { coordinator.repeatMode }
        set { coordinator.repeatMode = newValue }
    }

    var volume: Double {
        get { coordinator.volume }
        set { coordinator.volume = newValue }
    }

    var currentFormat: AudioFormat {
        currentTrack?.format ?? .unknown
    }

    var currentTrack: AudioTrack? {
        playbackStateManager.currentTrack
    }

    var currentTrackIndex: Int? {
        playbackStateManager.currentTrackIndex
    }

    var currentTracks: [AudioTrack] {
        playbackStateManager.currentTracks
    }

    var playingSource: PlaybackStateManager.PlayingSource {
        playbackStateManager.playingSource
    }

    var canGoPrevious: Bool {
        coordinator.canGoPrevious
    }

    var canGoNext: Bool {
        coordinator.canGoNext
    }

    var isLoadingTracks: Bool {
        playlistManager.isLoading
    }

    var loadingTracksCount: Int {
        playlistManager.loadingCount
    }

    init(
        coordinator: PlaybackCoordinator,
        windowStateMonitor: WindowStateMonitor? = nil
    ) {
        self.coordinator = coordinator
        self.playbackProgressState = coordinator.playbackProgressState
        self.playlistManager = coordinator.playlistManager
        self.playbackStateManager = coordinator.playbackStateManager

        if let monitor = windowStateMonitor {
            injectWindowStateMonitor(monitor)
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.coordinator.restoreState()
            self.isPlaylistLoaded = true
        }
    }

    func injectWindowStateMonitor(_ monitor: WindowStateMonitor) {
        coordinator.injectWindowStateMonitor(monitor)
    }

    func play() {
        coordinator.play()
    }

    func pause() {
        coordinator.pause()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func previous() {
        coordinator.previous()
    }

    func next() {
        coordinator.next()
    }

    func seek(to time: TimeInterval) {
        coordinator.seek(to: time)
    }

    func toggleRepeatMode() {
        coordinator.toggleRepeatMode()
    }

    func updateWindowVisibility(_ state: WindowStateMonitor.WindowVisibilityState) {
        coordinator.updateWindowVisibility(state)
    }

    func addTracksToPlaylist(urls: [URL]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.coordinator.addTracksToPlaylist(urls: urls)
            if !self.isPlaylistLoaded {
                self.isPlaylistLoaded = true
            }
        }
    }

    func removeTrackFromPlaylist(at index: Int) {
        coordinator.removeTrackFromPlaylist(at: index)
    }

    func clearPlaylist() {
        coordinator.clearPlaylist()
    }

    func moveTrackInPlaylist(from source: Int, to destination: Int) {
        coordinator.moveTrackInPlaylist(from: source, to: destination)
    }

    func playPlaylistTrack(at index: Int) {
        coordinator.playPlaylistTrack(at: index)
    }

    func playAlbum(_ album: Album, startAt index: Int = 0) {
        coordinator.playAlbum(album, startAt: index)
    }

    func isTrackFailed(_ trackID: UUID) -> Bool {
        coordinator.isTrackFailed(trackID)
    }

    func getCurrentPlaybackTime() -> TimeInterval {
        coordinator.getCurrentPlaybackTime()
    }

    func saveState() {
        coordinator.saveState()
    }
}
