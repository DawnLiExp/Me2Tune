//
//  PlaybackCoordinator.swift
//  Me2Tune
//
//  Coordinates playback flow, state transitions, and audio core delegate events.
//

import AppKit
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class PlaybackCoordinator {
    private(set) var isPlaying = false
    private(set) var currentArtwork: NSImage?
    private(set) var duration: TimeInterval = 0

    var repeatMode: RepeatMode = .off {
        didSet {
            playerCore.repeatMode = repeatMode
        }
    }

    var volume: Double = 0.7 {
        didSet {
            persistenceController.scheduleVolumeApply(volume)
        }
    }

    let playbackProgressState = PlaybackProgressState()
    let playlistManager: PlaylistManager
    let playbackStateManager: PlaybackStateManager

    var canGoPrevious: Bool {
        guard playbackStateManager.currentTrackIndex != nil else { return false }
        if repeatMode == .all { return !playbackStateManager.currentTracks.isEmpty }
        return playbackStateManager.canGoPrevious
    }

    var canGoNext: Bool {
        guard playbackStateManager.currentTrackIndex != nil else { return false }
        if repeatMode == .all { return !playbackStateManager.currentTracks.isEmpty }
        return playbackStateManager.canGoNext
    }

    @ObservationIgnored private let playerCore: any AudioPlayerCoreProtocol
    @ObservationIgnored private let failedTrackRegistry: FailedTrackRegistry
    @ObservationIgnored private let persistenceController: PlaybackPersistenceController
    @ObservationIgnored private let effectsController: PlaybackEffectsController
    @ObservationIgnored private var progressController: PlaybackProgressController!

    @ObservationIgnored private var hasMarkedPlayCount = false
    @ObservationIgnored private var currentStatTrackId: UUID?
    @ObservationIgnored private var trackIndexBeforeGapless: Int?
    @ObservationIgnored private var windowStateMonitor: WindowStateMonitor?
    @ObservationIgnored private lazy var progressTimeProvider: () -> TimeInterval = { [weak self] in
        self?.playerCore.getCurrentPlaybackTime() ?? 0
    }

    private let playCountThreshold: Double = 0.8
    private let logger = Logger.coordinator

    init(
        collectionManager: CollectionManager,
        dataService: DataServiceProtocol = DataService.shared,
        statisticsManager: some StatisticsManagerProtocol = StatisticsManager.shared,
        playerCore: (any AudioPlayerCoreProtocol)? = nil
    ) {
        self.playlistManager = PlaylistManager(dataService: dataService)
        self.playbackStateManager = PlaybackStateManager(
            playlistManager: self.playlistManager,
            collectionManager: collectionManager,
            dataService: dataService
        )

        let playerCore = playerCore ?? AudioPlayerCore()
        self.playerCore = playerCore
        self.failedTrackRegistry = FailedTrackRegistry()
        self.effectsController = PlaybackEffectsController(statisticsManager: statisticsManager)

        let playbackStateManager = self.playbackStateManager
        self.persistenceController = PlaybackPersistenceController(
            saveHandler: { [weak playbackStateManager] volume in
                playbackStateManager?.saveState(volume: volume)
            },
            volumeApplyHandler: { [weak playerCore] volume in
                playerCore?.setVolume(volume)
            }
        )

        playerCore.delegate = self
        self.progressController = PlaybackProgressController(
            timeProvider: { [weak self] in
                self?.playerCore.getCurrentPlaybackTime() ?? 0
            },
            tickHandler: { [weak self] time in
                guard let self else { return }
                self.playbackProgressState.currentTime = time
                self.hasMarkedPlayCount = self.effectsController.handlePlaybackTimeUpdated(
                    currentTime: time,
                    duration: self.duration,
                    playCountThreshold: self.playCountThreshold,
                    hasMarkedPlayCount: self.hasMarkedPlayCount
                )
            }
        )
        logger.debug("PlaybackCoordinator initialized")
    }

    deinit {
        progressController.stopFromDeinit()
        persistenceController.cancelAllFromDeinit()
    }

    func play() {
        if playbackStateManager.currentTrack == nil, !playlistManager.isEmpty {
            playbackStateManager.switchToPlaylist()
            loadAndPlay(at: 0)
            return
        }

        guard playbackStateManager.currentTrack != nil else {
            logger.warning("No track loaded, cannot play")
            return
        }

        playerCore.play()
    }

    func pause() {
        playerCore.pause()
        persistenceController.scheduleSave(volume: volume)
    }

    func seek(to time: TimeInterval) {
        playerCore.seek(to: time)
        effectsController.handleSeek(to: time)

        persistenceController.scheduleSave(volume: volume)
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

    func next() {
        guard let currentIndex = playbackStateManager.currentTrackIndex else { return }
        let tracks = playbackStateManager.currentTracks
        guard !tracks.isEmpty else { return }

        guard let nextIndex = TrackNavigationPolicy.nextValidIndex(
            after: currentIndex,
            tracks: tracks,
            repeatMode: repeatMode,
            failedIDs: failedTrackRegistry.snapshot(),
            maxAttempts: tracks.count
        ) else {
            return
        }

        loadAndPlay(at: nextIndex)
    }

    func previous() {
        guard let currentIndex = playbackStateManager.currentTrackIndex else { return }
        let tracks = playbackStateManager.currentTracks
        guard !tracks.isEmpty else { return }

        guard let targetIndex = TrackNavigationPolicy.previousIndex(
            before: currentIndex,
            count: tracks.count,
            repeatMode: repeatMode
        ) else {
            return
        }

        if let previousIndex = TrackNavigationPolicy.previousValidIndex(
            before: targetIndex + 1,
            tracks: tracks,
            failedIDs: failedTrackRegistry.snapshot()
        ) {
            loadAndPlay(at: previousIndex)
        }
    }

    func playPlaylistTrack(at index: Int) {
        guard playlistManager.tracks.indices.contains(index) else { return }

        playbackStateManager.switchToPlaylist()
        let track = playlistManager.tracks[index]
        retryIfFailed(track)
        loadAndPlay(at: index)
    }

    func playAlbum(_ album: Album, startAt index: Int = 0) {
        guard !album.tracks.isEmpty else {
            logger.warning("Cannot play empty album: \(album.name)")
            return
        }
        guard album.tracks.indices.contains(index) else { return }

        playbackStateManager.switchToAlbum(album)
        let track = album.tracks[index]
        retryIfFailed(track)
        loadAndPlay(at: index)
    }

    func addTracksToPlaylist(urls: [URL]) async {
        await playlistManager.addTracks(urls: urls)
        playbackStateManager.handlePlaylistTracksAdded()
    }

    func removeTrackFromPlaylist(at index: Int) {
        guard playlistManager.tracks.indices.contains(index) else { return }

        let wasPlaying = (playbackStateManager.playingSource == .playlist && playbackStateManager.currentTrackIndex == index)
        let removedTrack = playlistManager.tracks[index]
        failedTrackRegistry.clear(removedTrack.id)

        if wasPlaying {
            pause()
        }

        playlistManager.removeTrack(at: index)
        playbackStateManager.handlePlaylistTrackRemoved(at: index, wasPlaying: wasPlaying)
        persistenceController.scheduleSave(volume: volume)

        if playlistManager.isEmpty, playbackStateManager.playingSource == .playlist {
            effectsController.disableRemoteCommands()
            effectsController.clearNowPlayingInfo()
        }
    }

    func clearPlaylist() {
        if playbackStateManager.playingSource == .playlist {
            pause()
        }

        playlistManager.clearAll()
        playbackStateManager.handlePlaylistCleared()
        failedTrackRegistry.pruneStale(keeping: Set(playbackStateManager.currentTracks.map(\.id)))

        if playbackStateManager.playingSource == .playlist {
            effectsController.disableRemoteCommands()
            effectsController.clearNowPlayingInfo()
        }

        persistenceController.scheduleSave(volume: volume)
    }

    func moveTrackInPlaylist(from source: Int, to destination: Int) {
        playlistManager.moveTrack(from: source, to: destination)
        playbackStateManager.handlePlaylistTrackMoved(from: source, to: destination)
        persistenceController.scheduleSave(volume: volume)
    }

    func injectWindowStateMonitor(_ monitor: WindowStateMonitor) {
        windowStateMonitor = monitor
        handleWindowStateChanged(monitor.visibilityState)
        setupVisibilityObserver(monitor)
    }

    @discardableResult
    func restoreState() async -> Bool {
        guard let restored = await playbackStateManager.restoreState() else {
            return false
        }

        if let savedVolume = restored.volume {
            volume = savedVolume
            playerCore.setVolume(savedVolume)
            let pct = String(format: "%.0f", savedVolume * 100)
            logger.debug("Restored volume: \(pct)%")
        }

        return await loadTrack(restored.track)
    }

    func saveState() {
        playbackStateManager.saveState(volume: volume)
    }

    func isTrackFailed(_ id: UUID) -> Bool {
        failedTrackRegistry.isMarked(id)
    }

    func getCurrentPlaybackTime() -> TimeInterval {
        playerCore.getCurrentPlaybackTime()
    }

    private func makePlaybackCommandHandlers() -> PlaybackCommandHandlers {
        PlaybackCommandHandlers(
            play: { [weak self] in
                self?.play()
            },
            pause: { [weak self] in
                self?.pause()
            },
            togglePlayPause: { [weak self] in
                guard let self else { return }
                if self.isPlaying {
                    self.pause()
                } else {
                    self.play()
                }
            },
            next: { [weak self] in
                self?.next()
            },
            previous: { [weak self] in
                self?.previous()
            },
            seek: { [weak self] time in
                self?.seek(to: time)
            },
            canGoNext: { [weak self] in
                self?.canGoNext ?? false
            },
            canGoPrevious: { [weak self] in
                self?.canGoPrevious ?? false
            },
            isPlaying: { [weak self] in
                self?.isPlaying ?? false
            }
        )
    }

    private func setupVisibilityObserver(_ monitor: WindowStateMonitor) {
        withObservationTracking {
            let state = monitor.visibilityState
            handleWindowStateChanged(state)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.setupVisibilityObserver(monitor)
            }
        }
    }

    private func handleWindowStateChanged(_ state: WindowStateMonitor.WindowVisibilityState) {
        progressController.updateVisibilityState(state)
        logger.debug("Coordinator visibility: \(state.description)")
    }

    private func loadTrack(_ track: AudioTrack) async -> Bool {
        await playerCore.loadTrack(track)
    }

    private func loadAndPlay(at index: Int, attempt: Int = 0) {
        let tracks = playbackStateManager.currentTracks
        guard tracks.indices.contains(index) else {
            logger.warning("Index out of range: \(index)")
            return
        }

        guard attempt < 10 else {
            logger.error("Max retry attempts reached, stopping playback")
            pause()
            return
        }

        let track = tracks[index]

        if currentStatTrackId != track.id {
            currentStatTrackId = track.id
            hasMarkedPlayCount = false
        }

        if failedTrackRegistry.isMarked(track.id) {
            logger.debug("Skipping known failed track: \(track.title)")
            handleLoadFailure(track: track, index: index, attempt: attempt)
            return
        }

        playerCore.prepareForTrackSwitch()

        Task { @MainActor in
            let success = await self.loadTrack(track)
            if !success {
                self.handleLoadFailure(track: track, index: index, attempt: attempt)
                return
            }

            self.playbackStateManager.setCurrentIndex(index)
            self.playerCore.play()
            self.persistenceController.scheduleSave(volume: self.volume)
        }
    }

    private func handleLoadFailure(track: AudioTrack, index: Int, attempt: Int) {
        logger.warning("Track load failed: \(track.title)")
        failedTrackRegistry.mark(track.id)

        if repeatMode == .one {
            logger.info("Single repeat on failed track, stopping")
            pause()
            return
        }

        let tracks = playbackStateManager.currentTracks
        guard let nextIndex = TrackNavigationPolicy.nextValidIndex(
            after: index,
            tracks: tracks,
            repeatMode: repeatMode,
            failedIDs: failedTrackRegistry.snapshot(),
            maxAttempts: tracks.count
        ) else {
            logger.debug("No next valid track available")
            pause()
            return
        }

        loadAndPlay(at: nextIndex, attempt: attempt + 1)
    }

    private func enqueueNextTrack() {
        guard let currentIndex = playbackStateManager.currentTrackIndex else { return }
        let tracks = playbackStateManager.currentTracks
        guard !tracks.isEmpty else { return }

        guard let nextIndex = TrackNavigationPolicy.nextValidIndex(
            after: currentIndex,
            tracks: tracks,
            repeatMode: repeatMode,
            failedIDs: failedTrackRegistry.snapshot(),
            maxAttempts: tracks.count
        ) else {
            logger.debug("No next track to enqueue")
            return
        }

        let nextTrack = tracks[nextIndex]
        Task { @MainActor in
            let success = await self.playerCore.enqueueTrack(nextTrack)
            if !success {
                logger.warning("Enqueue failed, marking track: \(nextTrack.title)")
                self.failedTrackRegistry.mark(nextTrack.id)
            }
        }
    }

    private func retryIfFailed(_ track: AudioTrack) {
        if failedTrackRegistry.isMarked(track.id) {
            logger.info("Retry failed track: \(track.title)")
            failedTrackRegistry.clear(track.id)
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = playbackStateManager.currentTrack else { return }
        effectsController.updateNowPlayingInfo(
            track: track,
            artwork: currentArtwork,
            currentTime: playbackProgressState.currentTime,
            duration: duration,
            isPlaying: isPlaying
        )
    }
}

extension PlaybackCoordinator: AudioPlayerCoreDelegate {
    func playerCoreDidUpdatePlaybackState(_ isPlaying: Bool) {
        self.isPlaying = isPlaying
        progressController.updatePlaybackState(isPlaying: isPlaying)

        effectsController.handlePlaybackStateChanged(
            isPlaying: isPlaying,
            currentTimeProvider: progressTimeProvider
        )

        if isPlaying {
            persistenceController.startPeriodicSave { [weak self] in
                self?.volume ?? 0.7
            }
        } else {
            persistenceController.stopPeriodicSave()
        }
    }

    func playerCoreDidUpdateTime(currentTime: TimeInterval, duration: TimeInterval) {
        playbackProgressState.currentTime = currentTime
        let knownTrackDuration = playbackStateManager.currentTrack?.duration ?? 0
        let resolvedDuration = knownTrackDuration > 0 ? knownTrackDuration : duration
        if resolvedDuration > 0 {
            self.duration = resolvedDuration
        }
    }

    func playerCoreDidLoadTrack(_ track: AudioTrack, artwork: NSImage?) {
        currentArtwork = artwork
        duration = track.duration
        effectsController.ensureRemoteCommandsReady(handlers: makePlaybackCommandHandlers())
    }

    func playerCoreDidEncounterError(_ error: Error) {
        logger.logError(error, context: "PlayerCore")
    }

    func playerCoreNowPlayingChanged(to track: AudioTrack?) {
        guard let track else {
            logger.debug("Now playing changed to nil")
            return
        }

        let tracks = playbackStateManager.currentTracks
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            let indexChanged = (playbackStateManager.currentTrackIndex != index)
            if indexChanged {
                logger.info("Auto switched to track \(index + 1): \(track.title)")
                playbackStateManager.setCurrentIndex(index)
            }

            Task { @MainActor in
                let artwork = await ArtworkCacheService.shared.artwork(for: track.url)

                self.currentArtwork = artwork
                self.duration = track.duration

                self.updateNowPlayingInfo()
                self.playerCore.updateDockIcon(artwork)

                if indexChanged {
                    self.playbackProgressState.currentTime = 0
                    self.persistenceController.scheduleSave(volume: self.volume)
                }
            }
        } else {
            logger.warning("Track not found in current tracks: \(track.title)")
        }
    }

    func playerCoreDecodingComplete(for track: AudioTrack) {
        trackIndexBeforeGapless = playbackStateManager.currentTrackIndex
        logger.debug("Decoding complete, enqueuing next track")
        enqueueNextTrack()
    }

    func playerCoreDidReachEnd() {
        let baseIndex = trackIndexBeforeGapless
        trackIndexBeforeGapless = nil

        if repeatMode == .one {
            let index = baseIndex ?? playbackStateManager.currentTrackIndex
            guard let index else { return }
            let tracks = playbackStateManager.currentTracks
            guard tracks.indices.contains(index) else { return }
            let track = tracks[index]

            if failedTrackRegistry.isMarked(track.id) {
                logger.info("Single repeat on failed track, stopping")
                pause()
            } else {
                loadAndPlay(at: index)
            }
            return
        }

        if baseIndex == nil {
            logger.warning("trackIndexBeforeGapless missing, falling back to currentTrackIndex")
        }

        guard let effectiveIndex = baseIndex ?? playbackStateManager.currentTrackIndex else { return }
        let tracks = playbackStateManager.currentTracks
        guard !tracks.isEmpty else { return }

        let expectedNext = TrackNavigationPolicy.nextIndex(
            after: effectiveIndex,
            count: tracks.count,
            repeatMode: repeatMode
        )

        if TrackNavigationPolicy.isGaplessAlreadyHandled(
            currentIndex: playbackStateManager.currentTrackIndex,
            expectedNext: expectedNext
        ) {
            logger.debug("Gapless transition already handled, skipping manual load")
            return
        }

        guard let nextIndex = expectedNext else {
            logger.debug("Reached end of playlist")
            return
        }

        logger.debug("End of track, loading next (base: \(effectiveIndex) -> next: \(nextIndex))")
        loadAndPlay(at: nextIndex)
    }
}
