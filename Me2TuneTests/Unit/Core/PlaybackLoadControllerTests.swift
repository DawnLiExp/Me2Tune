//
//  PlaybackLoadControllerTests.swift
//  Me2TuneTests
//
//  Unit tests for isolated playback load, failure recovery, gapless, and statistics behavior.
//

import AppKit
import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("PlaybackLoadController 单元测试")
struct PlaybackLoadControllerTests {
    private func makeController(
        tracks: [AudioTrack],
        playerCore: MockLoadPlayerCore,
        repeatMode: RepeatMode = .off,
        onPause: @escaping @MainActor () -> Void = {}
    ) throws -> (controller: PlaybackLoadController, stateManager: PlaybackStateManager, registry: FailedTrackRegistry, statistics: MockLoadStatisticsManager) {
        let dataService = try createTestDataService()
        let playlistManager = PlaylistManager(dataService: dataService)
        let collectionManager = CollectionManager(dataService: dataService)
        let stateManager = PlaybackStateManager(
            playlistManager: playlistManager,
            collectionManager: collectionManager,
            dataService: dataService
        )

        let album = Album(
            id: UUID(),
            name: "Test Album",
            folderURL: nil,
            tracks: tracks
        )
        stateManager.switchToAlbum(album)

        let statistics = MockLoadStatisticsManager()
        let effectsController = PlaybackEffectsController(statisticsManager: statistics)
        let registry = FailedTrackRegistry()
        let persistenceController = PlaybackPersistenceController(
            saveHandler: {},
            volumeApplyHandler: { _ in }
        )

        let controller = PlaybackLoadController(
            playerCore: playerCore,
            stateManager: stateManager,
            registry: registry,
            persistenceController: persistenceController,
            effectsController: effectsController,
            repeatModeProvider: { repeatMode },
            onPause: onPause
        )

        return (controller, stateManager, registry, statistics)
    }

    @Test("loadAndPlay 成功后设置索引并调用 play")
    func testLoadAndPlaySuccessSetsIndexAndPlays() async throws {
        let tracks = makeTracks(count: 3)
        let playerCore = MockLoadPlayerCore()
        let (controller, stateManager, _, _) = try makeController(
            tracks: tracks,
            playerCore: playerCore
        )

        controller.loadAndPlay(at: 1)

        let loaded = await waitUntil {
            stateManager.currentTrackIndex == 1 && playerCore.playCallCount == 1
        }

        #expect(loaded)
        #expect(playerCore.loadTrackCallIDs == [tracks[1].id])
    }

    @Test("首曲加载失败后标记 failed 并跳到下一首")
    func testLoadFailureMarksFailedAndSkips() async throws {
        let tracks = makeTracks(count: 3)
        let playerCore = MockLoadPlayerCore()
        playerCore.loadResults[tracks[0].id] = false
        playerCore.loadResults[tracks[1].id] = true

        let (controller, _, registry, _) = try makeController(
            tracks: tracks,
            playerCore: playerCore
        )

        controller.loadAndPlay(at: 0)

        let skipped = await waitUntil {
            playerCore.loadTrackCallIDs.count >= 2
        }

        #expect(skipped)
        #expect(playerCore.loadTrackCallIDs.prefix(2) == [tracks[0].id, tracks[1].id])
        #expect(registry.isMarked(tracks[0].id))
    }

    @Test("所有曲目均失败后触发 onPause")
    func testAllFailedTracksTriggerPause() async throws {
        let tracks = makeTracks(count: 2)
        let playerCore = MockLoadPlayerCore()
        for track in tracks {
            playerCore.loadResults[track.id] = false
        }

        var pauseCallCount = 0
        let (controller, _, _, _) = try makeController(
            tracks: tracks,
            playerCore: playerCore,
            onPause: { pauseCallCount += 1 }
        )

        controller.loadAndPlay(at: 0)

        let paused = await waitUntil {
            pauseCallCount == 1
        }

        #expect(paused)
        #expect(playerCore.loadTrackCallIDs == [tracks[0].id, tracks[1].id])
    }

    @Test("repeat one 下加载失败直接停止且不跳转")
    func testRepeatOneFailureStopsWithoutSkipping() async throws {
        let tracks = makeTracks(count: 3)
        let playerCore = MockLoadPlayerCore()
        playerCore.loadResults[tracks[0].id] = false

        var pauseCallCount = 0
        let (controller, _, _, _) = try makeController(
            tracks: tracks,
            playerCore: playerCore,
            repeatMode: .one,
            onPause: { pauseCallCount += 1 }
        )

        controller.loadAndPlay(at: 0)

        let paused = await waitUntil {
            pauseCallCount == 1
        }

        #expect(paused)
        #expect(playerCore.loadTrackCallIDs == [tracks[0].id])
    }

    @Test("gapless 已处理时 handleEndOfTrack 不重复加载")
    func testHandleEndOfTrackSkipsWhenGaplessAlreadyHandled() async throws {
        let tracks = makeTracks(count: 3)
        let playerCore = MockLoadPlayerCore()
        let (controller, stateManager, _, _) = try makeController(
            tracks: tracks,
            playerCore: playerCore
        )

        controller.loadAndPlay(at: 0)

        let loadedFirst = await waitUntil {
            playerCore.loadTrackCallIDs.count == 1
        }

        #expect(loadedFirst)

        controller.trackIndexBeforeGapless = 0
        stateManager.setCurrentTrack(id: tracks[1].id)

        controller.handleEndOfTrack()
        try? await Task.sleep(for: .milliseconds(80))

        #expect(playerCore.loadTrackCallIDs.count == 1)
    }

    @Test("80% 阈值只计数一次")
    func testPlayCountTriggersOnlyOnceAtThreshold() async throws {
        let tracks = makeTracks(count: 1)
        let playerCore = MockLoadPlayerCore()
        let (controller, _, _, statistics) = try makeController(
            tracks: tracks,
            playerCore: playerCore
        )

        controller.loadAndPlay(at: 0)
        let loaded = await waitUntil {
            playerCore.playCallCount == 1
        }

        #expect(loaded)

        controller.handleProgressTick(time: 79, duration: 100)
        #expect(statistics.incrementCount == 0)

        controller.handleProgressTick(time: 81, duration: 100)
        let countedOnce = await waitUntil {
            statistics.incrementCount == 1
        }

        #expect(countedOnce)

        controller.handleProgressTick(time: 90, duration: 100)
        try? await Task.sleep(for: .milliseconds(80))

        #expect(statistics.incrementCount == 1)
    }

    @Test("切换新曲目后统计标记重置并可再次计数")
    func testPlayCountResetsOnTrackChange() async throws {
        let tracks = makeTracks(count: 2)
        let playerCore = MockLoadPlayerCore()
        let (controller, _, _, statistics) = try makeController(
            tracks: tracks,
            playerCore: playerCore
        )

        controller.loadAndPlay(at: 0)
        let loadedFirst = await waitUntil {
            playerCore.playCallCount == 1
        }

        #expect(loadedFirst)

        controller.handleProgressTick(time: 81, duration: 100)
        let firstCounted = await waitUntil {
            statistics.incrementCount == 1
        }

        #expect(firstCounted)

        controller.loadAndPlay(at: 1)
        let loadedSecond = await waitUntil {
            playerCore.loadTrackCallIDs.count == 2
        }

        #expect(loadedSecond)

        controller.handleProgressTick(time: 81, duration: 100)
        let secondCounted = await waitUntil {
            statistics.incrementCount == 2
        }

        #expect(secondCounted)
    }

    @Test("回到开头后统计标记清除并允许重新计数")
    func testPlayCountResetsAfterRewindToStart() async throws {
        let tracks = makeTracks(count: 1)
        let playerCore = MockLoadPlayerCore()
        let (controller, _, _, statistics) = try makeController(
            tracks: tracks,
            playerCore: playerCore
        )

        controller.loadAndPlay(at: 0)
        let loaded = await waitUntil {
            playerCore.playCallCount == 1
        }

        #expect(loaded)

        controller.handleProgressTick(time: 81, duration: 100)
        let firstCounted = await waitUntil {
            statistics.incrementCount == 1
        }

        #expect(firstCounted)

        controller.handleProgressTick(time: 0.5, duration: 100)
        controller.handleProgressTick(time: 81, duration: 100)

        let recounted = await waitUntil {
            statistics.incrementCount == 2
        }

        #expect(recounted)
    }

    private func makeTracks(count: Int) -> [AudioTrack] {
        (0..<count).map { index in
            AudioTrack(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/load_controller_track_\(index).mp3"),
                title: "Track \(index)",
                artist: nil,
                albumTitle: nil,
                duration: 120,
                format: .unknown,
                bookmark: nil
            )
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

@MainActor
private final class MockLoadPlayerCore: AudioPlayerCoreProtocol {
    weak var delegate: (any AudioPlayerCoreDelegate)?
    var isPlaying = false
    var repeatMode: RepeatMode = .off

    var loadResults: [UUID: Bool] = [:]
    private(set) var loadTrackCallIDs: [UUID] = []
    private(set) var enqueueTrackCallIDs: [UUID] = []
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0

    func loadTrack(_ track: AudioTrack) async -> Bool {
        loadTrackCallIDs.append(track.id)
        return loadResults[track.id] ?? true
    }

    func enqueueTrack(_ track: AudioTrack) async -> Bool {
        enqueueTrackCallIDs.append(track.id)
        return true
    }

    func play() {
        isPlaying = true
        playCallCount += 1
    }

    func pause() {
        isPlaying = false
        pauseCallCount += 1
    }

    func seek(to time: TimeInterval) {}

    func setVolume(_ volume: Double) {}

    func prepareForTrackSwitch() {}

    func getCurrentPlaybackTime() -> TimeInterval {
        0
    }

    func updateDockIcon(_ artwork: NSImage?) {}
}

@MainActor
private final class MockLoadStatisticsManager: StatisticsManagerProtocol {
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
