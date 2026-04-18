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

    @Test("自动切歌后过期时长回调不会覆盖当前曲目时长")
    func testStaleDurationUpdateDoesNotOverrideCurrentTrackDuration() async throws {
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

        let trackA = AudioTrack(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/test_track_a.mp3"),
            title: "Track A",
            artist: nil,
            albumTitle: nil,
            duration: 277,
            format: .unknown,
            bookmark: nil
        )
        let trackB = AudioTrack(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/test_track_b.mp3"),
            title: "Track B",
            artist: nil,
            albumTitle: nil,
            duration: 385,
            format: .unknown,
            bookmark: nil
        )

        coordinator.playAlbum(makeAlbum(with: [trackA, trackB]), startAt: 1)

        let loadedSecond = await waitUntil {
            coordinator.playbackStateManager.currentTrackIndex == 1
        }
        #expect(loadedSecond)

        coordinator.playerCoreDidLoadTrack(trackB, artwork: nil)
        #expect(coordinator.duration == 385)

        coordinator.playerCoreDidUpdateTime(currentTime: 10, duration: 277)
        #expect(coordinator.duration == 385)
    }

    @Test("跨来源切换到专辑时加载完成前不出现空曲目")
    func testPlayAlbumKeepsTargetTrackVisibleBeforeLoadCompletes() async throws {
        let dataService = try createTestDataService()
        for i in 0..<2 {
            let track = SDTrack.makeSample(title: "Playlist \(i)", urlString: "file:///tmp/playlist-\(i).mp3")
            track.isInPlaylist = true
            track.playlistOrder = i
            dataService.insert(track)
        }
        try dataService.save()

        let collectionManager = CollectionManager(dataService: dataService)
        let playerCore = MockAudioPlayerCore()
        playerCore.loadDelay = .milliseconds(200)
        let statistics = MockStatisticsManager()
        let coordinator = PlaybackCoordinator(
            collectionManager: collectionManager,
            dataService: dataService,
            statisticsManager: statistics,
            playerCore: playerCore
        )

        coordinator.playPlaylistTrack(at: 0)
        let playlistLoaded = await waitUntil {
            coordinator.playbackStateManager.currentTrackIndex == 0 && playerCore.playCallCount == 1
        }
        #expect(playlistLoaded)

        let albumTracks = makeTracks(count: 3)
        let album = makeAlbum(with: albumTracks)

        coordinator.playAlbum(album, startAt: 1)
        try? await Task.sleep(for: .milliseconds(20))

        #expect(coordinator.playbackStateManager.playingSource == .album(album.id))
        #expect(coordinator.playbackStateManager.currentTrack?.id == albumTracks[1].id)
        #expect(coordinator.playbackStateManager.currentTrackIndex == 1)

        let albumLoaded = await waitUntil {
            playerCore.loadTrackCallIDs.suffix(1).first == albumTracks[1].id && playerCore.playCallCount == 2
        }
        #expect(albumLoaded)
    }

    @Test("seek 到 80% 会触发一次播放统计")
    func testSeekBeyondThresholdIncrementsStatistics() async throws {
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

        let track = AudioTrack(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/test_seek_track.mp3"),
            title: "Seek Track",
            artist: nil,
            albumTitle: nil,
            duration: 100,
            format: .unknown,
            bookmark: nil
        )

        coordinator.playAlbum(makeAlbum(with: [track]), startAt: 0)

        let loaded = await waitUntil {
            coordinator.playbackStateManager.currentTrackIndex == 0
        }
        #expect(loaded)

        coordinator.playerCoreDidLoadTrack(track, artwork: nil)
        coordinator.seek(to: 80)

        let didCount = await waitUntil {
            statistics.incrementCount == 1
        }
        #expect(didCount)
    }

    @Test("自动切歌到新曲后可再次计数")
    func testAutoSwitchedTrackCanCountAgain() async throws {
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

        let tracks = [
            AudioTrack(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/test_track_a.mp3"),
                title: "Track A",
                artist: nil,
                albumTitle: nil,
                duration: 100,
                format: .unknown,
                bookmark: nil
            ),
            AudioTrack(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/test_track_b.mp3"),
                title: "Track B",
                artist: nil,
                albumTitle: nil,
                duration: 100,
                format: .unknown,
                bookmark: nil
            )
        ]

        coordinator.playAlbum(makeAlbum(with: tracks), startAt: 0)

        let loadedFirst = await waitUntil {
            coordinator.playbackStateManager.currentTrackIndex == 0
        }
        #expect(loadedFirst)

        coordinator.playerCoreDidLoadTrack(tracks[0], artwork: nil)
        coordinator.seek(to: 80)

        let firstCounted = await waitUntil {
            statistics.incrementCount == 1
        }
        #expect(firstCounted)

        coordinator.playerCoreNowPlayingChanged(to: tracks[1])
        coordinator.playerCoreDidLoadTrack(tracks[1], artwork: nil)
        coordinator.seek(to: 80)

        let secondCounted = await waitUntil {
            statistics.incrementCount == 2
        }
        #expect(secondCounted)
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
    let statisticsRevision = 0
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
    var loadDelay: Duration?
    private(set) var loadTrackCallIDs: [UUID] = []
    private(set) var enqueueTrackCallIDs: [UUID] = []
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0

    private var currentTime: TimeInterval = 0

    func loadTrack(_ track: AudioTrack) async -> Bool {
        loadTrackCallIDs.append(track.id)
        currentTime = 0
        if let loadDelay {
            try? await Task.sleep(for: loadDelay)
        }
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

    func updateDockIcon(_ artwork: NSImage?) {}
}
