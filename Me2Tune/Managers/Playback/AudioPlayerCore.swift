//
//  AudioPlayerCore.swift
//  Me2Tune
//
//  音频播放核心 - 纯播放逻辑 + 加载状态返回
//

import AppKit
import Foundation
import OSLog
import SFBAudioEngine

private let logger = Logger.player

// MARK: - Delegate Protocol

@MainActor
protocol AudioPlayerCoreDelegate: AnyObject {
    func playerCoreDidUpdatePlaybackState(_ isPlaying: Bool)
    func playerCoreDidUpdateTime(currentTime: TimeInterval, duration: TimeInterval)
    func playerCoreDidLoadTrack(_ track: AudioTrack, artwork: NSImage?)
    func playerCoreDidEncounterError(_ error: Error)
    func playerCoreDidConfirmSeek(to time: TimeInterval)
    func playerCoreDecodingFailed(for track: AudioTrack, isCurrent: Bool)
    func playerCoreDidReachEnd()
    func playerCoreDecodingComplete(for track: AudioTrack)
    func playerCoreNowPlayingChanged(to track: AudioTrack?)
}

// MARK: - Audio Player Core

@MainActor
final class AudioPlayerCore: NSObject {
    weak var delegate: (any AudioPlayerCoreDelegate)?
    
    private var player: AudioPlayer?
    // Weak references also cover decoders retained temporarily by engine callbacks.
    private final class DecoderReleaseProbe {
        weak var decoder: AudioDecoder?
        init(_ decoder: AudioDecoder) { self.decoder = decoder }
    }
    private var decoderReleaseProbes: [DecoderReleaseProbe] = []

    func waitForStoppedDecoders() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while decoderReleaseProbes.contains(where: { $0.decoder != nil }) {
            guard !Task.isCancelled, ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        decoderReleaseProbes.removeAll()
        return true
    }

    private func trackDecoderLifetime(_ decoder: AudioDecoder) -> AudioDecoder {
        decoderReleaseProbes.removeAll { $0.decoder == nil }
        decoderReleaseProbes.append(DecoderReleaseProbe(decoder))
        return decoder
    }
    
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var currentTrack: AudioTrack?
    private var decoderQueue = PlaybackDecoderQueue()
    private let events = AudioPlayerEvents()
    private var eventTask: Task<Void, Never>?
    private var pendingSeek: TimeInterval?
    private var seekingDecoderID: ObjectIdentifier?
    
    private var audioBufferingEnabled: Bool {
        UserDefaults.standard.bool(forKey: "audioBufferingEnabled")
    }
    
    typealias RepeatMode = Me2Tune.RepeatMode
    
    var repeatMode: RepeatMode = .off
    var volume: Double = 0.7
    
    override init() {
        super.init()
        let stream = events.stream
        eventTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { break }
                self?.handle(event)
            }
        }
        logger.debug("AudioPlayerCore initialized")
    }
    
    // MARK: - Playback Control
    
    deinit { eventTask?.cancel() }

    func loadTrack(_ track: AudioTrack, startingAt time: TimeInterval = 0) async -> Bool {
        let loadStartedAt = CFAbsoluteTimeGetCurrent()
        logger.info("Loading: \(track.title)")
        ensurePlayerInitialized()
        guard let player else { return false }
        player.pause()
        decoderQueue.reset()
        pendingSeek = nil
        seekingDecoderID = nil
        let generation = decoderQueue.generation
        isPlaying = false
        currentTrack = track
        currentTime = 0
        duration = track.duration

        do {
            try enqueueCurrentDecoder(for: track, startingAt: time, player: player)
            delegate?.playerCoreDidUpdatePlaybackState(false)
            delegate?.playerCoreDidUpdateTime(currentTime: currentTime, duration: duration)
            let artwork = await ArtworkCacheService.shared.artwork(for: track.url)
            guard decoderQueue.generation == generation, decoderQueue.currentID != nil else { return false }
            delegate?.playerCoreDidLoadTrack(track, artwork: artwork)
            updateDockIcon(artwork)
            logger.logPerformance("Track load", duration: CFAbsoluteTimeGetCurrent() - loadStartedAt)
            return true
        } catch {
            decoderQueue.reset()
            player.stop()
            delegate?.playerCoreDidEncounterError(AppError.audioLoadFailed(track.url))
            return false
        }
    }

    // Keep the decoder's local strong reference out of the artwork suspension point.
    // The save path waits for engine cancellation and callback ownership to finish.
    private func enqueueCurrentDecoder(for track: AudioTrack, startingAt time: TimeInterval, player: AudioPlayer) throws {
        let decoder = try makeDecoder(for: track)
        if time > 0 {
            // Seek before enqueueing: a paused engine may not yet expose a current decoder.
            if !decoder.isOpen { try decoder.open() }
            guard time.isFinite, decoder.supportsSeeking, decoder.length > 0 else {
                throw AppError.audioLoadFailed(track.url)
            }
            let frame = min(time * decoder.processingFormat.sampleRate, Double(decoder.length - 1))
            try decoder.seek(to: Int64(frame))
            currentTime = Double(decoder.position) / decoder.processingFormat.sampleRate
        }
        decoderQueue.register(DecoderReference(decoder), track: track, current: true)
        // Queue without briefly rendering the track while artwork is loading.
        try player.enqueue(decoder, immediate: true)
    }

    var queuedTrackID: UUID? { decoderQueue.queuedTrack?.id }

    func enqueueTrack(_ track: AudioTrack) -> AudioEnqueueResult {
        guard let player else { return .failed }
        logger.info("Enqueuing: \(track.title)")
        // Exactly one future playback instance is owned by this core.
        if let queued = decoderQueue.queuedTrack { return .occupied(queued.id) }
        do {
            let decoder = try makeDecoder(for: track)
            let reference = DecoderReference(decoder)
            decoderQueue.register(reference, track: track, current: false)
            do {
                try player.enqueue(decoder)
            } catch {
                _ = decoderQueue.remove(reference.id)
                throw error
            }
            return .enqueued(track.id)
        } catch {
            delegate?.playerCoreDidEncounterError(AppError.audioLoadFailed(track.url))
            return .failed
        }
    }

    private func makeDecoder(for track: AudioTrack) throws -> AudioDecoder {
        if audioBufferingEnabled {
            let isNetwork = AudioBufferDetector.isNetworkStorage(url: track.url)
            if AudioBufferDetector.calculateBufferSize(track: track, isNetworkStorage: isNetwork) != nil {
                do {
                    let source = try InputSource(for: track.url, flags: .loadFilesInMemory)
                    return trackDecoderLifetime(try AudioDecoder(inputSource: source))
                } catch {
                    logger.warning("Buffering failed, using direct playback: \(error)")
                }
            }
        }
        return trackDecoderLifetime(try AudioDecoder(url: track.url))
    }

    func play() {
        ensurePlayerInitialized()
        guard let player else { return }
        
        do {
            try player.play()
            isPlaying = true
            delegate?.playerCoreDidUpdatePlaybackState(true)
            logger.debug("▶️ Playback started")
        } catch {
            let appError = AppError.audioPlayFailed(error.localizedDescription)
            logger.logError(appError, context: "play")
            delegate?.playerCoreDidEncounterError(appError)
        }
    }
    
    func pause() {
        guard let player else { return }
        
        player.pause()
        isPlaying = false
        delegate?.playerCoreDidUpdatePlaybackState(false)
        logger.debug("⏸ Playback paused")
    }
    
    func seek(to time: TimeInterval) {
        guard time.isFinite, time >= 0, let player, player.supportsSeeking,
              let current = player.currentDecoder,
              ObjectIdentifier(current) == decoderQueue.currentID else { return }
        pendingSeek = time
        if seekingDecoderID == nil { submitPendingSeek() }
    }

    private func submitPendingSeek() {
        guard let target = pendingSeek, let player else { return }
        pendingSeek = nil
        guard player.supportsSeeking, let current = player.currentDecoder,
              ObjectIdentifier(current) == decoderQueue.currentID,
              let snapshot = player.positionAndTime else { return }
        let position = snapshot.position
        let time = snapshot.time
        guard position.frameLength > 0, time.totalTime > 0 else { return }
        let sampleRate = Double(position.frameLength) / time.totalTime
        let targetFrame = min(target * sampleRate, Double(position.frameLength - 1))
        // Seeking to the existing frame succeeds without generating a callback.
        if targetFrame >= 0, targetFrame < Double(Int64.max), Int64(targetFrame) == position.framePosition {
            confirmSeek(time.currentTime)
        } else if player.seek(time: target) {
            seekingDecoderID = ObjectIdentifier(current)
        }
    }

    private func confirmSeek(_ time: TimeInterval) {
        guard time.isFinite, time >= 0 else { return }
        currentTime = time
        delegate?.playerCoreDidUpdateTime(currentTime: time, duration: duration)
        delegate?.playerCoreDidConfirmSeek(to: time)
    }

    func setVolume(_ volume: Double) {
        guard let player else { return }
        
        do {
            try player.setVolume(Float(volume))
            self.volume = volume
            let pct = String(format: "%.0f", volume * 100)
            logger.debug("🔊 Volume set to \(pct)%")
        } catch {
            logger.error("Failed to set volume: \(error)")
        }
    }
    
    // MARK: - Real-time Progress
    
    func getCurrentPlaybackTime() -> TimeInterval {
        guard seekingDecoderID == nil else { return currentTime }
        if let decoder = player?.currentDecoder, ObjectIdentifier(decoder) == decoderQueue.currentID,
           let time = player?.currentTime, time.isFinite, time >= 0 { currentTime = time }
        return currentTime
    }
    
    func prepareForTrackSwitch() {
        player?.stop()
        isPlaying = false
        delegate?.playerCoreDidUpdatePlaybackState(false)
        decoderQueue.reset()
        pendingSeek = nil
        seekingDecoderID = nil
        currentTime = 0
        delegate?.playerCoreDidUpdateTime(currentTime: 0, duration: duration)
        logger.debug("🧹 Prepared for track switch (progress reset)")
    }
    
    // MARK: - Private Methods
    
    private func ensurePlayerInitialized() {
        guard player == nil else { return }
        
        player = AudioPlayer()
        player?.delegate = events
        logger.debug("Audio player initialized")
    }
    
    func updateDockIcon(_ artwork: NSImage?) {
        guard let artwork else {
            NSApp.dockTile.contentView = nil
            NSApp.dockTile.display()
            return
        }
            
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
            
        let imageView = NSImageView(frame: NSRect(x: 6, y: 6, width: 116, height: 116))
        imageView.image = artwork
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
            
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 2
        imageView.layer?.borderColor = NSColor.black.cgColor
            
        containerView.addSubview(imageView)
            
        NSApp.dockTile.contentView = containerView
        NSApp.dockTile.display()
    }
}

// MARK: - Ordered Player Events

extension AudioPlayerCore {
    private func handle(_ event: AudioPlayerEvent) {
        switch event {
        case .stateChanged:
            // State notifications may be delayed; publish the current engine state.
            isPlaying = player?.isPlaying ?? false
            delegate?.playerCoreDidUpdatePlaybackState(isPlaying)
        case .nowPlaying(let reference, let time):
            guard let reference else {
                // A nil event does not consume a queued track or erase the last displayed track.
                return
            }
            let changed = decoderQueue.currentID != reference.id
            guard let track = decoderQueue.activate(reference.id) else { return }
            if changed {
                pendingSeek = nil
                seekingDecoderID = nil
            }
            currentTrack = track
            duration = track.duration
            currentTime = time
            delegate?.playerCoreNowPlayingChanged(to: track)
            delegate?.playerCoreDidUpdateTime(currentTime: time, duration: duration)
            notifyDecodingCompleteIfNeeded()
        case .decoded(let reference):
            decoderQueue.decoded(reference.id)
            notifyDecodingCompleteIfNeeded()
        case .rendered(let reference):
            decoderQueue.rendered(reference.id)
        case .canceled(let reference):
            _ = decoderQueue.remove(reference.id)
        case .aborted(let reference, let error):
            guard let failure = decoderQueue.remove(reference.id) else { return }
            if failure.isCurrent {
                pendingSeek = nil
                seekingDecoderID = nil
                decoderQueue.reset()
                player?.stop()
                isPlaying = false
                delegate?.playerCoreDidUpdatePlaybackState(false)
            }
            delegate?.playerCoreDidEncounterError(error)
            delegate?.playerCoreDecodingFailed(for: failure.track, isCurrent: failure.isCurrent)
        case .sought(let reference, let time):
            guard seekingDecoderID == reference.id, decoderQueue.currentID == reference.id else { return }
            seekingDecoderID = nil
            if pendingSeek != nil { submitPendingSeek() }
            else { confirmSeek(time) }
        case .end:
            // Ignore unscoped end events from a previous load or while a successor is pending.
            guard player?.currentDecoder == nil, player?.queueIsEmpty == true,
                  decoderQueue.takeEnd() else { return }
            pendingSeek = nil
            seekingDecoderID = nil
            pause()
            delegate?.playerCoreDidReachEnd()
        case .error(let error):
            delegate?.playerCoreDidEncounterError(error)
        }
    }

    private func notifyDecodingCompleteIfNeeded() {
        guard let track = decoderQueue.takeCompletedCurrentTrack() else { return }
        delegate?.playerCoreDecodingComplete(for: track)
    }
}

extension AudioPlayerCore: AudioPlayerCoreProtocol {}
