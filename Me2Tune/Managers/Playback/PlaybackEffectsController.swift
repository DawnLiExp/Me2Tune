//
//  PlaybackEffectsController.swift
//  Me2Tune
//
//  Centralizes playback side effects: now playing, statistics, and media keys.
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
    private let statisticsManager: any StatisticsManagerProtocol
    private let remoteCommandController: RemoteCommandController

    private let logger = Logger.effects
    private var didRegisterRemoteHandlers = false

    init(
        nowPlayingService: NowPlayingService = .shared,
        statisticsManager: any StatisticsManagerProtocol,
        remoteCommandController: RemoteCommandController = .shared
    ) {
        self.nowPlayingService = nowPlayingService
        self.statisticsManager = statisticsManager
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

    func handlePlaybackTimeUpdated(
        currentTime: TimeInterval,
        duration: TimeInterval,
        playCountThreshold: Double,
        hasMarkedPlayCount: Bool
    ) -> Bool {
        guard duration > 0 else { return hasMarkedPlayCount }

        var nextMarkedState = hasMarkedPlayCount

        if nextMarkedState, currentTime < 1.0 {
            nextMarkedState = false
        }

        if !nextMarkedState, currentTime >= duration * playCountThreshold {
            nextMarkedState = true
            Task { @MainActor in
                await self.statisticsManager.incrementTodayPlayCount()
            }
        }

        return nextMarkedState
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
