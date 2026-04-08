//
//  PlaybackProgressControllerTests.swift
//  Me2TuneTests
//
//  Unit tests for playback progress polling controller.
//

import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("PlaybackProgressController 单元测试")
struct PlaybackProgressControllerTests {
    @Test("未播放时不启动轮询")
    func doesNotPollWhenNotPlaying() async throws {
        var providerCallCount = 0
        var tickCount = 0

        let controller = PlaybackProgressController(
            timeProvider: {
                providerCallCount += 1
                return TimeInterval(providerCallCount)
            },
            tickHandler: { _ in
                tickCount += 1
            },
            intervalResolver: Self.testInterval(for:)
        )
        defer { controller.stop() }

        controller.updateVisibilityState(.activeFocused)
        try? await Task.sleep(for: .milliseconds(140))

        #expect(providerCallCount == 0)
        #expect(tickCount == 0)
    }

    @Test("active/inactive 使用不同节拍")
    func usesDifferentIntervalsForActiveAndInactive() async throws {
        var tickCount = 0

        let controller = PlaybackProgressController(
            timeProvider: { 1 },
            tickHandler: { _ in
                tickCount += 1
            },
            intervalResolver: Self.testInterval(for:)
        )
        defer { controller.stop() }

        controller.updateVisibilityState(.activeFocused)
        controller.updatePlaybackState(isPlaying: true)
        controller.refreshNow()
        let activeBaseline = tickCount

        let activeTicked = await waitUntil {
            tickCount > activeBaseline
        }
        #expect(activeTicked)

        controller.updateVisibilityState(.inactive)
        let beforeInactiveWindow = tickCount
        try? await Task.sleep(for: .milliseconds(45))
        #expect(tickCount == beforeInactiveWindow)

        let inactiveTicked = await waitUntil {
            tickCount > beforeInactiveWindow
        }
        #expect(inactiveTicked)
    }

    @Test("hidden/mini 状态停止轮询")
    func stopsPollingInHiddenAndMiniStates() async throws {
        var tickCount = 0

        let controller = PlaybackProgressController(
            timeProvider: { 1 },
            tickHandler: { _ in
                tickCount += 1
            },
            intervalResolver: Self.testInterval(for:)
        )
        defer { controller.stop() }

        controller.updateVisibilityState(.activeFocused)
        controller.updatePlaybackState(isPlaying: true)
        let started = await waitUntil { tickCount > 0 }
        #expect(started)

        controller.updateVisibilityState(.hidden)
        let hiddenSnapshot = tickCount
        try? await Task.sleep(for: .milliseconds(120))
        #expect(tickCount == hiddenSnapshot)

        controller.updateVisibilityState(.miniVisible)
        let miniSnapshot = tickCount
        try? await Task.sleep(for: .milliseconds(120))
        #expect(tickCount == miniSnapshot)
    }

    @Test("从隐藏切回可见会立即刷新一次")
    func refreshesImmediatelyWhenReturningVisible() async throws {
        let providedTimes: [TimeInterval] = [42, 43, 43]
        var providedIndex = 0
        var receivedTimes: [TimeInterval] = []

        let controller = PlaybackProgressController(
            timeProvider: {
                defer {
                    providedIndex = min(providedIndex + 1, providedTimes.count - 1)
                }
                return providedTimes[providedIndex]
            },
            tickHandler: { time in
                receivedTimes.append(time)
            },
            intervalResolver: Self.testInterval(for:)
        )
        defer { controller.stop() }

        controller.updatePlaybackState(isPlaying: true)
        controller.updateVisibilityState(.hidden)
        #expect(receivedTimes.isEmpty)

        controller.updateVisibilityState(.activeFocused)
        #expect(receivedTimes == [42])

        let hasFollowUpTick = await waitUntil {
            receivedTimes.count >= 2
        }
        #expect(hasFollowUpTick)
        #expect(receivedTimes.last == 43)
    }

    @Test("停止轮询后不会残留任务继续写入")
    func noResidualPollingAfterStop() async throws {
        var tickCount = 0

        let controller = PlaybackProgressController(
            timeProvider: { 1 },
            tickHandler: { _ in
                tickCount += 1
            },
            intervalResolver: Self.testInterval(for:)
        )
        defer { controller.stop() }

        controller.updateVisibilityState(.activeFocused)
        controller.updatePlaybackState(isPlaying: true)

        let started = await waitUntil { tickCount >= 2 }
        #expect(started)

        controller.updatePlaybackState(isPlaying: false)
        let snapshot = tickCount
        try? await Task.sleep(for: .milliseconds(140))
        #expect(tickCount == snapshot)
    }

    @Test("tickHandler 接收的时间来自 timeProvider")
    func tickUsesProviderValue() async throws {
        var providerValue: TimeInterval = 0
        var captured: [TimeInterval] = []

        let controller = PlaybackProgressController(
            timeProvider: {
                providerValue += 1
                return providerValue
            },
            tickHandler: { time in
                captured.append(time)
            },
            intervalResolver: Self.testInterval(for:)
        )
        defer { controller.stop() }

        controller.updateVisibilityState(.activeFocused)
        controller.updatePlaybackState(isPlaying: true)

        let collected = await waitUntil { captured.count >= 2 }
        #expect(collected)
        #expect(captured.prefix(2) == [1, 2])
    }

    @Test("可在 tick 中完成统计阈值翻转")
    func tickCanDrivePlayCountThresholdFlip() async throws {
        let providedTimes: [TimeInterval] = [79, 81]
        var providedIndex = 0
        var hasMarkedPlayCount = false
        let duration: TimeInterval = 100

        let controller = PlaybackProgressController(
            timeProvider: {
                defer {
                    providedIndex = min(providedIndex + 1, providedTimes.count - 1)
                }
                return providedTimes[providedIndex]
            },
            tickHandler: { time in
                if hasMarkedPlayCount, time < 1 {
                    hasMarkedPlayCount = false
                }
                if !hasMarkedPlayCount, time >= duration * 0.8 {
                    hasMarkedPlayCount = true
                }
            },
            intervalResolver: Self.testInterval(for:)
        )
        defer { controller.stop() }

        controller.refreshNow()
        #expect(hasMarkedPlayCount == false)

        controller.refreshNow()
        #expect(hasMarkedPlayCount == true)
    }

    private static func testInterval(for state: WindowStateMonitor.WindowVisibilityState) -> TimeInterval {
        switch state {
        case .activeFocused:
            return 0.03
        case .inactive:
            return 0.08
        case .hidden, .miniVisible, .miniHidden:
            return 0.03
        }
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        interval: Duration = .milliseconds(5),
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
