//
//  PlaybackStatisticsTrackerTests.swift
//  Me2TuneTests
//
//  Unit tests for playback statistics tracking behavior.
//

import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("PlaybackStatisticsTracker 单元测试")
struct PlaybackStatisticsTrackerTests {
    @Test("未到 80% 不计数")
    func doesNotCountBeforeThreshold() async throws {
        let statistics = MockTrackerStatisticsManager()
        let tracker = PlaybackStatisticsTracker(statisticsManager: statistics)

        tracker.prepareForRequestedTrack(UUID())
        tracker.evaluate(currentTime: 79, duration: 100)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(statistics.incrementCount == 0)
    }

    @Test("到 80% 只计数一次")
    func countsOnlyOncePerSession() async throws {
        let statistics = MockTrackerStatisticsManager()
        let tracker = PlaybackStatisticsTracker(statisticsManager: statistics)

        tracker.prepareForRequestedTrack(UUID())
        tracker.evaluate(currentTime: 81, duration: 100)
        tracker.evaluate(currentTime: 95, duration: 100)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(statistics.incrementCount == 1)
    }

    @Test("seek 到 80% 立即计数")
    func seekCanCountImmediately() async throws {
        let statistics = MockTrackerStatisticsManager()
        let tracker = PlaybackStatisticsTracker(statisticsManager: statistics)

        tracker.prepareForRequestedTrack(UUID())
        tracker.handleSeek(to: 90, duration: 100)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(statistics.incrementCount == 1)
    }

    @Test("seek 回到开头后可再次计数")
    func rewindBelowBoundaryAllowsRecount() async throws {
        let statistics = MockTrackerStatisticsManager()
        let tracker = PlaybackStatisticsTracker(statisticsManager: statistics)

        tracker.prepareForRequestedTrack(UUID())
        tracker.evaluate(currentTime: 81, duration: 100)
        tracker.handleSeek(to: 0.5, duration: 100)
        tracker.evaluate(currentTime: 81, duration: 100)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(statistics.incrementCount == 2)
    }

    @Test("同曲重新请求会重置会话")
    func prepareForRequestedTrackResetsSameTrack() async throws {
        let statistics = MockTrackerStatisticsManager()
        let tracker = PlaybackStatisticsTracker(statisticsManager: statistics)
        let trackID = UUID()

        tracker.prepareForRequestedTrack(trackID)
        tracker.evaluate(currentTime: 81, duration: 100)
        tracker.prepareForRequestedTrack(trackID)
        tracker.evaluate(currentTime: 81, duration: 100)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(statistics.incrementCount == 2)
    }

    @Test("gapless 切到新曲会重置会话")
    func synchronizeObservedTrackResetsForNewTrack() async throws {
        let statistics = MockTrackerStatisticsManager()
        let tracker = PlaybackStatisticsTracker(statisticsManager: statistics)

        tracker.prepareForRequestedTrack(UUID())
        tracker.evaluate(currentTime: 81, duration: 100)
        tracker.synchronizeObservedTrack(UUID())
        tracker.evaluate(currentTime: 81, duration: 100)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(statistics.incrementCount == 2)
    }

    @Test("无效时长不计数")
    func ignoresInvalidDuration() async throws {
        let statistics = MockTrackerStatisticsManager()
        let tracker = PlaybackStatisticsTracker(statisticsManager: statistics)

        tracker.prepareForRequestedTrack(UUID())
        tracker.evaluate(currentTime: 81, duration: 0)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(statistics.incrementCount == 0)
    }

    @Test("支持自定义 reset boundary")
    func supportsInjectedResetBoundary() async throws {
        let statistics = MockTrackerStatisticsManager()
        let tracker = PlaybackStatisticsTracker(
            statisticsManager: statistics,
            playCountThreshold: 0.8,
            resetBoundary: 0.1
        )

        tracker.prepareForRequestedTrack(UUID())
        tracker.evaluate(currentTime: 81, duration: 100)
        tracker.handleSeek(to: 0.5, duration: 100)
        tracker.evaluate(currentTime: 81, duration: 100)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(statistics.incrementCount == 1)
    }
}

@MainActor
private final class MockTrackerStatisticsManager: StatisticsManagerProtocol {
    private(set) var incrementCount = 0

    func incrementTodayPlayCount() async {
        incrementCount += 1
    }

    func fetchAggregatedStats(period: StatPeriod) async -> [DailyStatItem] {
        []
    }

    func fetchRecentStatistics(days: Int) async -> [DailyStatItem] {
        []
    }

    func cleanupOldData(keepDays: Int) {}
}
