//
//  PlaybackTimeSamplerTests.swift
//  Me2TuneTests
//
//  Unit tests for playback time sampling behavior.
//

import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("PlaybackTimeSampler 单元测试")
struct PlaybackTimeSamplerTests {
    @Test("未播放时不启动采样")
    func doesNotSampleWhenNotPlaying() async throws {
        var providerCallCount = 0
        var uiTickCount = 0
        var statisticsTickCount = 0

        let sampler = PlaybackTimeSampler(
            timeProvider: {
                providerCallCount += 1
                return TimeInterval(providerCallCount)
            },
            uiHandler: { _ in
                uiTickCount += 1
            },
            statisticsHandler: { _ in
                statisticsTickCount += 1
            },
            intervalResolver: Self.testInterval(for:)
        )
        defer { sampler.stop() }

        sampler.updateVisibilityState(.activeFocused)
        try? await Task.sleep(for: .milliseconds(140))

        #expect(providerCallCount == 0)
        #expect(uiTickCount == 0)
        #expect(statisticsTickCount == 0)
    }

    @Test("active 和 inactive 使用不同节拍")
    func usesDifferentIntervalsForActiveAndInactive() async throws {
        var uiTickCount = 0

        let sampler = PlaybackTimeSampler(
            timeProvider: { 1 },
            uiHandler: { _ in
                uiTickCount += 1
            },
            statisticsHandler: { _ in },
            intervalResolver: Self.testInterval(for:)
        )
        defer { sampler.stop() }

        sampler.updateVisibilityState(.activeFocused)
        sampler.updatePlaybackState(isPlaying: true)
        sampler.refreshNow()
        let activeBaseline = uiTickCount

        let activeTicked = await waitUntil {
            uiTickCount > activeBaseline
        }
        #expect(activeTicked)

        sampler.updateVisibilityState(.inactive)
        let beforeInactiveWindow = uiTickCount
        try? await Task.sleep(for: .milliseconds(45))
        #expect(uiTickCount == beforeInactiveWindow)

        let inactiveTicked = await waitUntil {
            uiTickCount > beforeInactiveWindow
        }
        #expect(inactiveTicked)
    }

    @Test("hidden 状态继续采样但不发布 UI")
    func hiddenContinuesStatisticsWithoutUIPublishing() async throws {
        var uiTickCount = 0
        var statisticsTickCount = 0

        let sampler = PlaybackTimeSampler(
            timeProvider: { 1 },
            uiHandler: { _ in
                uiTickCount += 1
            },
            statisticsHandler: { _ in
                statisticsTickCount += 1
            },
            intervalResolver: Self.testInterval(for:)
        )
        defer { sampler.stop() }

        sampler.updateVisibilityState(.hidden)
        sampler.updatePlaybackState(isPlaying: true)

        let sampled = await waitUntil {
            statisticsTickCount > 0
        }
        #expect(sampled)
        #expect(uiTickCount == 0)
    }

    @Test("miniVisible 状态采样并发布 UI")
    func miniVisibleSamplesAndPublishesUI() async throws {
        var uiTickCount = 0
        var statisticsTickCount = 0

        let sampler = PlaybackTimeSampler(
            timeProvider: { 1 },
            uiHandler: { _ in
                uiTickCount += 1
            },
            statisticsHandler: { _ in
                statisticsTickCount += 1
            },
            intervalResolver: Self.testInterval(for:)
        )
        defer { sampler.stop() }

        sampler.updateVisibilityState(.miniVisible)
        sampler.updatePlaybackState(isPlaying: true)

        let sampled = await waitUntil {
            uiTickCount > 0 && statisticsTickCount > 0
        }
        #expect(sampled)
    }

    @Test("miniHidden 状态继续采样但不发布 UI")
    func miniHiddenContinuesStatisticsWithoutUIPublishing() async throws {
        var uiTickCount = 0
        var statisticsTickCount = 0

        let sampler = PlaybackTimeSampler(
            timeProvider: { 1 },
            uiHandler: { _ in
                uiTickCount += 1
            },
            statisticsHandler: { _ in
                statisticsTickCount += 1
            },
            intervalResolver: Self.testInterval(for:)
        )
        defer { sampler.stop() }

        sampler.updateVisibilityState(.miniHidden)
        sampler.updatePlaybackState(isPlaying: true)

        let sampled = await waitUntil {
            statisticsTickCount > 0
        }
        #expect(sampled)
        #expect(uiTickCount == 0)
    }

    @Test("从隐藏切回可发布 UI 状态会立即刷新一次")
    func refreshesImmediatelyWhenReturningToUIPublishingState() async throws {
        let providedTimes: [TimeInterval] = [42, 43, 44]
        var providedIndex = 0
        var receivedUITimes: [TimeInterval] = []
        var receivedStatisticTimes: [TimeInterval] = []

        let sampler = PlaybackTimeSampler(
            timeProvider: {
                defer {
                    providedIndex = min(providedIndex + 1, providedTimes.count - 1)
                }
                return providedTimes[providedIndex]
            },
            uiHandler: { time in
                receivedUITimes.append(time)
            },
            statisticsHandler: { time in
                receivedStatisticTimes.append(time)
            },
            intervalResolver: Self.testInterval(for:)
        )
        defer { sampler.stop() }

        sampler.updatePlaybackState(isPlaying: true)
        sampler.updateVisibilityState(.hidden)

        let hiddenSampled = await waitUntil {
            !receivedStatisticTimes.isEmpty
        }
        #expect(hiddenSampled)
        #expect(receivedUITimes.isEmpty)

        sampler.updateVisibilityState(.activeFocused)
        #expect(receivedUITimes == [43])

        let hasFollowUpTick = await waitUntil {
            receivedUITimes.count >= 2
        }
        #expect(hasFollowUpTick)
    }

    @Test("停止采样后不会残留任务继续写入")
    func noResidualSamplingAfterStop() async throws {
        var statisticsTickCount = 0

        let sampler = PlaybackTimeSampler(
            timeProvider: { 1 },
            uiHandler: { _ in },
            statisticsHandler: { _ in
                statisticsTickCount += 1
            },
            intervalResolver: Self.testInterval(for:)
        )
        defer { sampler.stop() }

        sampler.updateVisibilityState(.activeFocused)
        sampler.updatePlaybackState(isPlaying: true)

        let started = await waitUntil { statisticsTickCount >= 2 }
        #expect(started)

        sampler.updatePlaybackState(isPlaying: false)
        let snapshot = statisticsTickCount
        try? await Task.sleep(for: .milliseconds(140))
        #expect(statisticsTickCount == snapshot)
    }

    @Test("统计处理接收的时间来自 timeProvider")
    func statisticsHandlerUsesProviderValue() async throws {
        var providerValue: TimeInterval = 0
        var captured: [TimeInterval] = []

        let sampler = PlaybackTimeSampler(
            timeProvider: {
                providerValue += 1
                return providerValue
            },
            uiHandler: { _ in },
            statisticsHandler: { time in
                captured.append(time)
            },
            intervalResolver: Self.testInterval(for:)
        )
        defer { sampler.stop() }

        sampler.updateVisibilityState(.activeFocused)
        sampler.updatePlaybackState(isPlaying: true)

        let collected = await waitUntil { captured.count >= 2 }
        #expect(collected)
        #expect(captured.prefix(2) == [1, 2])
    }

    @Test("非法间隔不会启动空转任务")
    func nonPositiveIntervalsDoNotStartSamplingTask() async throws {
        var statisticsTickCount = 0

        let sampler = PlaybackTimeSampler(
            timeProvider: { 1 },
            uiHandler: { _ in },
            statisticsHandler: { _ in
                statisticsTickCount += 1
            },
            intervalResolver: { _ in 0 }
        )
        defer { sampler.stop() }

        sampler.updateVisibilityState(.hidden)
        sampler.updatePlaybackState(isPlaying: true)
        try? await Task.sleep(for: .milliseconds(120))

        #expect(statisticsTickCount == 0)
    }

    private static func testInterval(for state: WindowStateMonitor.WindowVisibilityState) -> TimeInterval {
        switch state {
        case .activeFocused:
            0.03
        case .inactive:
            0.07
        case .hidden, .miniVisible, .miniHidden:
            0.05
        }
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        interval: Duration = .milliseconds(10),
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < timeout {
            if condition() {
                return true
            }
            try? await Task.sleep(for: interval)
        }
        return condition()
    }
}
