//
//  AudioPlayerCore.swift
//  Me2Tune
//
//  音频播放核心 - 纯播放逻辑，无 UI 状态
//

import AppKit
import Foundation
import OSLog
import SFBAudioEngine

private let logger = Logger.player

// MARK: - Delegate Protocol

protocol AudioPlayerCoreDelegate: AnyObject {
    func playerCore(_ core: AudioPlayerCore, didUpdatePlaybackState isPlaying: Bool)
    func playerCore(_ core: AudioPlayerCore, didUpdateTime currentTime: TimeInterval, duration: TimeInterval)
    func playerCore(_ core: AudioPlayerCore, didLoadTrack track: AudioTrack, artwork: NSImage?)
    func playerCore(_ core: AudioPlayerCore, didEncounterError error: Error)
    func playerCoreDidReachEnd(_ core: AudioPlayerCore)
}

// MARK: - Audio Player Core

final class AudioPlayerCore: NSObject {
    weak var delegate: AudioPlayerCoreDelegate?
    
    private var player: AudioPlayer?
    private var timer: Timer?
    private let artworkService = ArtworkService()
    
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    
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
    
    deinit {
        stopTimer()
        logger.debug("AudioPlayerCore deinitialized")
    }
    
    // MARK: - Playback Control
    
    func loadTrack(_ track: AudioTrack) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        ensurePlayerInitialized()
        guard let player else { return }
        
        await MainActor.run {
            if isPlaying {
                player.pause()
                isPlaying = false
            }
            stopTimer()
        }
        
        logger.info("Loading: \(track.title)")
        
        do {
            try player.play(track.url)
            player.pause()
            
            await MainActor.run {
                duration = track.duration
                currentTime = 0
                isPlaying = false
            }
            
            let artwork = await artworkService.artwork(for: track.url)
            
            await MainActor.run {
                delegate?.playerCore(self, didLoadTrack: track, artwork: artwork)
                updateDockIcon(artwork)
            }
            
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            logger.logPerformance("Track load", duration: elapsed)
        } catch {
            let appError = AppError.audioLoadFailed(track.url)
            logger.logError(appError, context: "loadTrack")
            await MainActor.run {
                delegate?.playerCore(self, didEncounterError: appError)
            }
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            
            Task { @MainActor [weak self] in
                guard let self else { return }
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPlaying = (playbackState == .playing)
            self.delegate?.playerCore(self, didUpdatePlaybackState: self.isPlaying)
        }
    }
    
    nonisolated func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.playerCoreDidReachEnd(self)
        }
    }
    
    @objc nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            logger.error("Player error: \(error.localizedDescription)")
            self.delegate?.playerCore(self, didEncounterError: error)
        }
    }
}
