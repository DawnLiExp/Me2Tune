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
    @MainActor
    private final class VolumeProviderBox {
        var provider: @MainActor () -> Double = { 0.7 }
    }

    @MainActor
    private final class RepeatModeProviderBox {
        var provider: @MainActor () -> RepeatMode = { .off }
    }

    @MainActor
    private final class PauseHandlerBox {
        var handler: @MainActor () -> Void = {}
    }

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

    /// 同步探测是否存在已保存的会话快照（转发 sessionStore）
    var hasSessionSnapshot: Bool {
        playbackStateManager.hasSessionSnapshot
    }

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
    @ObservationIgnored private let statisticsTracker: PlaybackStatisticsTracker
    @ObservationIgnored private let loadController: PlaybackLoadController
    @ObservationIgnored private var timeSampler: PlaybackTimeSampler!

    @ObservationIgnored private var windowStateMonitor: WindowStateMonitor?
    @ObservationIgnored private lazy var progressTimeProvider: () -> TimeInterval = { [weak self] in
        self?.playerCore.getCurrentPlaybackTime() ?? 0
    }

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
        self.effectsController = PlaybackEffectsController()
        self.statisticsTracker = PlaybackStatisticsTracker(statisticsManager: statisticsManager)
        let statisticsTracker = self.statisticsTracker

        let playbackStateManager = self.playbackStateManager
        let volumeProviderBox = VolumeProviderBox()
        let repeatModeProviderBox = RepeatModeProviderBox()
        let pauseHandlerBox = PauseHandlerBox()
        self.persistenceController = PlaybackPersistenceController(
            saveHandler: { [weak playbackStateManager, volumeProviderBox] in
                playbackStateManager?.saveState(volume: volumeProviderBox.provider())
            },
            volumeApplyHandler: { [weak playerCore] volume in
                playerCore?.setVolume(volume)
            }
        )
        self.loadController = PlaybackLoadController(
            playerCore: playerCore,
            stateManager: self.playbackStateManager,
            registry: self.failedTrackRegistry,
            persistenceController: self.persistenceController,
            repeatModeProvider: { [repeatModeProviderBox] in
                repeatModeProviderBox.provider()
            },
            onPause: { [pauseHandlerBox] in
                pauseHandlerBox.handler()
            },
            onTrackRequested: { track in
                statisticsTracker.prepareForRequestedTrack(track.id)
            }
        )
        volumeProviderBox.provider = { [weak self] in
            self?.volume ?? 0.7
        }
        repeatModeProviderBox.provider = { [weak self] in
            self?.repeatMode ?? .off
        }
        pauseHandlerBox.handler = { [weak self] in
            self?.pause()
        }

        playerCore.delegate = self
        self.timeSampler = PlaybackTimeSampler(
            timeProvider: { [weak self] in
                self?.playerCore.getCurrentPlaybackTime() ?? 0
            },
            uiHandler: { [weak self] time in
                guard let self else { return }
                self.playbackProgressState.currentTime = time
            },
            statisticsHandler: { [weak self] time in
                guard let self else { return }
                self.statisticsTracker.evaluate(currentTime: time, duration: self.duration)
            }
        )
        logger.debug("PlaybackCoordinator initialized")
    }

    deinit {
        timeSampler.stopFromDeinit()
        persistenceController.cancelAllFromDeinit()
    }

    func play() {
        if playbackStateManager.currentTrack == nil, !playlistManager.isEmpty {
            playbackStateManager.switchToPlaylist(selecting: 0)
            loadController.loadAndPlay(at: 0)
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
    }

    func seek(to time: TimeInterval) {
        playerCore.seek(to: time)
        effectsController.handleSeek(to: time)
        statisticsTracker.handleSeek(to: time, duration: duration)
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

        loadController.loadAndPlay(at: nextIndex)
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
            loadController.loadAndPlay(at: previousIndex)
        }
    }

    func playPlaylistTrack(at index: Int) {
        guard playlistManager.tracks.indices.contains(index) else { return }

        playbackStateManager.switchToPlaylist(selecting: index)
        persistenceController.scheduleSave()
        let track = playlistManager.tracks[index]
        loadController.retryIfFailed(track)
        loadController.loadAndPlay(at: index)
    }

    func playAlbum(_ album: Album, startAt index: Int = 0) {
        guard !album.tracks.isEmpty else {
            logger.warning("Cannot play empty album: \(album.name)")
            return
        }
        guard album.tracks.indices.contains(index) else { return }

        playbackStateManager.switchToAlbum(album, selecting: index)
        persistenceController.scheduleSave()
        let track = album.tracks[index]
        loadController.retryIfFailed(track)
        loadController.loadAndPlay(at: index)
    }

    @discardableResult
    func addTracksToPlaylist(urls: [URL]) async -> AddTracksResult {
        let result = await playlistManager.addTracks(urls: urls)
        if result.newTracksCount > 0 {
            playbackStateManager.handlePlaylistTracksAdded()
        }
        return result
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
        playbackStateManager.handlePlaylistTrackRemoved(removedTrackID: removedTrack.id, wasPlaying: wasPlaying)
        if wasPlaying {
            persistenceController.scheduleSave()
        }

        if playlistManager.isEmpty, playbackStateManager.playingSource == .playlist {
            effectsController.disableRemoteCommands()
            effectsController.clearNowPlayingInfo()
        }
    }

    func clearPlaylist() {
        let isClearingCurrentSource = (playbackStateManager.playingSource == .playlist)

        if isClearingCurrentSource {
            pause()
        }

        playlistManager.clearAll()
        playbackStateManager.handlePlaylistCleared()
        failedTrackRegistry.pruneStale(keeping: Set(playbackStateManager.currentTracks.map(\.id)))

        if isClearingCurrentSource {
            effectsController.disableRemoteCommands()
            effectsController.clearNowPlayingInfo()
            persistenceController.scheduleSave()
        }
    }

    func moveTrackInPlaylist(from source: Int, to destination: Int) {
        playlistManager.moveTrack(from: source, to: destination)
        playbackStateManager.handlePlaylistTrackMoved(from: source, to: destination)
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
        timeSampler.updateVisibilityState(state)
        logger.debug("Coordinator visibility: \(state.description)")
    }

    private func loadTrack(_ track: AudioTrack) async -> Bool {
        await playerCore.loadTrack(track)
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
        timeSampler.updatePlaybackState(isPlaying: isPlaying)

        effectsController.handlePlaybackStateChanged(
            isPlaying: isPlaying,
            currentTimeProvider: progressTimeProvider
        )
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

        statisticsTracker.synchronizeObservedTrack(track.id)
        let tracks = playbackStateManager.currentTracks
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            let idChanged = (playbackStateManager.currentTrackID != track.id)
            if idChanged {
                logger.info("Auto switched to track \(index + 1): \(track.title)")
                playbackStateManager.setCurrentTrack(id: track.id)
            }

            Task { @MainActor in
                let artwork = await ArtworkCacheService.shared.artwork(for: track.url)

                self.currentArtwork = artwork
                self.duration = track.duration

                self.updateNowPlayingInfo()
                self.playerCore.updateDockIcon(artwork)

                if idChanged {
                    self.playbackProgressState.currentTime = 0
                    self.persistenceController.scheduleSave()
                }
            }
        } else {
            logger.warning("Track not found in current tracks: \(track.title)")
        }
    }

    func playerCoreDecodingComplete(for track: AudioTrack) {
        loadController.trackIndexBeforeGapless = playbackStateManager.currentTrackIndex
        logger.debug("Decoding complete, enqueuing next track")
        loadController.enqueueNextTrack()
    }

    func playerCoreDidReachEnd() {
        loadController.handleEndOfTrack()
    }
}
