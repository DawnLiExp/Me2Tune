import Foundation
import Observation

/// Owns requests and the one successor already submitted to the audio engine.
@MainActor
@Observable
final class PlaybackLoadController {
    private let playerCore: any AudioPlayerCoreProtocol
    private let stateManager: PlaybackStateManager
    private let registry: FailedTrackRegistry
    private let persistenceController: PlaybackPersistenceController
    private let repeatModeProvider: @MainActor () -> RepeatMode
    private let onPause: @MainActor () -> Void
    private let onTrackRequested: @MainActor (AudioTrack) -> Void
    let order: PlaybackOrderState

    private(set) var generation = UUID()
    private(set) var submitted: PlaybackOrderState.Selection?
    private(set) var hasLoadedTrack = false
    private(set) var hasEnded = false
    var hasPendingStart: Bool { pendingStart != nil }
    private var pendingStart: PlaybackOrderState.Selection?
    private var enqueueRequest: UUID?
    private var endWhileEnqueuing = false
    private var decodedCurrent = false
    private var loadingAutomatic = true
    private var wantsPlayback = true

    init(
        playerCore: any AudioPlayerCoreProtocol,
        stateManager: PlaybackStateManager,
        registry: FailedTrackRegistry,
        persistenceController: PlaybackPersistenceController,
        repeatModeProvider: @escaping @MainActor () -> RepeatMode,
        onPause: @escaping @MainActor () -> Void,
        onTrackRequested: @escaping @MainActor (AudioTrack) -> Void,
        order: PlaybackOrderState = PlaybackOrderState()
    ) {
        self.playerCore = playerCore
        self.stateManager = stateManager
        self.registry = registry
        self.persistenceController = persistenceController
        self.repeatModeProvider = repeatModeProvider
        self.onPause = onPause
        self.onTrackRequested = onTrackRequested
        self.order = order
    }

    func synchronizeOrder() {
        let ids = stateManager.currentTracks.map(\.id)
        if order.ids.isEmpty {
            order.reset(ids: ids, currentID: stateManager.currentTrackID, shuffling: order.isShuffling)
        } else {
            order.reconcile(ids: ids)
        }
    }

    func start(_ selection: PlaybackOrderState.Selection, automatic: Bool = false,
               autoplay: Bool = true, resumeTime: TimeInterval? = nil) {
        invalidate()
        wantsPlayback = autoplay
        loadingAutomatic = automatic
        order.request(selection)
        pendingStart = selection
        onTrackRequestedIfPresent(selection.id)
        playerCore.prepareForTrackSwitch()
        let request = generation
        let source = stateManager.playingSource
        Task { @MainActor [weak self] in
            guard let self else { return }
            var target = selection
            var attempted: Set<UUID> = []
            while self.generation == request, self.stateManager.playingSource == source,
                  let track = self.stateManager.currentTracks.first(where: { $0.id == target.id }),
                  attempted.insert(target.id).inserted {
                self.order.request(target)
                self.pendingStart = target
                let success: Bool
                if self.registry.isMarked(track.id) { success = false }
                else { success = await self.playerCore.loadTrack(track, startingAt: resumeTime ?? 0) }
                guard self.generation == request, self.stateManager.playingSource == source else { return }
                self.synchronizeOrder()
                guard self.order.ids.contains(track.id) else { return }
                if success {
                    self.hasLoadedTrack = true
                    self.stateManager.setCurrentTrack(id: track.id)
                    self.persistenceController.scheduleSave()
                    if self.wantsPlayback { self.playerCore.play() }
                    return
                }
                self.pendingStart = nil
                if resumeTime != nil {
                    self.order.cancelRequest()
                    self.onPause()
                    return
                }
                self.registry.mark(track.id)
                if automatic && self.repeatModeProvider() == .one { break }
                guard let next = self.order.next(repeatMode: self.repeatModeProvider(), automatic: false,
                                                 failed: self.registry.snapshot().union(attempted)) else { break }
                target = next
                self.onTrackRequestedIfPresent(target.id)
            }
            guard self.generation == request else { return }
            self.order.cancelRequest()
            self.pendingStart = nil
            self.hasEnded = true
            self.onPause()
        }
    }

    private func onTrackRequestedIfPresent(_ id: UUID) {
        if let track = stateManager.currentTracks.first(where: { $0.id == id }) { onTrackRequested(track) }
    }

    func restore(_ track: AudioTrack) async -> Bool {
        invalidate()
        wantsPlayback = false
        let request = generation
        pendingStart = order.select(track.id)
        let success = await playerCore.loadTrack(track)
        guard generation == request else { return false }
        hasLoadedTrack = success
        if !success { pendingStart = nil }
        else if wantsPlayback { playerCore.play() }
        return success
    }

    func invalidate() {
        generation = UUID()
        submitted = nil
        pendingStart = nil
        enqueueRequest = nil
        endWhileEnqueuing = false
        decodedCurrent = false
        hasEnded = false
        hasLoadedTrack = false
        order.cancelRequest()
    }

    func stop() {
        invalidate()
        wantsPlayback = false
        playerCore.prepareForTrackSwitch()
    }

    func setPlaybackIntent(_ playing: Bool) {
        wantsPlayback = playing
    }

    func confirmStarted(_ track: AudioTrack) {
        let wasDecoded = decodedCurrent
        let wasPending = pendingStart != nil
        let selection: PlaybackOrderState.Selection
        if let pendingStart, pendingStart.id == track.id {
            selection = pendingStart
            self.pendingStart = nil
        } else if let submitted, submitted.id == track.id {
            loadingAutomatic = true
            selection = submitted
            self.submitted = nil
        } else { return }
        order.confirm(selection)
        hasLoadedTrack = true
        hasEnded = false
        decodedCurrent = false
        if wasPending && wasDecoded { enqueueNextTrack() }
    }

    func modesChanged() {
        // Once submitted, a decoder may already be in the engine's active ring buffer.
        guard submitted == nil else { return }
        enqueueRequest = nil
        if decodedCurrent { enqueueNextTrack() }
    }

    func enqueueNextTrack(after track: AudioTrack? = nil) {
        decodedCurrent = true
        guard pendingStart == nil, submitted == nil, enqueueRequest == nil else { return }
        synchronizeOrder()
        // Restored paused tracks may finish decoding before their first audible start.
        if order.currentID == nil, let track {
            order.reset(ids: order.ids, currentID: track.id, shuffling: order.isShuffling)
        }
        let request = UUID()
        let generation = generation
        enqueueRequest = request
        Task { @MainActor [weak self] in
            guard let self, self.generation == generation, self.enqueueRequest == request else { return }
            var attempted: Set<UUID> = []
            while let next = self.order.next(repeatMode: self.repeatModeProvider(), automatic: true,
                                             failed: self.registry.snapshot().union(attempted)),
                  attempted.insert(next.id).inserted,
                  let track = self.stateManager.currentTracks.first(where: { $0.id == next.id }) {
                let result = self.playerCore.enqueueTrack(track)
                guard self.generation == generation, self.enqueueRequest == request else { return }
                switch result {
                case .enqueued(let id), .occupied(let id):
                    self.submitted = id == next.id ? next : self.order.select(id)
                case .failed:
                    self.registry.mark(track.id)
                }
                if self.submitted != nil { break }
            }
            self.enqueueRequest = nil
            if self.endWhileEnqueuing {
                self.endWhileEnqueuing = false
                if self.submitted != nil, self.wantsPlayback { self.playerCore.play() }
                else { self.handleEndOfTrack() }
            }
        }
    }

    func handleDecodingFailure(for track: AudioTrack, isCurrent: Bool) {
        synchronizeOrder()
        guard !registry.isMarked(track.id), order.ids.contains(track.id) else { return }
        registry.mark(track.id)
        if isCurrent {
            let automatic = loadingAutomatic
            invalidate()
            if automatic && repeatModeProvider() == .one { onPause(); return }
            order.request(order.select(track.id))
            guard let next = order.next(repeatMode: repeatModeProvider(), automatic: false,
                                        failed: registry.snapshot()) else { onPause(); return }
            start(next, automatic: automatic)
        } else {
            submitted = nil
            enqueueRequest = nil
            enqueueNextTrack()
        }
    }

    func handleEndOfTrack() {
        guard !hasEnded, decodedCurrent else { return }
        if enqueueRequest != nil { endWhileEnqueuing = true; return }
        // A successor owns the transition; a late end notification must not advance it twice.
        guard submitted == nil else { return }
        synchronizeOrder()
        if let next = order.next(repeatMode: repeatModeProvider(), automatic: true, failed: registry.snapshot()) {
            start(next, automatic: true)
        } else {
            hasEnded = true
            hasLoadedTrack = false
            onPause()
        }
    }

    func retryIfFailed(_ track: AudioTrack) { registry.clear(track.id) }
}
