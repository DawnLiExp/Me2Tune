//
//  PlaybackLoadController.swift
//  Me2Tune
//
//  Owns track loading, failure recovery, and gapless flow.
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
    private let repeatModeProvider: @MainActor () -> RepeatMode
    private let onPause: @MainActor () -> Void
    private let onTrackRequested: @MainActor (AudioTrack) -> Void

    var trackIndexBeforeGapless: Int?
    private(set) var generation = UUID()
    private var enqueueRequest: UUID?
    private var endWhileEnqueuing = false

    private let maxLoadAttempts = 10
    private let logger = Logger.coordinator

    init(
        playerCore: any AudioPlayerCoreProtocol,
        stateManager: PlaybackStateManager,
        registry: FailedTrackRegistry,
        persistenceController: PlaybackPersistenceController,
        repeatModeProvider: @escaping @MainActor () -> RepeatMode,
        onPause: @escaping @MainActor () -> Void,
        onTrackRequested: @escaping @MainActor (AudioTrack) -> Void
    ) {
        self.playerCore = playerCore
        self.stateManager = stateManager
        self.registry = registry
        self.persistenceController = persistenceController
        self.repeatModeProvider = repeatModeProvider
        self.onPause = onPause
        self.onTrackRequested = onTrackRequested
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

        if registry.isMarked(track.id) {
            logger.debug("Skipping known failed track: \(track.title)")
            handleLoadFailure(track: track, index: index, attempt: attempt)
            return
        }

        generation = UUID()
        let request = generation
        enqueueRequest = nil
        endWhileEnqueuing = false
        trackIndexBeforeGapless = nil
        onTrackRequested(track)
        playerCore.prepareForTrackSwitch()

        Task { @MainActor [weak self] in
            guard let self, self.generation == request else { return }

            let success = await self.playerCore.loadTrack(track)
            guard self.generation == request else { return }
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
        generation = UUID()
        enqueueRequest = nil
        endWhileEnqueuing = false
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

    func enqueueNextTrack(after track: AudioTrack? = nil) {
        guard enqueueRequest == nil else { return }
        let tracks = stateManager.currentTracks
        let index = track.flatMap { item in tracks.firstIndex { $0.id == item.id } } ?? stateManager.currentTrackIndex
        guard let index else { return }
        let request = UUID()
        let generation = generation
        enqueueRequest = request

        Task { @MainActor [weak self] in
            guard let self, self.generation == generation, self.enqueueRequest == request else { return }
            var cursor = index
            var enqueued = false
            while let next = TrackNavigationPolicy.nextValidIndex(
                after: cursor, tracks: tracks, repeatMode: self.repeatModeProvider(),
                failedIDs: self.registry.snapshot(), maxAttempts: tracks.count
            ) {
                let track = tracks[next]
                let success = await self.playerCore.enqueueTrack(track)
                guard self.generation == generation, self.enqueueRequest == request else { return }
                if success {
                    enqueued = true
                    break
                }
                self.registry.mark(track.id)
                cursor = next
            }
            self.enqueueRequest = nil
            if self.endWhileEnqueuing {
                self.endWhileEnqueuing = false
                if enqueued { self.playerCore.play() }
                else { self.handleEndOfTrack() }
            }
        }
    }

    func handleDecodingFailure(for track: AudioTrack, isCurrent: Bool) {
        guard !registry.isMarked(track.id) else { return }
        guard let index = stateManager.currentTracks.firstIndex(where: { $0.id == track.id }) else { return }
        if isCurrent {
            handleLoadFailure(track: track, index: index, attempt: 0)
        } else {
            registry.mark(track.id)
            enqueueRequest = nil
            enqueueNextTrack(after: track)
        }
    }

    func handleEndOfTrack() {
        if enqueueRequest != nil {
            endWhileEnqueuing = true
            return
        }
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

        guard let nextIndex = TrackNavigationPolicy.nextValidIndex(
            after: effectiveIndex, tracks: tracks, repeatMode: repeatMode,
            failedIDs: registry.snapshot(), maxAttempts: tracks.count
        ) else {
            logger.debug("Reached end of playlist")
            onPause()
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
}
