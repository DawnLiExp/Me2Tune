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

    private(set) var isPlaying = false
    private(set) var isSavingTags = false
    private(set) var isPlaybackBlockedForTagSave = false
    @ObservationIgnored private var tagSaveRestartID: UUID?
    private let dataService: DataServiceProtocol
    private let collectionManager: CollectionManager

    var hasPlaybackSession: Bool {
        isPlaying || loadController.hasLoadedTrack || loadController.hasPendingStart || loadController.submitted != nil
    }

    func tagSaveStopsPlayback(for url: URL) -> Bool {
        guard hasPlaybackSession else { return false }
        let target = url.resolvingSymlinksInPath()
        let ids = [playbackStateManager.currentTrackID, playbackOrder.requested?.id].compactMap { $0 }
        return playbackStateManager.currentTracks.contains {
            ids.contains($0.id) && ($0.resolveURL() ?? $0.url).resolvingSymlinksInPath() == target
        }
    }

    @discardableResult
    func beginTagSave(for url: URL) -> Bool {
        guard !isSavingTags else { return false }
        isSavingTags = true
        isPlaybackBlockedForTagSave = tagSaveStopsPlayback(for: url)
        // Copy-and-replace never mutates an open decoder's file. Unrelated playback,
        // including a preloaded successor, can continue using its original file handle.
        guard isPlaybackBlockedForTagSave else { return true }
        tagSaveRestartID = playbackStateManager.currentTrackID
        stopLoading()
        isPlaying = false
        playbackProgressState.currentTime = 0
        timeSampler.updatePlaybackState(isPlaying: false)
        resetOrder()
        updateNowPlayingInfo()
        return true
    }

    func endTagSave() {
        isSavingTags = false
        isPlaybackBlockedForTagSave = false
    }

    func refreshTrackMetadata(id: UUID, snapshot: TagSnapshot) async throws {
        let old = playlistManager.tracks.first { $0.id == id }
            ?? playbackStateManager.currentTracks.first { $0.id == id }
            ?? collectionManager.albums.lazy.flatMap(\.tracks).first { $0.id == id }
        for url in Set([snapshot.url, old?.url].compactMap { $0 }) {
            await FileMetadataReader.shared.invalidate(url: url)
            await artworkProvider.invalidate(url: url)
            await LyricsCacheService.shared.invalidate(url: url)
        }
        let writer = dataService.makeLibraryWriter()
        let record = try writer.trackForUpdate(id: id)
        let existingURL = old?.url ?? record.flatMap { URL(string: $0.urlString) }
        let referenceURL = existingURL.flatMap { $0.resolvingSymlinksInPath() == snapshot.url ? $0 : nil } ?? snapshot.url
        let title = snapshot.text(.title).trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = snapshot.values(.artist).joined(separator: "; ")
        let album = snapshot.values(.album).joined(separator: "; ")
        let bookmark = try referenceURL.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                     includingResourceValuesForKeys: nil, relativeTo: nil)
        let refreshed: AudioTrack?
        if let record {
            record.title = title.isEmpty ? referenceURL.deletingPathExtension().lastPathComponent : title
            record.artist = artist.isEmpty ? nil : artist
            record.albumTitle = album.isEmpty ? nil : album
            record.urlString = referenceURL.absoluteString
            record.bookmark = bookmark
            try writer.save()
            refreshed = record.toAudioTrack()
        } else if let old {
            refreshed = AudioTrack(id: id, url: referenceURL,
                title: title.isEmpty ? referenceURL.deletingPathExtension().lastPathComponent : title,
                artist: artist.isEmpty ? nil : artist, albumTitle: album.isEmpty ? nil : album,
                duration: old.duration, format: old.format, bookmark: bookmark)
        } else { refreshed = nil }
        guard let refreshed else { return }
        playlistManager.refreshTrackMetadata(refreshed)
        collectionManager.refreshTrackMetadata(refreshed)
        playbackStateManager.refreshTrackMetadata(refreshed)
        if playbackStateManager.currentTrackID == id {
            let request = loadController.generation
            let artwork = await artworkProvider.artwork(for: snapshot.url)
            guard loadController.generation == request, playbackStateManager.currentTrackID == id,
                  playbackStateManager.currentTrack?.metadataRevision == refreshed.metadataRevision else { return }
            publishArtwork(artwork, for: refreshed)
            updateNowPlayingInfo()
        }
    }
    private(set) var currentArtwork: NSImage?
    private(set) var duration: TimeInterval = 0

    var repeatMode: RepeatMode = .off {
        didSet {
            playerCore.repeatMode = repeatMode
            if !isPlaybackBlockedForTagSave { loadController.modesChanged() }
        }
    }

    let playbackOrder: PlaybackOrderState
    @ObservationIgnored private let defaults: UserDefaults
    var isShuffling: Bool { playbackOrder.isShuffling }

    func toggleShuffle() {
        guard !isPlaybackBlockedForTagSave else { return }
        loadController.synchronizeOrder()
        playbackOrder.setShuffling(!isShuffling)
        defaults.set(isShuffling, forKey: "shuffleEnabled")
        loadController.modesChanged()
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
        !isPlaybackBlockedForTagSave && playbackOrder.previous(repeatMode: repeatMode, failed: failedTrackRegistry.snapshot()) != nil
    }

    var canGoNext: Bool {
        !isPlaybackBlockedForTagSave && playbackOrder.next(repeatMode: repeatMode, automatic: false,
                           failed: failedTrackRegistry.snapshot()) != nil
    }

    @ObservationIgnored private let playerCore: any AudioPlayerCoreProtocol
    @ObservationIgnored private let failedTrackRegistry: FailedTrackRegistry
    @ObservationIgnored private let persistenceController: PlaybackPersistenceController
    @ObservationIgnored private let effectsController: any PlaybackEffects
    @ObservationIgnored private let artworkProvider: any PlaybackArtworkProviding
    @ObservationIgnored private let statisticsTracker: PlaybackStatisticsTracker
    @ObservationIgnored private var activationArtworkTask: Task<Void, Never>?
    @ObservationIgnored private var presentedArtworkRevision: UUID?
    @ObservationIgnored private lazy var loadController: PlaybackLoadController = PlaybackLoadController(
        playerCore: playerCore, stateManager: playbackStateManager, registry: failedTrackRegistry,
        onTrackPrepared: { [weak self] track in await self?.preparePresentation(for: track) },
        onTrackLoaded: { [weak self] track in self?.commitCurrentTrack(track) },
        repeatModeProvider: { [weak self] in self?.repeatMode ?? .off },
        onPause: { [weak self] in self?.pause() },
        onTrackRequested: { [weak self] track in
            self?.activationArtworkTask?.cancel()
            self?.statisticsTracker.prepareForRequestedTrack(track.id)
        },
        order: playbackOrder
    )
    @ObservationIgnored private var timeSampler: PlaybackTimeSampler!

    @ObservationIgnored private var windowStateMonitor: WindowStateMonitor?
    @ObservationIgnored private lazy var progressTimeProvider: () -> TimeInterval = { [weak self] in
        self?.playerCore.getCurrentPlaybackTime() ?? 0
    }

    private let logger = Logger.coordinator

    init(
        collectionManager: CollectionManager,
        dataService: DataServiceProtocol = DataService.shared,
        statisticsManager: (any StatisticsManagerProtocol)? = nil,
        playerCore: (any AudioPlayerCoreProtocol)? = nil,
        defaults: UserDefaults = .standard,
        playbackOrder: PlaybackOrderState = PlaybackOrderState(),
        effects: any PlaybackEffects = PlaybackEffectsController(),
        artworkProvider: any PlaybackArtworkProviding = ArtworkCacheService.shared
    ) {
        self.playbackOrder = playbackOrder
        self.defaults = defaults
        self.dataService = dataService
        self.collectionManager = collectionManager
        self.playlistManager = PlaylistManager(dataService: dataService)
        self.playbackStateManager = PlaybackStateManager(
            playlistManager: self.playlistManager,
            collectionManager: collectionManager,
            dataService: dataService,
            sessionStore: PlaybackSessionStore(defaults: defaults)
        )

        let playerCore = playerCore ?? AudioPlayerCore()
        self.playerCore = playerCore
        self.failedTrackRegistry = FailedTrackRegistry()
        self.effectsController = effects
        self.artworkProvider = artworkProvider
        self.statisticsTracker = PlaybackStatisticsTracker(statisticsManager: statisticsManager ?? StatisticsManager(dataService: dataService))

        let playbackStateManager = self.playbackStateManager
        let volumeProviderBox = VolumeProviderBox()
        self.persistenceController = PlaybackPersistenceController(
            saveHandler: { [weak playbackStateManager, volumeProviderBox] in
                playbackStateManager?.saveState(volume: volumeProviderBox.provider())
            },
            volumeApplyHandler: { [weak playerCore] volume in
                playerCore?.setVolume(volume)
            }
        )
        volumeProviderBox.provider = { [weak self] in
            self?.volume ?? 0.7
        }
        self.playbackOrder.setShuffling(defaults.bool(forKey: "shuffleEnabled"))
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
        activationArtworkTask?.cancel()
        persistenceController.cancelAllFromDeinit()
    }

    func play() {
        guard !isPlaybackBlockedForTagSave else { return }
        if let id = tagSaveRestartID {
            tagSaveRestartID = nil
            if let track = playbackStateManager.currentTracks.first(where: { $0.id == id }) {
                resetOrder()
                loadController.retryIfFailed(track)
                loadController.start(playbackOrder.select(id))
                return
            }
        }
        loadController.setPlaybackIntent(true)
        // A paused decoder can activate before the explicit load finishes preparing its artwork.
        guard loadController.preparingID == nil else { return }
        if loadController.hasLoadedTrack, !loadController.hasEnded {
            playerCore.play()
            return
        }
        // A second play action only updates intent while the selected track is loading.
        guard !loadController.hasPendingStart else { return }
        if playbackStateManager.currentTrack == nil {
            playbackStateManager.switchToPlaylist()
        }
        let ids = playbackStateManager.currentTracks.map(\.id)
        let previewID = loadController.hasEnded ? nil : playbackStateManager.currentTrack?.id
        // Keep the preview outside the shuffled remainder so a failed load cannot skip other tracks.
        playbackOrder.reset(ids: ids, currentID: previewID, shuffling: isShuffling)
        let failed = failedTrackRegistry.snapshot()
        let first: PlaybackOrderState.Selection?
        // Before the first load, play the track already shown in the player.
        if let previewID, !failed.contains(previewID) {
            first = playbackOrder.select(previewID)
        } else {
            first = playbackOrder.first(failed: failed)
        }
        guard let first else { return }
        loadController.start(first)
    }

    func pause() {
        guard !isPlaybackBlockedForTagSave else { return }
        loadController.setPlaybackIntent(false)
        playerCore.pause()
    }

    var canSeek: Bool {
        !isPlaybackBlockedForTagSave && loadController.hasLoadedTrack
            && !loadController.hasEnded && playerCore.canSeek
    }

    func seek(to time: TimeInterval, trackID: UUID, metadataRevision: UUID) {
        guard canSeek, let track = playbackStateManager.currentTrack,
              track.id == trackID, track.metadataRevision == metadataRevision,
              time.isFinite, time >= 0, duration.isFinite, time < duration else { return }
        seek(to: time)
    }

    func seek(to time: TimeInterval) {
        guard !isPlaybackBlockedForTagSave else { return }
        playerCore.seek(to: time)
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
        guard !isPlaybackBlockedForTagSave else { return }
        tagSaveRestartID = nil
        loadController.synchronizeOrder()
        guard let target = playbackOrder.next(repeatMode: repeatMode, automatic: false,
                                               failed: failedTrackRegistry.snapshot()) else { return }
        loadController.start(target)
    }

    func previous() {
        guard !isPlaybackBlockedForTagSave else { return }
        tagSaveRestartID = nil
        loadController.synchronizeOrder()
        guard let target = playbackOrder.previous(repeatMode: repeatMode,
                                                   failed: failedTrackRegistry.snapshot()) else { return }
        loadController.start(target)
    }

    private func resetOrder() {
        playbackOrder.reset(ids: playbackStateManager.currentTracks.map(\.id),
                            currentID: playbackStateManager.currentTrackID, shuffling: isShuffling)
    }

    func playPlaylistTrack(at index: Int) {
        guard !isPlaybackBlockedForTagSave else { return }
        tagSaveRestartID = nil
        guard let track = playlistManager.track(at: index) else { return }

        playbackStateManager.switchToPlaylist(selecting: index)
        persistenceController.scheduleSave()
        loadController.retryIfFailed(track)
        resetOrder()
        loadController.start(playbackOrder.select(track.id))
    }

    func playAlbum(_ album: Album, startAt index: Int = 0) {
        guard !isPlaybackBlockedForTagSave else { return }
        tagSaveRestartID = nil
        guard !album.tracks.isEmpty else {
            logger.warning("Cannot play empty album: \(album.name)")
            return
        }
        guard album.tracks.indices.contains(index) else { return }

        playbackStateManager.switchToAlbum(album, selecting: index)
        persistenceController.scheduleSave()
        let track = album.tracks[index]
        loadController.retryIfFailed(track)
        resetOrder()
        loadController.start(playbackOrder.select(track.id))
    }

    @discardableResult
    func addTracksToPlaylist(urls: [URL]) async -> AddTracksResult {
        let result = await playlistManager.addTracks(urls: urls)
        if result.newTracksCount > 0 {
            playbackStateManager.handlePlaylistTracksAdded()
            if playbackStateManager.playingSource == .playlist {
                loadController.synchronizeOrder()
                if !isPlaybackBlockedForTagSave { loadController.modesChanged() }
            }
        }
        return result
    }

    func removeTrackFromPlaylist(at index: Int) throws(AppError) {
        guard !isPlaybackBlockedForTagSave else { return }
        guard let removedTrack = playlistManager.track(at: index) else { return }
        let active = playbackStateManager.playingSource == .playlist
        let wasCurrent = active && playbackStateManager.currentTrackID == removedTrack.id
        let wasRequested = active && playbackOrder.requested?.id == removedTrack.id
        let wasSubmitted = active && loadController.submitted?.id == removedTrack.id
        let resumeTime = playerCore.getCurrentPlaybackTime()
        let resumePlayback = isPlaying
        try playlistManager.removeTrack(at: index)
        if wasCurrent || wasRequested || wasSubmitted { stopLoading() }
        failedTrackRegistry.clear(removedTrack.id)
        playbackStateManager.handlePlaylistTrackRemoved(removedTrackID: removedTrack.id, wasPlaying: wasCurrent)
        if active {
            loadController.synchronizeOrder()
            if wasCurrent {
                resetOrder()
                effectsController.clearNowPlayingInfo()
            } else if wasSubmitted || wasRequested, let current = playbackStateManager.currentTrack {
                loadController.start(playbackOrder.select(current.id), autoplay: resumePlayback, resumeTime: resumeTime)
            }
            persistenceController.scheduleSave()
        }
        if playlistManager.isEmpty, active {
            effectsController.disableRemoteCommands()
            effectsController.clearNowPlayingInfo()
        }
    }

    func clearPlaylist() throws(AppError) {
        guard !isPlaybackBlockedForTagSave else { return }
        let isClearingCurrentSource = (playbackStateManager.playingSource == .playlist)

        try playlistManager.clearAll()
        if isClearingCurrentSource {
            stopLoading()
        }

        playbackStateManager.handlePlaylistCleared()
        failedTrackRegistry.pruneStale(keeping: Set(playbackStateManager.currentTracks.map(\.id)))

        if isClearingCurrentSource {
            resetOrder()
            effectsController.disableRemoteCommands()
            effectsController.clearNowPlayingInfo()
            persistenceController.scheduleSave()
        }
    }

    func moveTrackInPlaylist(from source: Int, to destination: Int) throws(AppError) {
        guard !isPlaybackBlockedForTagSave else { return }
        try playlistManager.moveTrack(from: source, to: destination)
        playbackStateManager.handlePlaylistTrackMoved(from: source, to: destination)
        if playbackStateManager.playingSource == .playlist { loadController.synchronizeOrder() }
    }

    func injectWindowStateMonitor(_ monitor: WindowStateMonitor) {
        windowStateMonitor = monitor
        handleWindowStateChanged(monitor.visibilityState)
        setupVisibilityObserver(monitor)
    }

    @discardableResult
    func restoreState() async -> Bool {
        guard !isPlaybackBlockedForTagSave else { return false }
        guard let restored = await playbackStateManager.restoreState() else {
            return false
        }

        guard !isPlaybackBlockedForTagSave else { return false }
        if let savedVolume = restored.volume {
            volume = savedVolume
            playerCore.setVolume(savedVolume)
            let pct = String(format: "%.0f", savedVolume * 100)
            logger.debug("Restored volume: \(pct)%")
        }

        resetOrder()
        activationArtworkTask?.cancel()
        return await loadController.restore(restored.track)
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

    private func stopLoading() {
        activationArtworkTask?.cancel()
        loadController.stop()
    }

    private func commitCurrentTrack(_ track: AudioTrack) {
        if playbackStateManager.currentTrackID != track.id {
            playbackStateManager.setCurrentTrack(id: track.id)
        }
        persistenceController.scheduleSave()
    }

    private func publishArtwork(_ artwork: NSImage?, for track: AudioTrack) {
        currentArtwork = artwork
        presentedArtworkRevision = track.metadataRevision
        effectsController.updateDockIcon(artwork)
    }

    private func preparePresentation(for track: AudioTrack) async {
        let request = loadController.generation
        let artwork = await artworkProvider.artwork(for: track.url)
        guard loadController.generation == request, !isPlaybackBlockedForTagSave,
              let latest = playbackStateManager.currentTracks.first(where: { $0.id == track.id }) else { return }
        if latest.metadataRevision == track.metadataRevision {
            publishArtwork(artwork, for: track)
        }
        duration = latest.duration
        effectsController.ensureRemoteCommandsReady(handlers: makePlaybackCommandHandlers())
        if !loadController.hasPendingStart, playbackStateManager.currentTrackID == track.id {
            updateNowPlayingInfo()
        }
    }

    private func updateActivatedArtwork(for track: AudioTrack) {
        activationArtworkTask?.cancel()
        if presentedArtworkRevision == track.metadataRevision {
            updateNowPlayingInfo()
            return
        }
        guard loadController.preparingID != track.id else { return }
        let request = loadController.generation
        activationArtworkTask = Task { @MainActor [weak self, artworkProvider] in
            let artwork = await artworkProvider.artwork(for: track.url)
            guard !Task.isCancelled, let self, self.loadController.generation == request,
                  self.playbackStateManager.currentTrackID == track.id,
                  self.playbackStateManager.currentTrack?.metadataRevision == track.metadataRevision else { return }
            self.publishArtwork(artwork, for: track)
            self.updateNowPlayingInfo()
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
        guard !isPlaybackBlockedForTagSave || !isPlaying else { return }
        self.isPlaying = isPlaying
        timeSampler.updatePlaybackState(isPlaying: isPlaying)

        effectsController.handlePlaybackStateChanged(
            isPlaying: isPlaying,
            currentTimeProvider: progressTimeProvider
        )
    }

    func playerCoreDidUpdateTime(currentTime: TimeInterval, duration: TimeInterval) {
        guard !isPlaybackBlockedForTagSave else { return }
        playbackProgressState.currentTime = currentTime
        let knownTrackDuration = playbackStateManager.currentTrack?.duration ?? 0
        let resolvedDuration = knownTrackDuration > 0 ? knownTrackDuration : duration
        if resolvedDuration > 0 {
            self.duration = resolvedDuration
        }
    }

    func playerCoreDidEncounterError(_ error: Error) {
        logger.logError(error, context: "PlayerCore")
    }

    func playerCoreNowPlayingChanged(to track: AudioTrack?) {
        guard !isPlaybackBlockedForTagSave else { return }
        guard let reportedTrack = track else {
            logger.debug("Now playing changed to nil")
            return
        }

        // Queued decoders retain the old DTO; use current library metadata on activation.
        guard let track = playbackStateManager.currentTracks.first(where: { $0.id == reportedTrack.id }) else {
            logger.warning("Track not found in current tracks: \(reportedTrack.title)")
            return
        }
        loadController.confirmStarted(track)
        statisticsTracker.didActivateTrack(track.id)
        if playbackStateManager.currentTrackID != track.id {
            commitCurrentTrack(track)
        }
        duration = track.duration
        updateActivatedArtwork(for: track)
    }

    func playerCoreDecodingComplete(for track: AudioTrack) {
        guard !isPlaybackBlockedForTagSave else { return }
        logger.debug("Decoding complete, enqueuing next track")
        loadController.enqueueNextTrack(after: track)
    }

    func playerCoreDidConfirmSeek(to time: TimeInterval) {
        guard !isPlaybackBlockedForTagSave, time.isFinite, time >= 0 else { return }
        playbackProgressState.confirmSeek(at: time)
        effectsController.handleSeek(to: time)
        statisticsTracker.handleSeek(to: time, duration: duration)
    }

    func playerCoreDecodingFailed(for track: AudioTrack, isCurrent: Bool) {
        guard !isPlaybackBlockedForTagSave else { return }
        loadController.handleDecodingFailure(for: track, isCurrent: isCurrent)
    }

    func playerCoreDidReachEnd() {
        guard !isPlaybackBlockedForTagSave else { return }
        loadController.handleEndOfTrack()
    }
}
