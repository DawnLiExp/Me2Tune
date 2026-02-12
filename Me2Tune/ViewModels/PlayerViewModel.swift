//
//  PlayerViewModel.swift
//  Me2Tune
//
//  播放器视图模型 - 协调播放控制、播放列表、状态管理
//

import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI

private let logger = Logger.viewModel

@MainActor
@Observable
final class PlayerViewModel {
    // MARK: - Published States (UI 绑定状态)

    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    private(set) var currentArtwork: NSImage?
    private(set) var isPlaylistLoaded = false
    var repeatMode: RepeatMode = .off {
        didSet {
            playerCore.repeatMode = AudioPlayerCore.RepeatMode(from: repeatMode)
        }
    }

    var volume: Double = 0.7 {
        didSet {
            scheduleVolumeUpdate(volume)
        }
    }

    /// 播放列表滚动到的记录 ID，用于在 Tab 切换时保持位置
    var lastScrollTrackId: UUID?
    
    // MARK: - Progress State (独立 @Observable)
    
    @ObservationIgnored let playbackProgressState = PlaybackProgressState()
    
    // MARK: - Managers
    
    let playlistManager: PlaylistManager
    let playbackStateManager: PlaybackStateManager
    
    // MARK: - Types
    
    typealias PlayingSource = PlaybackStateManager.PlayingSource
    
    enum RepeatMode {
        case off
        case all
        case one
    }
    
    // MARK: - Private Properties (不触发UI更新)
    
    @ObservationIgnored private let playerCore: AudioPlayerCore
    @ObservationIgnored private var observerTask: Task<Void, Never>?
    @ObservationIgnored private var stateSaveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?
    @ObservationIgnored private var volumeUpdateTask: Task<Void, Never>?
    
    // MARK: - Statistics Tracking
    
    @ObservationIgnored private var hasMarkedPlayCount = false
    @ObservationIgnored private var currentStatTrackId: UUID?
    
    @ObservationIgnored private var isWindowVisible = true
    @ObservationIgnored private lazy var progressTimeProvider: () -> TimeInterval = { [weak self] in
        self?.playbackProgressState.currentTime ?? 0
    }

    // MARK: - Computed Properties
    
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
        playbackStateManager.canGoPrevious
    }
    
    var canGoNext: Bool {
        playbackStateManager.canGoNext
    }
    
    var isLoadingTracks: Bool {
        playlistManager.isLoading
    }
    
    var loadingTracksCount: Int {
        playlistManager.loadingCount
    }

    // MARK: - Initialization
    
    init(collectionManager: CollectionManager? = nil) {
        self.playlistManager = PlaylistManager()
        self.playbackStateManager = PlaybackStateManager(
            playlistManager: playlistManager,
            collectionManager: collectionManager
        )
        self.playerCore = AudioPlayerCore()
        self.playerCore.delegate = self
        
        RemoteCommandController.shared.setup(viewModel: self)
        
        Task { @MainActor in
            await restorePlaybackState()
        }
        
        setupNotificationObservers()
        
        logger.debug("✅ PlayerViewModel initialized (@Observable)")
    }
    
    deinit {
        stateSaveTask?.cancel()
        observerTask?.cancel()
        pendingSaveTask?.cancel()
        volumeUpdateTask?.cancel()
    }

    // MARK: - Setup
    
    // MARK: - Setup
    
    private func setupNotificationObservers() {
        observerTask?.cancel()
        observerTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .windowVisibilityDidChange) {
                guard let self,
                      let state = notification.object as? WindowStateMonitor.WindowVisibilityState
                else { continue }
                self.playerCore.updateVisibilityState(state)
            }
        }
    }
    
    private func scheduleVolumeUpdate(_ newVolume: Double) {
        volumeUpdateTask?.cancel()
        volumeUpdateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self.playerCore.setVolume(newVolume)
            self.scheduleStateSave()
        }
    }
    
    // MARK: - Playback Control
    
    func play() {
        if currentTrack == nil, !playlistManager.isEmpty {
            playbackStateManager.switchToPlaylist()
            loadAndPlay(at: 0)
            return
        }
        
        guard currentTrack != nil else {
            logger.warning("No track loaded, cannot play")
            return
        }
        
        playerCore.play()
    }
    
    func pause() {
        playerCore.pause()
        scheduleStateSave()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func previous() {
        guard let currentIndex = currentTrackIndex else { return }
        
        if let previousIndex = findPreviousValidTrack(from: currentIndex) {
            loadAndPlay(at: previousIndex)
        } else {
            logger.debug("No valid previous track found")
        }
    }
    
    func next() {
        guard let nextIndex = playbackStateManager.moveToNextIndex() else {
            return
        }
        
        loadAndPlay(at: nextIndex)
    }
    
    func seek(to time: TimeInterval) {
        playerCore.seek(to: time)
        
        NowPlayingService.shared.updatePlaybackTime(currentTime: time)
        NowPlayingService.shared.restartUpdateTimer()
        
        scheduleStateSave()
    }
    
    func toggleRepeatMode() {
        switch repeatMode {
        case .off:
            repeatMode = .all
        case .all:
            repeatMode = .one
        case .one:
            repeatMode = .off
        }
        logger.debug("Repeat mode: \(String(describing: self.repeatMode))")
    }
    
    // MARK: - Real-time Progress Access
    
    func getCurrentPlaybackTime() -> TimeInterval {
        return playerCore.getCurrentPlaybackTime()
    }
    
    // MARK: - Window Visibility

    func updateWindowVisibility(_ state: WindowStateMonitor.WindowVisibilityState) {
        playerCore.updateVisibilityState(state)
        
        isWindowVisible = (state == .activeFocused || state == .inactive)
        
        NowPlayingService.shared.handleWindowVisibilityChange(
            isVisible: state == .activeFocused,
            isPlaying: isPlaying
        )
        
        logger.debug("ViewModel visibility: \(state.description)")
    }
    
    // MARK: - Playlist Operations
    
    func addTracksToPlaylist(urls: [URL]) {
        Task { @MainActor in
            await playlistManager.addTracks(urls: urls)
            
            if !isPlaylistLoaded {
                isPlaylistLoaded = true
            }
            
            playbackStateManager.handlePlaylistTracksAdded()
            
            if currentTrackIndex == nil, let track = currentTrack {
                _ = await loadTrack(track)
            }
        }
    }
    
    func removeTrackFromPlaylist(at index: Int) {
        guard playlistManager.tracks.indices.contains(index) else { return }
        
        let wasPlaying = (playingSource == .playlist && currentTrackIndex == index)
        let removedTrack = playlistManager.tracks[index]
        
        clearFailedMark(for: removedTrack.id)
        
        if wasPlaying {
            pause()
        }
        
        playlistManager.removeTrack(at: index)
        playbackStateManager.handlePlaylistTrackRemoved(at: index, wasPlaying: wasPlaying)
        
        scheduleStateSave()
        
        if playlistManager.isEmpty, playingSource == .playlist {
            RemoteCommandController.shared.disable()
        }
    }
    
    func clearPlaylist() {
        if playingSource == .playlist {
            pause()
        }
        
        clearFailedMarksForPlaylist()
        
        playlistManager.clearAll()
        playbackStateManager.handlePlaylistCleared()
        
        if playingSource == .playlist {
            RemoteCommandController.shared.disable()
        }
        
        scheduleStateSave()
    }
    
    func moveTrackInPlaylist(from source: Int, to destination: Int) {
        playlistManager.moveTrack(from: source, to: destination)
        playbackStateManager.handlePlaylistTrackMoved(from: source, to: destination)
        scheduleStateSave()
    }
    
    func playPlaylistTrack(at index: Int) {
        guard playlistManager.tracks.indices.contains(index) else { return }
        
        playbackStateManager.switchToPlaylist()
        
        let track = playlistManager.tracks[index]
        retryIfFailed(track)
        
        loadAndPlay(at: index)
    }
    
    // MARK: - Album Playback
    
    func playAlbum(_ album: Album, startAt index: Int = 0) {
        guard !album.tracks.isEmpty else {
            logger.warning("Cannot play empty album: \(album.name)")
            return
        }
        
        playbackStateManager.switchToAlbum(album)
        
        let track = album.tracks[index]
        retryIfFailed(track)
        
        loadAndPlay(at: index)
    }
    
    // MARK: - Track Loading
    
    private func loadTrack(_ track: AudioTrack) async -> Bool {
        return await playerCore.loadTrack(track)
    }
    
    private func loadAndPlay(at index: Int, attempt: Int = 0) {
        guard currentTracks.indices.contains(index) else {
            logger.warning("❌ Index out of range: \(index)")
            return
        }
        
        guard attempt < 10 else {
            logger.error("❌ Max retry attempts reached, stopping playback")
            pause()
            return
        }
        
        let track = currentTracks[index]
        
        // ✅ Statistics Marker Reset
        if currentStatTrackId != track.id {
            currentStatTrackId = track.id
            hasMarkedPlayCount = false
        }
        
        // 已标记失败的歌曲直接跳过
        if isTrackFailed(track.id) {
            logger.debug("⏭️ Skipping known failed track: \(track.title)")
            skipToNextTrack(from: index, attempt: attempt)
            return
        }
        
        Task { @MainActor in
            let success = await loadTrack(track)
            
            if !success {
                handleLoadFailure(track: track, index: index, attempt: attempt)
                return
            }
            
            // 加载成功：设置索引并播放
            playbackStateManager.setCurrentIndex(index)
            playerCore.play()
            scheduleStateSave()
        }
    }
    
    /// 处理加载失败
    private func handleLoadFailure(track: AudioTrack, index: Int, attempt: Int) {
        logger.warning("⚠️ Track load failed: \(track.title)")
        markTrackFailed(track.id)
        
        // 单曲循环模式下：停止播放
        if repeatMode == .one {
            logger.info("🛑 Single repeat on failed track, stopping")
            pause()
            return
        }
        
        skipToNextTrack(from: index, attempt: attempt)
    }
    
    /// 跳到下一首（失败后或跳过已失败歌曲时调用）
    private func skipToNextTrack(from index: Int, attempt: Int) {
        if let nextIndex = playbackStateManager.calculateNextIndex(at: index, repeatMode: convertRepeatMode()) {
            logger.info("⏭️ Auto-skipping to next track")
            loadAndPlay(at: nextIndex, attempt: attempt + 1)
        } else {
            logger.debug("No next track available")
            pause()
        }
    }
    
    private func enqueueNextTrack() {
        guard let currentIndex = currentTrackIndex else { return }
        
        let nextIndex = playbackStateManager.calculateNextIndex(at: currentIndex, repeatMode: convertRepeatMode())
        
        guard let nextIndex, currentTracks.indices.contains(nextIndex) else {
            logger.debug("No next track to enqueue")
            return
        }
        
        let nextTrack = currentTracks[nextIndex]
        
        // 不预加载已知失败的歌曲
        if isTrackFailed(nextTrack.id) {
            logger.debug("Skip enqueuing known failed track: \(nextTrack.title)")
            return
        }
        
        Task { @MainActor in
            let success = await playerCore.enqueueTrack(nextTrack)
            
            // 预加载失败：只标记，不跳转
            if !success {
                logger.warning("⚠️ Enqueue failed, marking track: \(nextTrack.title)")
                markTrackFailed(nextTrack.id)
            }
        }
    }
    
    // MARK: - Failed Track Handling
    
    @ObservationIgnored private var failedTrackIDs = Set<UUID>()
    
    /// 检查歌曲是否已标记为失败
    func isTrackFailed(_ trackID: UUID) -> Bool {
        failedTrackIDs.contains(trackID)
    }
    
    /// 标记歌曲为失败
    private func markTrackFailed(_ trackID: UUID) {
        failedTrackIDs.insert(trackID)
    }
    
    /// 清除单个歌曲的失败标记
    private func clearFailedMark(for trackID: UUID) {
        failedTrackIDs.remove(trackID)
    }
    
    /// 清除播放列表所有歌曲的失败标记
    private func clearFailedMarksForPlaylist() {
        let playlistTrackIDs = Set(playlistManager.tracks.map(\.id))
        failedTrackIDs.subtract(playlistTrackIDs)
    }
    
    /// 用户手动点击时：清除失败标记并重试
    private func retryIfFailed(_ track: AudioTrack) {
        if failedTrackIDs.contains(track.id) {
            logger.info("🔄 Retry failed track: \(track.title)")
            failedTrackIDs.remove(track.id)
        }
    }
    
    /// 查找上一首有效歌曲（跳过已失败的）
    private func findPreviousValidTrack(from currentIndex: Int) -> Int? {
        var testIndex = currentIndex - 1
        var attempts = 0
        
        while testIndex >= 0, attempts < currentTracks.count {
            let track = currentTracks[testIndex]
            if !isTrackFailed(track.id) {
                return testIndex
            }
            testIndex -= 1
            attempts += 1
        }
        
        return nil
    }
    
    // MARK: - Private Helpers
    
    private func convertRepeatMode() -> PlaybackStateManager.RepeatMode {
        switch repeatMode {
        case .off: return .off
        case .all: return .all
        case .one: return .one
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else { return }
        
        NowPlayingService.shared.updateNowPlayingInfo(
            track: track,
            artwork: currentArtwork,
            currentTime: playbackProgressState.currentTime,
            duration: duration,
            isPlaying: isPlaying
        )
    }
    
    // MARK: - Persistence
    
    func saveState() {
        playbackStateManager.saveState(volume: volume)
    }
    
    private func scheduleStateSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            saveState()
        }
    }
    
    private func startStateSaveTimer() {
        stopStateSaveTimer()
        
        stateSaveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5), clock: .continuous)
                if Task.isCancelled { break }
                
                guard let self, self.isPlaying else { break }
                self.saveState()
            }
        }
        logger.debug("💾 State save timer started")
    }
    
    private func stopStateSaveTimer() {
        stateSaveTask?.cancel()
        stateSaveTask = nil
    }
 
    private func restorePlaybackState() async {
        guard let restored = await playbackStateManager.restoreState() else {
            isPlaylistLoaded = true
            return
        }
        
        if let savedVolume = restored.volume {
            volume = savedVolume
            playerCore.setVolume(savedVolume)
            logger.debug("🔊 Restored volume: \(String(format: "%.0f", savedVolume * 100))%")
        }
        
        _ = await loadTrack(restored.track)
        isPlaylistLoaded = true
    }
}

// MARK: - AudioPlayerCore Delegate

extension PlayerViewModel: AudioPlayerCoreDelegate {
    func playerCore(_ core: AudioPlayerCore, didUpdatePlaybackState isPlaying: Bool) {
        self.isPlaying = isPlaying
        
        NowPlayingService.shared.updatePlaybackState(isPlaying: isPlaying)
        NowPlayingService.shared.handlePlaybackStateChange(
            isPlaying: isPlaying,
            isWindowVisible: isWindowVisible,
            currentTimeProvider: progressTimeProvider
        )
                
        if isPlaying {
            startStateSaveTimer()
        } else {
            stopStateSaveTimer()
        }
    }
    
    func playerCore(_ core: AudioPlayerCore, didUpdateTime currentTime: TimeInterval, duration: TimeInterval) {
        playbackProgressState.currentTime = currentTime
        
        // Statistics Tracking: 播放进度达到 80% 计入统计
        guard duration > 0 else { return }
        
        // 处理单曲循环：如果进度条回到起点，重置标记
        if hasMarkedPlayCount && currentTime < 1.0 {
            hasMarkedPlayCount = false
        }
        
        if !hasMarkedPlayCount && currentTime >= duration * 0.8 {
            hasMarkedPlayCount = true
            Task { @MainActor in
                StatisticsManager.shared.incrementTodayPlayCount()
            }
        }
    }
    
    func playerCore(_ core: AudioPlayerCore, didLoadTrack track: AudioTrack, artwork: NSImage?) {
        self.currentArtwork = artwork
        self.duration = track.duration
        
        RemoteCommandController.shared.enable()
    }
    
    func playerCore(_ core: AudioPlayerCore, didEncounterError error: Error) {
        logger.logError(error, context: "PlayerCore")
    }
    
    func playerCore(_ core: AudioPlayerCore, nowPlayingChangedTo track: AudioTrack?) {
        guard let track else {
            logger.debug("Now playing changed to nil")
            return
        }
        
        if let index = currentTracks.firstIndex(where: { $0.id == track.id }) {
            let indexChanged = (currentTrackIndex != index)
            
            if indexChanged {
                logger.info("🔄 Auto switched to track \(index + 1): \(track.title)")
                playbackStateManager.setCurrentIndex(index)
            }
            
            Task { @MainActor in
                let artwork = await ArtworkCacheService.shared.artwork(for: track.url)
                
                self.currentArtwork = artwork
                self.duration = track.duration
                
                self.updateNowPlayingInfo()
                self.playerCore.updateDockIcon(artwork)
                
                if indexChanged {
                    self.scheduleStateSave()
                }
            }
        } else {
            logger.warning("Track not found in current tracks: \(track.title)")
        }
    }
    
    func playerCore(_ core: AudioPlayerCore, decodingCompleteFor track: AudioTrack) {
        logger.debug("🔄 Decoding complete, enqueuing next track")
        enqueueNextTrack()
    }
    
    func playerCoreDidReachEnd(_ core: AudioPlayerCore) {
        // 单曲循环：重新播放
        if repeatMode == .one, let index = currentTrackIndex {
            let track = currentTracks[index]
            
            if isTrackFailed(track.id) {
                logger.info("🛑 Single repeat on failed track, stopping")
                pause()
            } else {
                loadAndPlay(at: index)
            }
            return
        }
        
        // 其他模式：尝试播放下一首
        guard let currentIndex = currentTrackIndex else { return }
        
        if let nextIndex = playbackStateManager.calculateNextIndex(at: currentIndex, repeatMode: convertRepeatMode()) {
            logger.debug("🔄 End of track, loading next")
            loadAndPlay(at: nextIndex)
        } else {
            logger.debug("🏁 Reached end of playlist")
        }
    }
}

// MARK: - RepeatMode Conversion

private extension AudioPlayerCore.RepeatMode {
    init(from viewModelMode: PlayerViewModel.RepeatMode) {
        switch viewModelMode {
        case .off:
            self = .off
        case .all:
            self = .all
        case .one:
            self = .one
        }
    }
}
