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
        hasCountedCurrentSession = false
    }

    func synchronizeObservedTrack(_ trackID: UUID) {
        guard currentTrackID != trackID else { return }
        currentTrackID = trackID
        hasCountedCurrentSession = false
    }

    func evaluate(currentTime: TimeInterval, duration: TimeInterval) {
        guard currentTrackID != nil, duration > 0 else { return }

        if hasCountedCurrentSession, currentTime < resetBoundary {
            hasCountedCurrentSession = false
        }

        guard !hasCountedCurrentSession else { return }
        guard currentTime >= duration * playCountThreshold else { return }

        hasCountedCurrentSession = true
        Task { @MainActor [statisticsManager] in
            await statisticsManager.incrementTodayPlayCount()
        }
    }

    func handleSeek(to time: TimeInterval, duration: TimeInterval) {
        evaluate(currentTime: time, duration: duration)
    }
}
