//
//  AudioPlayerCore.swift
//  Me2Tune
//
//  音频播放核心 - 纯播放逻辑（三档自适应刷新频率）
//

import AppKit
import Foundation
import OSLog
import SFBAudioEngine

private let logger = Logger.player

// MARK: - Delegate Protocol

@MainActor
protocol AudioPlayerCoreDelegate: AnyObject {
    func playerCore(_ core: AudioPlayerCore, didUpdatePlaybackState isPlaying: Bool)
    func playerCore(_ core: AudioPlayerCore, didUpdateTime currentTime: TimeInterval, duration: TimeInterval)
    func playerCore(_ core: AudioPlayerCore, didLoadTrack track: AudioTrack, artwork: NSImage?)
    func playerCore(_ core: AudioPlayerCore, didEncounterError error: Error)
    func playerCoreDidReachEnd(_ core: AudioPlayerCore)
    func playerCore(_ core: AudioPlayerCore, decodingCompleteFor track: AudioTrack)
    func playerCore(_ core: AudioPlayerCore, nowPlayingChangedTo url: URL?)
}

// MARK: - Audio Player Core

@MainActor
final class AudioPlayerCore: NSObject {
    weak var delegate: AudioPlayerCoreDelegate?
    
    private var player: AudioPlayer?
    private var timer: DispatchSourceTimer?
    
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var currentTrack: AudioTrack?
    
    private(set) var visibilityState: WindowStateMonitor.WindowVisibilityState = .activeFocused
    
    private var shouldTimerRun: Bool {
        return isPlaying
    }
    
    enum RepeatMode {
        case off
        case all
        case one
    }
    
    var repeatMode: RepeatMode = .off
    var volume: Double = 0.7
    
    override init() {
        super.init()
        logger.debug("AudioPlayerCore initialized")
    }
    
    nonisolated deinit {
        // DispatchSourceTimer.cancel() 是线程安全的
        timer?.cancel()
        timer = nil
    }
    
    // MARK: - Window Visibility
    
    func updateVisibilityState(_ state: WindowStateMonitor.WindowVisibilityState) {
        logger.debug("🎯 AudioPlayerCore received state: \(state.description)")
        
        guard visibilityState != state else {
            logger.debug("🎯 State unchanged, skipping")
            return
        }
        
        let oldState = visibilityState
        visibilityState = state
        
        logger.debug("⚡ Visibility changed: \(oldState.description) -> \(state.description)")
        logger.debug("⚡ Update interval: \(String(format: "%.1f", state.updateInterval))s")
        
        if shouldTimerRun {
            logger.debug("⚡ Rebuilding timer with new interval")
            startTimer()
        } else {
            logger.debug("⚡ Not playing, skipping timer rebuild")
        }
    }
    
    // MARK: - Playback Control
    
    func loadTrack(_ track: AudioTrack) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        ensurePlayerInitialized()
        guard let player else { return }
        
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        stopTimer()
        
        logger.info("Loading: \(track.title)")
        
        do {
            try player.play(track.url)
            player.pause()
            
            duration = track.duration
            currentTime = 0
            isPlaying = false
            currentTrack = track
            
            let artwork = await ArtworkCacheService.shared.artwork(for: track.url)
            
            delegate?.playerCore(self, didLoadTrack: track, artwork: artwork)
            updateDockIcon(artwork)
            
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            logger.logPerformance("Track load", duration: elapsed)
        } catch {
            let appError = AppError.audioLoadFailed(track.url)
            logger.logError(appError, context: "loadTrack")
            delegate?.playerCore(self, didEncounterError: appError)
        }
    }
    
    func enqueueTrack(_ track: AudioTrack) async {
        ensurePlayerInitialized()
        guard let player else { return }
        
        logger.info("Enqueuing: \(track.title)")
        
        do {
            let decoder = try AudioDecoder(url: track.url)
            try player.enqueue(decoder)
            logger.debug("✓ Enqueued next track")
        } catch {
            let appError = AppError.audioLoadFailed(track.url)
            logger.logError(appError, context: "enqueueTrack")
            delegate?.playerCore(self, didEncounterError: appError)
        }
    }
    
    func play() {
        ensurePlayerInitialized()
        guard let player else { return }
        
        do {
            try player.play()
            isPlaying = true
            startTimer()
            delegate?.playerCore(self, didUpdatePlaybackState: true)
            logger.debug("▶️ Playback started")
        } catch {
            let appError = AppError.audioPlayFailed(error.localizedDescription)
            logger.logError(appError, context: "play")
            delegate?.playerCore(self, didEncounterError: appError)
        }
    }
    
    func pause() {
        guard let player else { return }
        
        player.pause()
        isPlaying = false
        stopTimer()
        delegate?.playerCore(self, didUpdatePlaybackState: false)
        logger.debug("⏸ Playback paused")
    }
    
    func seek(to time: TimeInterval) {
        guard let player, player.supportsSeeking else {
            logger.warning("Seek not supported for current track")
            return
        }
        
        let wasPlaying = isPlaying
        if wasPlaying {
            player.pause()
        }
        
        if player.seek(time: time) {
            currentTime = time
            delegate?.playerCore(self, didUpdateTime: currentTime, duration: duration)
            logger.debug("⏩ Seeked to \(String(format: "%.1f", time))s")
        } else {
            logger.warning("Seek to \(time)s failed")
        }
        
        if wasPlaying {
            do {
                try player.play()
            } catch {
                let appError = AppError.audioPlayFailed("Resume after seek failed")
                logger.logError(appError, context: "seek")
                isPlaying = false
                delegate?.playerCore(self, didUpdatePlaybackState: false)
                delegate?.playerCore(self, didEncounterError: appError)
            }
        }
    }
    
    func setVolume(_ volume: Double) {
        guard let player else { return }
        
        do {
            try player.setVolume(Float(volume))
            self.volume = volume
            logger.debug("🔊 Volume set to \(String(format: "%.0f", volume * 100))%")
        } catch {
            logger.error("Failed to set volume: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Real-time Progress
    
    func getCurrentPlaybackTime() -> TimeInterval {
        return player?.currentTime ?? currentTime
    }
    
    // MARK: - Private Methods
    
    private func ensurePlayerInitialized() {
        guard player == nil else { return }
        
        player = AudioPlayer()
        player?.delegate = self
        logger.debug("Audio player initialized")
    }
    
    private func startTimer() {
        stopTimer()
        
        let interval = visibilityState.updateInterval
        
        let leeway: DispatchTimeInterval
        switch visibilityState {
        case .activeFocused:
            leeway = .milliseconds(200)
        case .inactive:
            leeway = .milliseconds(300)
        case .hidden, .miniHidden:
            leeway = .milliseconds(1000)
        case .miniVisible:
            leeway = .milliseconds(200)
        }
        
        logger.debug("⏱️ Creating timer for \(self.visibilityState.description), interval: \(String(format: "%.1f", interval))s")
        
        let newTimer = DispatchSource.makeTimerSource(queue: .main)
        newTimer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: leeway
        )
        
        newTimer.setEventHandler { [weak self] in
            guard let self, let player = self.player else { return }
            
            self.currentTime = player.currentTime ?? 0
            self.duration = player.totalTime ?? 0
            self.delegate?.playerCore(self, didUpdateTime: self.currentTime, duration: self.duration)
        }
        
        newTimer.resume()
        timer = newTimer
    }

    private func stopTimer() {
        if timer != nil {
            logger.debug("⏱️ Stopping timer")
        }
        timer?.cancel()
        timer = nil
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

// MARK: - AudioPlayer.Delegate

extension AudioPlayerCore: AudioPlayer.Delegate {
    nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, playbackStateChanged playbackState: AudioPlayer.PlaybackState) {
        Task { @MainActor in
            self.isPlaying = (playbackState == .playing)
            self.delegate?.playerCore(self, didUpdatePlaybackState: self.isPlaying)
        }
    }
    
    nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, nowPlayingChanged nowPlaying: PCMDecoding?, previouslyPlaying: PCMDecoding?) {
        let url = nowPlaying?.inputSource.url
        Task { @MainActor in
            logger.debug("🔄 Now playing changed to: \(url?.lastPathComponent ?? "nil")")
            self.delegate?.playerCore(self, nowPlayingChangedTo: url)
        }
    }
    
    nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, decodingComplete decoder: PCMDecoding) {
        Task { @MainActor in
            guard let track = self.currentTrack else { return }
            logger.debug("✓ Decoding complete for: \(track.title)")
            self.delegate?.playerCore(self, decodingCompleteFor: track)
        }
    }
    
    nonisolated func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
        Task { @MainActor in
            self.delegate?.playerCoreDidReachEnd(self)
        }
    }
    
    @objc nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) {
        Task { @MainActor in
            logger.error("Player error: \(error.localizedDescription)")
            self.delegate?.playerCore(self, didEncounterError: error)
        }
    }
}
