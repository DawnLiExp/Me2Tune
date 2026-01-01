//
//  AudioPlayerCore.swift
//  Me2Tune
//
//  音频播放核心 - 纯播放逻辑,无 UI 状态(窗口不可见时降低更新频率)
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
    private nonisolated(unsafe) var timer: Timer?
    
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var currentTrack: AudioTrack?
    
    // 窗口可见性状态
    private(set) var isWindowVisible = true
    
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
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Window Visibility
    
    func updateWindowVisibility(_ isVisible: Bool) {
        guard isWindowVisible != isVisible else { return }
        
        isWindowVisible = isVisible
        
        // 重新配置定时器以使用新的更新频率
        if isPlaying {
            startTimer()
        }
        
        logger.debug("Window visibility: \(isVisible ? "visible" : "hidden")")
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
    
    // MARK: - Private Methods
    
    private func ensurePlayerInitialized() {
        guard player == nil else { return }
        
        player = AudioPlayer()
        player?.delegate = self
        logger.debug("Audio player initialized")
    }
    
    private func startTimer() {
        stopTimer()
        
        // 窗口不可见时降低更新频率: 0.2s -> 1.0s
        let interval: TimeInterval = isWindowVisible ? 0.2 : 1.0
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                
                self.currentTime = player.currentTime ?? 0
                self.duration = player.totalTime ?? 0
                self.delegate?.playerCore(self, didUpdateTime: self.currentTime, duration: self.duration)
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateDockIcon(_ artwork: NSImage?) {
        guard let artwork else {
            NSApp.dockTile.contentView = nil
            NSApp.dockTile.display()
            return
        }
        
        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        imageView.image = artwork
        imageView.imageScaling = .scaleProportionallyUpOrDown
        
        NSApp.dockTile.contentView = imageView
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
