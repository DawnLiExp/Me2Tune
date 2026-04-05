//
//  PlaybackCoordinatorTests.swift
//  Me2TuneTests
//
//  Unit tests for playback coordinator flow and edge cases.
//

import AppKit
import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("PlaybackCoordinator 单元测试")
struct PlaybackCoordinatorTests {
    @Test("failed track 自动跳过到下一首")
    func testFailedTrackAutoSkip() async throws {
        let dataService = try createTestDataService()
        let collectionManager = CollectionManager(dataService: dataService)
        let playerCore = MockAudioPlayerCore()
        let statistics = MockStatisticsManager()
        let coordinator = PlaybackCoordinator(
            collectionManager: collectionManager,
            dataService: dataService,
            statisticsManager: statistics,
            playerCore: playerCore
        )

        let tracks = makeTracks(count: 3)
        playerCore.loadResults[tracks[0].id] = false
        playerCore.loadResults[tracks[1].id] = true

        coordinator.playAlbum(makeAlbum(with: tracks), startAt: 0)

        let didSkip = await waitUntil {
            coordinator.playbackStateManager.currentTrackIndex == 1 && playerCore.loadTrackCallIDs.count >= 2
        }

        #expect(didSkip)
        #expect(playerCore.loadTrackCallIDs.prefix(2) == [tracks[0].id, tracks[1].id])
        #expect(coordinator.isTrackFailed(tracks[0].id))
    }

    @Test("repeat one 下加载失败会停止")
    func testRepeatOneFailureStops() async throws {
        let dataService = try createTestDataService()
        let collectionManager = CollectionManager(dataService: dataService)
        let playerCore = MockAudioPlayerCore()
        let statistics = MockStatisticsManager()
        let coordinator = PlaybackCoordinator(
            collectionManager: collectionManager,
            dataService: dataService,
            statisticsManager: statistics,
            playerCore: playerCore
        )

        let tracks = makeTracks(count: 1)
        playerCore.loadResults[tracks[0].id] = false

        coordinator.repeatMode = .one
        coordinator.playAlbum(makeAlbum(with: tracks), startAt: 0)

        let didPause = await waitUntil {
            playerCore.pauseCallCount > 0
        }

        #expect(didPause)
        #expect(playerCore.loadTrackCallIDs == [tracks[0].id])
    }

    @Test("repeat all 下 canGoPrevious/canGoNext 均为 true")
    func testCanGoPreviousAndNextInRepeatAll() async throws {
        let dataService = try createTestDataService()
        let collectionManager = CollectionManager(dataService: dataService)
        let playerCore = MockAudioPlayerCore()
        let statistics = MockStatisticsManager()
        let coordinator = PlaybackCoordinator(
            collectionManager: collectionManager,
            dataService: dataService,
            statisticsManager: statistics,
            playerCore: playerCore
        )

        let tracks = makeTracks(count: 2)
        coordinator.playAlbum(makeAlbum(with: tracks), startAt: 0)

        let loaded = await waitUntil {
            coordinator.playbackStateManager.currentTrackIndex == 0
        }
        #expect(loaded)

        coordinator.repeatMode = .all
        #expect(coordinator.canGoPrevious)
        #expect(coordinator.canGoNext)
    }

    @Test("gapless 已切换时 end 事件不重复跳转")
    func testGaplessEndDoesNotDoubleAdvance() async throws {
        let dataService = try createTestDataService()
        let collectionManager = CollectionManager(dataService: dataService)
        let playerCore = MockAudioPlayerCore()
        let statistics = MockStatisticsManager()
        let coordinator = PlaybackCoordinator(
            collectionManager: collectionManager,
            dataService: dataService,
            statisticsManager: statistics,
            playerCore: playerCore
        )

        let tracks = makeTracks(count: 3)
        coordinator.playAlbum(makeAlbum(with: tracks), startAt: 0)

        let loadedFirst = await waitUntil {
            coordinator.playbackStateManager.currentTrackIndex == 0 && playerCore.loadTrackCallIDs.count == 1
        }
        #expect(loadedFirst)

        coordinator.playerCoreDecodingComplete(for: tracks[0])
        let enqueued = await waitUntil {
            playerCore.enqueueTrackCallIDs == [tracks[1].id]
        }
        #expect(enqueued)

        coordinator.playerCoreNowPlayingChanged(to: tracks[1])
        #expect(coordinator.playbackStateManager.currentTrackIndex == 1)

        coordinator.playerCoreDidReachEnd()
        try? await Task.sleep(for: .milliseconds(80))

        #expect(playerCore.loadTrackCallIDs.count == 1)
    }

    private func makeTracks(count: Int) -> [AudioTrack] {
        (0..<count).map { index in
            AudioTrack(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/test_track_\(index).mp3"),
                title: "Track \(index)",
                artist: nil,
                albumTitle: nil,
                duration: 120,
                format: .unknown,
                bookmark: nil
            )
        }
    }

    private func makeAlbum(with tracks: [AudioTrack]) -> Album {
        Album(
            id: UUID(),
            name: "Test Album",
            folderURL: URL(fileURLWithPath: "/tmp/test_album"),
            tracks: tracks
        )
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
private final class MockStatisticsManager: StatisticsManagerProtocol {
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

@MainActor
private final class MockAudioPlayerCore: AudioPlayerCoreProtocol {
    weak var delegate: (any AudioPlayerCoreDelegate)?
    var isPlaying = false
    var repeatMode: RepeatMode = .off

    var loadResults: [UUID: Bool] = [:]
    private(set) var loadTrackCallIDs: [UUID] = []
    private(set) var enqueueTrackCallIDs: [UUID] = []
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0

    private var currentTime: TimeInterval = 0

    func loadTrack(_ track: AudioTrack) async -> Bool {
        loadTrackCallIDs.append(track.id)
        currentTime = 0
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

    func seek(to time: TimeInterval) {
        currentTime = time
    }

    func setVolume(_ volume: Double) {}

    func prepareForTrackSwitch() {
        currentTime = 0
    }

    func getCurrentPlaybackTime() -> TimeInterval {
        currentTime
    }

    func updateVisibilityState(_ state: WindowStateMonitor.WindowVisibilityState) {}

    func updateDockIcon(_ artwork: NSImage?) {}
}
