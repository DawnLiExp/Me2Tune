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
            playerCore: playerCore,
            defaults: try #require(UserDefaults(suiteName: "Me2TuneCoordinatorTests.\(UUID())"))
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
            playerCore: playerCore,
            defaults: try #require(UserDefaults(suiteName: "Me2TuneCoordinatorTests.\(UUID())"))
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
            playerCore: playerCore,
            defaults: try #require(UserDefaults(suiteName: "Me2TuneCoordinatorTests.\(UUID())"))
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
            playerCore: playerCore,
            defaults: try #require(UserDefaults(suiteName: "Me2TuneCoordinatorTests.\(UUID())"))
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
            playerCore: playerCore,
            defaults: try #require(UserDefaults(suiteName: "Me2TuneCoordinatorTests.\(UUID())"))
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
            playerCore: playerCore,
            defaults: try #require(UserDefaults(suiteName: "Me2TuneCoordinatorTests.\(UUID())"))
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
            playerCore: playerCore,
            defaults: try #require(UserDefaults(suiteName: "Me2TuneCoordinatorTests.\(UUID())"))
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
            playerCore: playerCore,
            defaults: try #require(UserDefaults(suiteName: "Me2TuneCoordinatorTests.\(UUID())"))
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

    @Test("跳转请求不提前计数；仅实际确认位置触发统计")
    func seekStatisticsWaitForConfirmation() async throws {
        let dataService = try createTestDataService()
        let collection = CollectionManager(dataService: dataService)
        let core = MockAudioPlayerCore()
        core.automaticallyConfirmsSeek = false
        let statistics = MockStatisticsManager()
        let coordinator = PlaybackCoordinator(collectionManager: collection, dataService: dataService,
                                               statisticsManager: statistics, playerCore: core)
        let track = AudioTrack(id: UUID(), url: URL(fileURLWithPath: "/tmp/confirmed.wav"), title: "Track",
                               artist: nil, albumTitle: nil, duration: 100, format: .unknown, bookmark: nil)
        coordinator.playAlbum(makeAlbum(with: [track]), startAt: 0)
        #expect(await waitUntil { core.playCallCount == 1 })
        coordinator.playerCoreDidLoadTrack(track, artwork: nil)
        coordinator.seek(to: 95)
        try await Task.sleep(for: .milliseconds(30))
        #expect(statistics.incrementCount == 0)
        core.confirmSeek(to: 70)
        try await Task.sleep(for: .milliseconds(30))
        #expect(statistics.incrementCount == 0)
        coordinator.seek(to: 95)
        core.confirmSeek(to: 85)
        #expect(await waitUntil { statistics.incrementCount == 1 })
    }

    @Test("随机只使用实际来源，切换来源保留开关并清除历史")
    func shuffleSourceIsolation() async throws {
        let (coordinator, core, _) = try playlistCoordinator(count: 4)
        coordinator.toggleShuffle()
        coordinator.playPlaylistTrack(at: 1)
        #expect(await waitUntil { core.playCallCount == 1 })
        let playlistIDs = Set(coordinator.playlistManager.tracks.map(\.id))
        #expect(Set(coordinator.playbackOrder.ids) == playlistIDs)
        let album = makeAlbum(with: makeTracks(count: 3))
        coordinator.playAlbum(album, startAt: 2)
        #expect(await waitUntil { core.playCallCount == 2 })
        #expect(coordinator.isShuffling)
        #expect(coordinator.playbackOrder.history == [album.tracks[2].id])
        #expect(Set(coordinator.playbackOrder.ids) == Set(album.tracks.map(\.id)))
        coordinator.clearPlaylist()
        #expect(Set(coordinator.playbackOrder.ids) == Set(album.tracks.map(\.id)))
        #expect(coordinator.isPlaying)
    }

    @Test("连续切换随机和循环保留同一已提交后继，手动切歌立即执行新模式")
    func submittedSuccessorSurvivesModes() async throws {
        let (coordinator, core, _) = try playlistCoordinator(count: 4)
        let tracks = coordinator.playlistManager.tracks
        coordinator.playPlaylistTrack(at: 0)
        #expect(await waitUntil { core.playCallCount == 1 })
        coordinator.playerCoreDecodingComplete(for: tracks[0])
        #expect(await waitUntil { core.enqueueTrackCallIDs.count == 1 })
        coordinator.toggleShuffle()
        coordinator.repeatMode = .one
        coordinator.toggleShuffle()
        coordinator.toggleShuffle()
        #expect(core.enqueueTrackCallIDs == [tracks[1].id])
        #expect(core.loadTrackCallIDs == [tracks[0].id])
        coordinator.playerCoreNowPlayingChanged(to: tracks[1])
        #expect(coordinator.playbackOrder.currentID == tracks[1].id)
        coordinator.next()
        #expect(await waitUntil { core.playCallCount == 2 })
        #expect(core.loadTrackCallIDs.last != tracks[1].id)
        #expect(coordinator.playbackStateManager.playingSource == .playlist)
    }

    @Test("删除已提交后继恢复进度，删除当前曲目与清空使旧播放失效")
    func deletionStopsQueuedPlayback() async throws {
        let (coordinator, core, _) = try playlistCoordinator(count: 3)
        let tracks = coordinator.playlistManager.tracks
        coordinator.playPlaylistTrack(at: 0)
        #expect(await waitUntil { core.playCallCount == 1 })
        coordinator.playerCoreDecodingComplete(for: tracks[0])
        #expect(await waitUntil { core.enqueueTrackCallIDs.count == 1 })
        core.confirmSeek(to: 30)
        coordinator.pause()
        coordinator.removeTrackFromPlaylist(at: 1)
        #expect(await waitUntil { core.loadTrackCallIDs.count == 2 })
        #expect(core.loadTrackCallIDs == [tracks[0].id, tracks[0].id])
        #expect(core.getCurrentPlaybackTime() == 30)
        #expect(!core.isPlaying)
        #expect(!coordinator.playbackOrder.ids.contains(tracks[1].id))
        coordinator.removeTrackFromPlaylist(at: 0)
        #expect(coordinator.playbackStateManager.currentTrackID == nil)
        #expect(!core.isPlaying)
        coordinator.clearPlaylist()
        #expect(coordinator.playbackOrder.ids.isEmpty)
    }

    @Test("切歌等待时排序通过 ID 提交，连续下一首仅最后请求生效")
    func rapidNavigationAndReorder() async throws {
        let (coordinator, core, _) = try playlistCoordinator(count: 4)
        let tracks = coordinator.playlistManager.tracks
        coordinator.playPlaylistTrack(at: 0)
        #expect(await waitUntil { core.playCallCount == 1 })
        core.loadDelay = .milliseconds(80)
        coordinator.next()
        coordinator.next()
        coordinator.moveTrackInPlaylist(from: 2, to: 0)
        #expect(await waitUntil { core.playCallCount == 2 })
        #expect(coordinator.playbackStateManager.currentTrackID == tracks[2].id)
        #expect(core.loadTrackCallIDs.last == tracks[2].id)
        #expect(coordinator.playbackOrder.history == [tracks[0].id, tracks[2].id])
    }

    @Test("只记住随机开关，首次播放加载曲目且不提前自动播放")
    func shufflePreferenceAndFirstPlay() async throws {
        let (coordinator, core, defaults) = try playlistCoordinator(count: 3)
        #expect(!coordinator.isShuffling)
        coordinator.toggleShuffle()
        #expect(defaults.bool(forKey: "shuffleEnabled"))
        #expect(core.playCallCount == 0)
        coordinator.play()
        #expect(await waitUntil { core.playCallCount == 1 })
        #expect(core.loadTrackCallIDs.count == 1)
        let data = try createTestDataService()
        let restored = PlaybackCoordinator(collectionManager: CollectionManager(dataService: data),
                                           dataService: data, statisticsManager: MockStatisticsManager(),
                                           playerCore: MockAudioPlayerCore(), defaults: defaults)
        #expect(restored.isShuffling)
        #expect(restored.playbackOrder.history.isEmpty)
    }

    @Test("恢复保持暂停且随机历史重新建立，加载期间明确播放不丢失", arguments: [false, true])
    func restoredSessionStartsFreshRound(playWhileRestoring: Bool) async throws {
        let (original, core, defaults) = try playlistCoordinator(count: 3)
        original.toggleShuffle()
        original.playPlaylistTrack(at: 1)
        #expect(await waitUntil { core.playCallCount == 1 })
        original.saveState()
        let data = try createTestDataService()
        let tracks = original.playlistManager.tracks
        for (index, track) in tracks.enumerated() {
            let stored = SDTrack(from: track)
            stored.isInPlaylist = true
            stored.playlistOrder = index
            data.insert(stored)
        }
        try data.save()
        let restoredCore = MockAudioPlayerCore()
        let restored = PlaybackCoordinator(collectionManager: CollectionManager(dataService: data),
                                           dataService: data, statisticsManager: MockStatisticsManager(),
                                           playerCore: restoredCore, defaults: defaults)
        if playWhileRestoring {
            restoredCore.heldLoadIDs = [tracks[1].id]
            defer { restoredCore.releaseAllLoads() }
            let restoration = Task { await restored.restoreState() }
            #expect(await waitUntil { restoredCore.loadTrackCallIDs.count == 1 })
            restored.play()
            restoredCore.releaseLoads(for: tracks[1].id)
            #expect(await restoration.value)
        } else {
            #expect(await restored.restoreState())
            #expect(restoredCore.playCallCount == 0)
            #expect(restored.playbackOrder.history.isEmpty)
            restored.play()
        }
        #expect(restored.playbackStateManager.currentTrackID == tracks[1].id)
        #expect(restored.isShuffling)
        #expect(restoredCore.playCallCount == 1)
        #expect(restored.playbackOrder.history == [tracks[1].id])
        #expect(restoredCore.loadTrackCallIDs == [tracks[1].id])
    }

    @Test("加载开始前后切换随机再连续下一首，按最后请求前进", arguments: [false, true])
    func modeSwitchDuringRapidNext(waitForLoad: Bool) async throws {
        let (coordinator, core, _) = try playlistCoordinator(count: 4)
        let tracks = coordinator.playlistManager.tracks
        coordinator.playPlaylistTrack(at: 0)
        #expect(await waitUntil { core.playCallCount == 1 })
        core.heldLoadIDs = [tracks[1].id, tracks[2].id]
        defer { core.releaseAllLoads() }
        coordinator.next()
        if waitForLoad { #expect(await waitUntil { core.loadTrackCallIDs.count == 2 }) }
        coordinator.toggleShuffle()
        coordinator.toggleShuffle()
        coordinator.next()
        #expect(coordinator.playbackOrder.requested?.id == tracks[2].id)
        #expect(await waitUntil { core.loadTrackCallIDs.last == tracks[2].id })
        core.releaseLoads(for: tracks[2].id)
        #expect(await waitUntil { core.playCallCount == 2 })
        core.releaseLoads(for: tracks[1].id)
        #expect(await waitUntil { core.completedLoadIDs.count == core.loadTrackCallIDs.count })
        #expect(coordinator.playbackStateManager.currentTrackID == tracks[2].id)
        #expect(coordinator.playbackOrder.history == [tracks[0].id, tracks[2].id])
        #expect(core.playCallCount == 2)
    }

    @Test("切换来源加载前后重复按播放仍保留点选曲目", arguments: [false, true], [false, true])
    func playDuringSourceLoad(shuffling: Bool, toAlbum: Bool) async throws {
        let (coordinator, core, _) = try playlistCoordinator(count: 4)
        let album = makeAlbum(with: makeTracks(count: 4))
        if shuffling { coordinator.toggleShuffle() }
        if toAlbum { coordinator.playPlaylistTrack(at: 0) }
        else { coordinator.playAlbum(album) }
        #expect(await waitUntil { core.playCallCount == 1 })
        let target = toAlbum ? album.tracks[2] : coordinator.playlistManager.tracks[2]
        core.heldLoadIDs = [target.id]
        defer { core.releaseAllLoads() }
        if toAlbum { coordinator.playAlbum(album, startAt: 2) }
        else { coordinator.playPlaylistTrack(at: 2) }
        coordinator.play()
        #expect(coordinator.playbackOrder.requested?.id == target.id)
        #expect(await waitUntil { core.loadTrackCallIDs.count == 2 })
        coordinator.pause()
        coordinator.play()
        core.releaseLoads(for: target.id)
        #expect(await waitUntil { core.playCallCount == 2 })
        #expect(core.loadTrackCallIDs.count == 2)
        #expect(coordinator.playbackStateManager.currentTrackID == target.id)
        #expect(coordinator.playbackStateManager.playingSource == (toAlbum ? .album(album.id) : .playlist))
        #expect(coordinator.playbackOrder.history == [target.id])
    }

    @Test("回退加载期间删除更早历史，确认后仍能沿原路径前进")
    func deleteHistoryDuringPendingBack() async throws {
        let (coordinator, core, _) = try playlistCoordinator(count: 4)
        let tracks = coordinator.playlistManager.tracks
        coordinator.toggleShuffle()
        coordinator.playPlaylistTrack(at: 0)
        #expect(await waitUntil { core.playCallCount == 1 })
        for count in 2...4 {
            coordinator.next()
            #expect(await waitUntil { core.playCallCount == count })
        }
        let history = coordinator.playbackOrder.history
        let previousID = history[2]
        core.heldLoadIDs = [previousID]
        defer { core.releaseAllLoads() }
        coordinator.previous()
        #expect(await waitUntil { core.loadTrackCallIDs.count == 5 })
        coordinator.removeTrackFromPlaylist(at: 0)
        core.releaseLoads(for: previousID)
        #expect(await waitUntil { core.playCallCount == 5 })
        #expect(coordinator.playbackOrder.history == history.filter { $0 != tracks[0].id })
        coordinator.next()
        #expect(await waitUntil { core.playCallCount == 6 })
        #expect(coordinator.playbackStateManager.currentTrackID == history.last)
    }

    private func playlistCoordinator(count: Int) throws -> (PlaybackCoordinator, MockAudioPlayerCore, UserDefaults) {
        let data = try createTestDataService()
        for (index, track) in makeTracks(count: count).enumerated() {
            let stored = SDTrack(from: track)
            stored.isInPlaylist = true
            stored.playlistOrder = index
            data.insert(stored)
        }
        try data.save()
        let defaults = try #require(UserDefaults(suiteName: "Me2TuneShuffleTests.\(UUID())"))
        let core = MockAudioPlayerCore()
        let coordinator = PlaybackCoordinator(collectionManager: CollectionManager(dataService: data),
                                              dataService: data, statisticsManager: MockStatisticsManager(),
                                              playerCore: core, defaults: defaults)
        return (coordinator, core, defaults)
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

    private var loadedTrack: AudioTrack?
    var loadResults: [UUID: Bool] = [:]
    var loadDelay: Duration?
    var heldLoadIDs: Set<UUID> = []
    private var heldLoads: [UUID: [CheckedContinuation<Void, Never>]] = [:]
    private(set) var completedLoadIDs: [UUID] = []

    func releaseLoads(for id: UUID) {
        heldLoadIDs.remove(id)
        for continuation in heldLoads.removeValue(forKey: id) ?? [] { continuation.resume() }
    }

    func releaseAllLoads() {
        for id in heldLoadIDs { releaseLoads(for: id) }
    }

    var automaticallyConfirmsSeek = true
    private(set) var loadTrackCallIDs: [UUID] = []
    private(set) var enqueueTrackCallIDs: [UUID] = []
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0

    private var currentTime: TimeInterval = 0

    func loadTrack(_ track: AudioTrack, startingAt time: TimeInterval = 0) async -> Bool {
        loadedTrack = track
        loadTrackCallIDs.append(track.id)
        currentTime = time
        if let loadDelay {
            try? await Task.sleep(for: loadDelay)
        }
        if heldLoadIDs.contains(track.id) {
            await withCheckedContinuation { heldLoads[track.id, default: []].append($0) }
        }
        completedLoadIDs.append(track.id)
        return loadResults[track.id] ?? true
    }

    func enqueueTrack(_ track: AudioTrack) -> AudioEnqueueResult {
        enqueueTrackCallIDs.append(track.id)
        return .enqueued(track.id)
    }

    func play() {
        isPlaying = true
        playCallCount += 1
        delegate?.playerCoreDidUpdatePlaybackState(true)
        if let loadedTrack {
            self.loadedTrack = nil
            delegate?.playerCoreNowPlayingChanged(to: loadedTrack)
        }
    }

    func pause() {
        isPlaying = false
        pauseCallCount += 1
        delegate?.playerCoreDidUpdatePlaybackState(false)
    }

    func seek(to time: TimeInterval) {
        if automaticallyConfirmsSeek { confirmSeek(to: time) }
    }

    func confirmSeek(to time: TimeInterval) {
        currentTime = time
        delegate?.playerCoreDidConfirmSeek(to: time)
    }

    func setVolume(_ volume: Double) {}

    func prepareForTrackSwitch() {
        currentTime = 0
        loadedTrack = nil
        isPlaying = false
        delegate?.playerCoreDidUpdatePlaybackState(false)
    }

    func getCurrentPlaybackTime() -> TimeInterval {
        currentTime
    }

    func updateDockIcon(_ artwork: NSImage?) {}
}
