//
//  ColdStartFlashBugConditionTests.swift
//  Me2TuneTests
//

import AppKit
import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("冷启动恢复期间的播放状态")
struct ColdStartFlashBugConditionTests {

    // MARK: - Helpers

    /// 创建带有 playlist 曲目的测试环境，并在 sessionStore 中保存快照
    private func setupWithSavedSession() throws -> (
        PlaybackCoordinator,
        PlaybackSessionStore,
        UUID  // savedTrackID
    ) {
        let dataService = try createTestDataService()

        // 创建 3 首 playlist 曲目
        var trackIDs: [UUID] = []
        for i in 0..<3 {
            let track = SDTrack.makeSample(
                title: "Playlist Track \(i)",
                urlString: "file:///tmp/cold_start_test_\(i).mp3"
            )
            track.isInPlaylist = true
            track.playlistOrder = i
            dataService.insert(track)
            trackIDs.append(track.stableId)
        }
        try dataService.save()

        let defaults = try #require(UserDefaults(suiteName: "ColdStartFlashTest.\(UUID())"))
        let sessionStore = PlaybackSessionStore(defaults: defaults)
        let playlistManager = PlaylistManager(dataService: dataService)

        // 模拟上次退出前正在播放第 2 首（index=1）
        let savedTrackID = playlistManager.tracks[1].id
        sessionStore.save(
            PlaybackSessionSnapshot(
                sourceKind: .playlist,
                currentTrackID: savedTrackID,
                albumID: nil,
                volume: 0.7
            )
        )

        let collectionManager = CollectionManager(dataService: dataService)
        let playerCore = StubAudioPlayerCore()
        let coordinator = makeTestPlaybackCoordinator(
            collectionManager: collectionManager,
            dataService: dataService,
            statisticsManager: StubStatisticsManager(),
            playerCore: playerCore, defaults: defaults
        )

        return (coordinator, sessionStore, savedTrackID)
    }

    @Test("有快照时首帧状态：currentTrack == nil 且 isPlaylistLoaded == false")
    func testFirstFrameStateWithSavedSnapshot() throws {
        let (coordinator, sessionStore, savedTrackID) = try setupWithSavedSession()
        let vm = PlayerViewModel(coordinator: coordinator)

        // === 首帧状态断言 ===
        // 在 restoreState() 完成前，首帧渲染时：
        #expect(vm.currentTrack == nil, "首帧 currentTrack 应为 nil（恢复尚未完成）")
        #expect(vm.isPlaylistLoaded == false, "首帧 isPlaylistLoaded 应为 false（恢复尚未完成）")

        // 确认快照确实存在
        let snapshot = sessionStore.load()
        #expect(snapshot != nil, "会话快照应存在")
        #expect(snapshot?.currentTrackID == savedTrackID, "快照中应保存了曲目 ID")
    }

    @Test("有快照时，首帧进入恢复状态并隐藏空曲目提示")
    func testSavedSessionStartsInRestoringState() throws {
        let (coordinator, _, _) = try setupWithSavedSession()
        let vm = PlayerViewModel(coordinator: coordinator)

        #expect(vm.currentTrack == nil)
        #expect(vm.isPlaylistLoaded == false)

        #expect(
            vm.isRestoring == true,
            "有快照的冷启动首帧，isRestoring 应为 true"
        )

        // 模拟 ControlSectionView 的标题选择。
        let wouldShowNoTrack: Bool
        if vm.isRestoring && vm.currentTrack == nil {
            wouldShowNoTrack = false  // 恢复期间保持静默，不渲染 no_track
        } else {
            wouldShowNoTrack = (vm.currentTrack?.title ?? "no_track") == "no_track"
        }

        #expect(wouldShowNoTrack == false, "恢复已保存会话时应隐藏空曲目提示")
    }
}

// MARK: - Minimal Stubs (仅用于此测试文件)

/// 最小化 AudioPlayerCore stub — 不执行任何实际音频操作
@MainActor
private final class StubAudioPlayerCore: AudioPlayerCoreProtocol {
    var canSeek = true
    weak var delegate: (any AudioPlayerCoreDelegate)?
    var isPlaying = false
    var repeatMode: RepeatMode = .off

    func loadTrack(_ track: AudioTrack, startingAt time: TimeInterval = 0) async -> Bool { true }
    func enqueueTrack(_ track: AudioTrack) -> AudioEnqueueResult { .enqueued(track.id) }
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func seek(to time: TimeInterval) {}
    func setVolume(_ volume: Double) {}
    func prepareForTrackSwitch() {}
    func getCurrentPlaybackTime() -> TimeInterval { 0 }
}

/// 最小化 StatisticsManager stub
@MainActor
private final class StubStatisticsManager: StatisticsManagerProtocol {
    let statisticsRevision = 0
    func incrementTodayPlayCount() async {}
    func fetchAggregatedStats(period: StatPeriod) async -> [DailyStatItem] { [] }
    func fetchRecentStatistics(days: Int) async -> [DailyStatItem] { [] }
    func cleanupOldData(keepDays: Int) {}
}
