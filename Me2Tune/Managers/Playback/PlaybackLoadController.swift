//
//  PlaybackLoadController.swift
//  Me2Tune
//
//  Owns track loading, failure recovery, gapless flow, and playback statistics state.
//  IMPORTANT: repeatModeProvider and onPause must not retain PlaybackCoordinator.
//  IMPORTANT: loadAndPlay(at:attempt:) is the single entry point for programmatic track starts.
//

import Foundation
import OSLog

@MainActor
final class PlaybackLoadController {
    private let playerCore: any AudioPlayerCoreProtocol
    private let stateManager: PlaybackStateManager
    private let registry: FailedTrackRegistry
    private let persistenceController: PlaybackPersistenceController
    private let effectsController: PlaybackEffectsController
    private let repeatModeProvider: @MainActor () -> RepeatMode
    private let onPause: @MainActor () -> Void

    var trackIndexBeforeGapless: Int?

    private var hasMarkedPlayCount = false
    private var currentStatTrackId: UUID?

    private let playCountThreshold: Double = 0.8
    private let maxLoadAttempts = 10
    private let logger = Logger.coordinator

    init(
        playerCore: any AudioPlayerCoreProtocol,
        stateManager: PlaybackStateManager,
        registry: FailedTrackRegistry,
        persistenceController: PlaybackPersistenceController,
        effectsController: PlaybackEffectsController,
        repeatModeProvider: @escaping @MainActor () -> RepeatMode,
        onPause: @escaping @MainActor () -> Void
    ) {
        self.playerCore = playerCore
        self.stateManager = stateManager
        self.registry = registry
        self.persistenceController = persistenceController
        self.effectsController = effectsController
        self.repeatModeProvider = repeatModeProvider
        self.onPause = onPause
    }

    func loadAndPlay(at index: Int, attempt: Int = 0) {
        let tracks = stateManager.currentTracks
        guard tracks.indices.contains(index) else {
            logger.warning("Index out of range: \(index)")
            return
        }

        guard attempt < maxLoadAttempts else {
            logger.error("Max retry attempts reached, stopping playback")
            onPause()
            return
        }

        let track = tracks[index]

        if currentStatTrackId != track.id {
            currentStatTrackId = track.id
            hasMarkedPlayCount = false
        }

        if registry.isMarked(track.id) {
            logger.debug("Skipping known failed track: \(track.title)")
            handleLoadFailure(track: track, index: index, attempt: attempt)
            return
        }

        playerCore.prepareForTrackSwitch()

        Task { @MainActor [weak self] in
            guard let self else { return }

            let success = await self.playerCore.loadTrack(track)
            if !success {
                self.handleLoadFailure(track: track, index: index, attempt: attempt)
                return
            }

            self.stateManager.setCurrentIndex(index)
            self.playerCore.play()
            self.persistenceController.scheduleSave()
        }
    }

    func handleLoadFailure(track: AudioTrack, index: Int, attempt: Int) {
        logger.warning("Track load failed: \(track.title)")
        registry.mark(track.id)

        if repeatModeProvider() == .one {
            logger.info("Single repeat on failed track, stopping")
            onPause()
            return
        }

        let tracks = stateManager.currentTracks
        guard let nextIndex = TrackNavigationPolicy.nextValidIndex(
            after: index,
            tracks: tracks,
            repeatMode: repeatModeProvider(),
            failedIDs: registry.snapshot(),
            maxAttempts: tracks.count
        ) else {
            logger.debug("No next valid track available")
            onPause()
            return
        }

        loadAndPlay(at: nextIndex, attempt: attempt + 1)
    }

    func enqueueNextTrack() {
        guard let currentIndex = stateManager.currentTrackIndex else { return }

        let tracks = stateManager.currentTracks
        guard !tracks.isEmpty else { return }

        guard let nextIndex = TrackNavigationPolicy.nextValidIndex(
            after: currentIndex,
            tracks: tracks,
            repeatMode: repeatModeProvider(),
            failedIDs: registry.snapshot(),
            maxAttempts: tracks.count
        ) else {
            logger.debug("No next track to enqueue")
            return
        }

        let nextTrack = tracks[nextIndex]
        Task { @MainActor [weak self] in
            guard let self else { return }

            let success = await self.playerCore.enqueueTrack(nextTrack)
            if !success {
                self.logger.warning("Enqueue failed, marking track: \(nextTrack.title)")
                self.registry.mark(nextTrack.id)
            }
        }
    }

    func handleEndOfTrack() {
        let baseIndex = trackIndexBeforeGapless
        trackIndexBeforeGapless = nil

        let repeatMode = repeatModeProvider()

        if repeatMode == .one {
            let index = baseIndex ?? stateManager.currentTrackIndex
            guard let index else { return }

            let tracks = stateManager.currentTracks
            guard tracks.indices.contains(index) else { return }

            let track = tracks[index]
            if registry.isMarked(track.id) {
                logger.info("Single repeat on failed track, stopping")
                onPause()
            } else {
                loadAndPlay(at: index)
            }
            return
        }

        if baseIndex == nil {
            logger.warning("trackIndexBeforeGapless missing, falling back to currentTrackIndex")
        }

        guard let effectiveIndex = baseIndex ?? stateManager.currentTrackIndex else { return }

        let tracks = stateManager.currentTracks
        guard !tracks.isEmpty else { return }

        let expectedNext = TrackNavigationPolicy.nextIndex(
            after: effectiveIndex,
            count: tracks.count,
            repeatMode: repeatMode
        )

        if TrackNavigationPolicy.isGaplessAlreadyHandled(
            currentIndex: stateManager.currentTrackIndex,
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

    func retryIfFailed(_ track: AudioTrack) {
        if registry.isMarked(track.id) {
            logger.info("Retry failed track: \(track.title)")
            registry.clear(track.id)
        }
    }

    func handleProgressTick(time: TimeInterval, duration: TimeInterval) {
        hasMarkedPlayCount = effectsController.handlePlaybackTimeUpdated(
            currentTime: time,
            duration: duration,
            playCountThreshold: playCountThreshold,
            hasMarkedPlayCount: hasMarkedPlayCount
        )
    }
}
