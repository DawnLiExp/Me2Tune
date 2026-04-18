//
//  PlaybackEffectsController.swift
//  Me2Tune
//
//  Centralizes playback side effects: now playing and media keys.
//

import AppKit
import Foundation
import OSLog

struct PlaybackCommandHandlers {
    let play: @MainActor () -> Void
    let pause: @MainActor () -> Void
    let togglePlayPause: @MainActor () -> Void
    let next: @MainActor () -> Void
    let previous: @MainActor () -> Void
    let seek: @MainActor (TimeInterval) -> Void
    let canGoNext: @MainActor () -> Bool
    let canGoPrevious: @MainActor () -> Bool
    let isPlaying: @MainActor () -> Bool
}

@MainActor
final class PlaybackEffectsController {
    private let nowPlayingService: NowPlayingService
    private let remoteCommandController: RemoteCommandController

    private let logger = Logger.effects
    private var didRegisterRemoteHandlers = false

    init(
        nowPlayingService: NowPlayingService = .shared,
        remoteCommandController: RemoteCommandController = .shared
    ) {
        self.nowPlayingService = nowPlayingService
        self.remoteCommandController = remoteCommandController
    }

    func handleSeek(to time: TimeInterval) {
        nowPlayingService.updatePlaybackTime(currentTime: time)
        nowPlayingService.restartUpdateTimer()
    }

    func handlePlaybackStateChanged(
        isPlaying: Bool,
        currentTimeProvider: @escaping () -> TimeInterval
    ) {
        nowPlayingService.updatePlaybackState(isPlaying: isPlaying)
        nowPlayingService.handlePlaybackStateChange(
            isPlaying: isPlaying,
            currentTimeProvider: currentTimeProvider
        )
    }

    func ensureRemoteCommandsReady(handlers: PlaybackCommandHandlers) {
        if !didRegisterRemoteHandlers {
            remoteCommandController.register(handlers: handlers)
            didRegisterRemoteHandlers = true
            logger.info("Remote command handlers registered")
        }

        remoteCommandController.enable()
    }

    func disableRemoteCommands() {
        remoteCommandController.disable()
    }

    func updateNowPlayingInfo(
        track: AudioTrack,
        artwork: NSImage?,
        currentTime: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool
    ) {
        nowPlayingService.updateNowPlayingInfo(
            track: track,
            artwork: artwork,
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying
        )
    }

    func clearNowPlayingInfo() {
        nowPlayingService.clearNowPlayingInfo()
    }
}
