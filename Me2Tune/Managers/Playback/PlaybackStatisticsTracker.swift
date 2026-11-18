//
//  PlaybackStatisticsTracker.swift
//  Me2Tune
//
//  Tracks per-track playback counting state and writes statistics when playback crosses the configured threshold.
//

import Foundation

@MainActor
final class PlaybackStatisticsTracker {
    private let statisticsManager: any StatisticsManagerProtocol
    private let playCountThreshold: Double
    private let resetBoundary: TimeInterval

    private var currentTrackID: UUID?
    private var awaitingFirstActivation = false
    private var hasCountedCurrentSession = false

    init(
        statisticsManager: any StatisticsManagerProtocol,
        playCountThreshold: Double = 0.8,
        resetBoundary: TimeInterval = 1.0
    ) {
        self.statisticsManager = statisticsManager
        self.playCountThreshold = playCountThreshold
        self.resetBoundary = resetBoundary
    }

    func prepareForRequestedTrack(_ trackID: UUID) {
        currentTrackID = trackID
        awaitingFirstActivation = true
        hasCountedCurrentSession = false
    }

    // The core emits one activation per decoder, including same-track successors.
    func didActivateTrack(_ trackID: UUID) {
        let confirmsRequest = awaitingFirstActivation && currentTrackID == trackID
        awaitingFirstActivation = false
        currentTrackID = trackID
        if !confirmsRequest { hasCountedCurrentSession = false }
    }

    func evaluate(currentTime: TimeInterval, duration: TimeInterval) {
        guard currentTrackID != nil, duration > 0 else { return }
        guard !hasCountedCurrentSession else { return }
        guard currentTime >= duration * playCountThreshold else { return }

        hasCountedCurrentSession = true
        Task { @MainActor [statisticsManager] in
            await statisticsManager.incrementTodayPlayCount()
        }
    }

    func handleSeek(to time: TimeInterval, duration: TimeInterval) {
        if time < resetBoundary { hasCountedCurrentSession = false }
        evaluate(currentTime: time, duration: duration)
    }
}
