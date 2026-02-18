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
    // MARK: - Nested Types
    
    @MainActor
    private final class FailedTrackHandler {
        private var failedIDs = Set<UUID>()
        
        func mark(_ id: UUID) {
            failedIDs.insert(id)
        }
        
        func isMarked(_ id: UUID) -> Bool {
            failedIDs.contains(id)
        }
        
        func clear(_ id: UUID) {
            failedIDs.remove(id)
        }
        
        func clearForPlaylist(_ trackIDs: Set<UUID>) {
            failedIDs.subtract(trackIDs)
        }
    }

    // MARK: - Published States

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

    var lastScrollTrackId: UUID? // Scroll anchor for playlist tab
    
    // MARK: - Progress State
    
    @ObservationIgnored let playbackProgressState = PlaybackProgressState()
    
    // MARK: - Managers
    
    let playlistManager: PlaylistManager
    let playbackStateManager: PlaybackStateManager
    private let statisticsManager: StatisticsManagerProtocol
    private let failedTrackHandler = FailedTrackHandler()
    
    // MARK: - Types
    
    typealias PlayingSource = PlaybackStateManager.PlayingSource
    
    enum RepeatMode {
        case off
        case all
        case one
    }
    
    // MARK: - Private Properties
    
    @ObservationIgnored private let playerCore: AudioPlayerCore
    @ObservationIgnored private var observerTask: Task<Void, Never>?
    @ObservationIgnored private var stateSaveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?
    @ObservationIgnored private var volumeUpdateTask: Task<Void, Never>?
    
    // MARK: - Statistics
    
    @ObservationIgnored private var hasMarkedPlayCount = false
    @ObservationIgnored private var currentStatTrackId: UUID?

    /// Snapshot of currentTrackIndex captured at decodingComplete time.
    /// Used to detect whether gapless has already advanced the index before playerCoreDidReachEnd fires.
    @ObservationIgnored private var trackIndexBeforeGapless: Int?
    
    private let playCountThreshold: Double = 0.8 // 80% threshold for play count
    
    @ObservationIgnored private var isWindowVisible = true
    @ObservationIgnored private lazy var progressTimeProvider: () -> TimeInterval = { [weak self] in
        self?.playbackProgressState.currentTime ?? 0
    }

    // MARK: - Window Monitor (DI)
    
    @ObservationIgnored private var windowStateMonitor: WindowStateMonitor?

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
    
    init(
        dataService: DataServiceProtocol = DataService.shared,
        collectionManager: CollectionManager? = nil,
        statisticsManager: StatisticsManagerProtocol = StatisticsManager.shared,
        windowStateMonitor: WindowStateMonitor? = nil
    ) {
        self.playlistManager = PlaylistManager(dataService: dataService)
        self.playbackStateManager = PlaybackStateManager(
            playlistManager: self.playlistManager,
            collectionManager: collectionManager,
            dataService: dataService
        )
        self.statisticsManager = statisticsManager
        self.windowStateMonitor = windowStateMonitor
        self.playerCore = AudioPlayerCore()
        
        self.playerCore.delegate = self
        
        RemoteCommandController.shared.setup(viewModel: self)
        
        Task { @MainActor in
            await restorePlaybackState()
        }
        
        if let monitor = windowStateMonitor {
            setupVisibilityObserver(monitor)
        }
        
        logger.debug("✅ PlayerViewModel initialized (@Observable)")
    }
    
    deinit {
        stateSaveTask?.cancel()
        observerTask?.cancel()
        pendingSaveTask?.cancel()
        volumeUpdateTask?.cancel()
    }

    // MARK: - Setup
    
    /// Public injection point for lazy initialization
    func injectWindowStateMonitor(_ monitor: WindowStateMonitor) {
        self.windowStateMonitor = monitor
        setupVisibilityObserver(monitor)
    }
    
    private func setupVisibilityObserver(_ monitor: WindowStateMonitor) {
        withObservationTracking {
            let state = monitor.visibilityState
            playerCore.updateVisibilityState(state)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.setupVisibilityObserver(monitor)
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
        
        failedTrackHandler.clear(removedTrack.id)
        
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
        
        failedTrackHandler.clearForPlaylist(Set(playlistManager.tracks.map(\.id)))
        
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
        
        // Reset stats marker
        if currentStatTrackId != track.id {
            currentStatTrackId = track.id
            hasMarkedPlayCount = false
        }
        
        // Skip tracks marked as failed
        if failedTrackHandler.isMarked(track.id) {
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
            
            // Load success: set index and play
            playbackStateManager.setCurrentIndex(index)
            playerCore.play()
            scheduleStateSave()
        }
    }
    
    /// Handle load failure
    private func handleLoadFailure(track: AudioTrack, index: Int, attempt: Int) {
        logger.warning("⚠️ Track load failed: \(track.title)")
        failedTrackHandler.mark(track.id)
        
        // Stop if single loop mode
        if repeatMode == .one {
            logger.info("🛑 Single repeat on failed track, stopping")
            pause()
            return
        }
        
        skipToNextTrack(from: index, attempt: attempt)
    }
    
    /// Skip to next track
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
        
        // Do not preload failed tracks
        if failedTrackHandler.isMarked(nextTrack.id) {
            logger.debug("Skip enqueuing known failed track: \(nextTrack.title)")
            return
        }
        
        Task { @MainActor in
            let success = await playerCore.enqueueTrack(nextTrack)
            
            // Preload failed: mark only
            if !success {
                logger.warning("⚠️ Enqueue failed, marking track: \(nextTrack.title)")
                failedTrackHandler.mark(nextTrack.id)
            }
        }
    }
    
    /// Clear failure mark on manual retry
    private func retryIfFailed(_ track: AudioTrack) {
        if failedTrackHandler.isMarked(track.id) {
            logger.info("🔄 Retry failed track: \(track.title)")
            failedTrackHandler.clear(track.id)
        }
    }
    
    /// Find previous valid track
    private func findPreviousValidTrack(from currentIndex: Int) -> Int? {
        var testIndex = currentIndex - 1
        var attempts = 0
        
        while testIndex >= 0, attempts < currentTracks.count {
            let track = currentTracks[testIndex]
            if !failedTrackHandler.isMarked(track.id) {
                return testIndex
            }
            testIndex -= 1
            attempts += 1
        }
        
        return nil
    }
    
    // MARK: - Failed Track Public Access
    
    /// Check if a track is marked as failed
    func isTrackFailed(_ trackID: UUID) -> Bool {
        failedTrackHandler.isMarked(trackID)
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
        
        // Statistics: Mark as played at 80%
        guard duration > 0 else { return }
        
        // Reset play count mark on loop
        if hasMarkedPlayCount, currentTime < 1.0 {
            hasMarkedPlayCount = false
        }
        
        if !hasMarkedPlayCount, currentTime >= duration * playCountThreshold {
            hasMarkedPlayCount = true
            Task { @MainActor in
                await self.statisticsManager.incrementTodayPlayCount()
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
        // Snapshot the index BEFORE gapless transition can advance it.
        // playerCoreDidReachEnd uses this to detect if gapless already moved to the next track.
        trackIndexBeforeGapless = currentTrackIndex
        logger.debug("🔄 Decoding complete, enqueuing next track")
        enqueueNextTrack()
    }
    
    func playerCoreDidReachEnd(_ core: AudioPlayerCore) {
        // Consume the pre-gapless snapshot; nil means decodingComplete didn't fire (rare edge case).
        let baseIndex = trackIndexBeforeGapless
        trackIndexBeforeGapless = nil

        // Single loop: replay same track
        if repeatMode == .one {
            let index = baseIndex ?? currentTrackIndex
            guard let index else { return }
            let track = currentTracks[index]
            
            if failedTrackHandler.isMarked(track.id) {
                logger.info("🛑 Single repeat on failed track, stopping")
                pause()
            } else {
                loadAndPlay(at: index)
            }
            return
        }

        // Use the snapshot index to calculate the true "next" track.
        // If snapshot is nil (decodingComplete never fired), fall back to current index so we don't stall.
        if baseIndex == nil {
            logger.warning("⚠️ trackIndexBeforeGapless missing, falling back to currentTrackIndex")
        }
        let effectiveIndex = baseIndex ?? currentTrackIndex
        guard let effectiveIndex else { return }

        guard let nextIndex = playbackStateManager.calculateNextIndex(at: effectiveIndex, repeatMode: convertRepeatMode()) else {
            logger.debug("🏁 Reached end of playlist")
            return
        }

        // Guard against gapless double-advance:
        // nowPlayingChangedTo may have already updated currentTrackIndex to nextIndex,
        // meaning the gapless transition succeeded — skip loadAndPlay to avoid skipping a track.
        if currentTrackIndex == nextIndex {
            logger.debug("🔄 Gapless transition already handled (index \(nextIndex)), skipping manual load")
            return
        }

        logger.debug("🔄 End of track, loading next (base: \(effectiveIndex) \\➡️ next: \(nextIndex))")
        loadAndPlay(at: nextIndex)
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
