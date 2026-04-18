//
//  ColdStartFlashBugConditionTests.swift
//  Me2TuneTests
//
//  Bug 条件探索性测试 — 冷启动恢复期间不显示 "no_track"
//
//  **Validates: Requirements 1.1, 1.2, 1.3, 2.1, 2.2, 2.3**
//
//  此测试编码了期望行为：冷启动时存在已保存的播放会话快照，
//  恢复尚未完成时，UI 应能区分"真实无曲目"和"恢复中"两种状态。
//  修复后 PlayerViewModel 提供 isRestoring 属性，UI 据此决定是否渲染 no_track。
//  测试验证：isRestoring == true 期间，修复后的 UI 逻辑不会显示 no_track。
//

import AppKit
import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("冷启动闪烁 Bug 条件探索性测试")
struct ColdStartFlashBugConditionTests {

    // MARK: - Helpers

    /// 创建隔离的 PlaybackSessionStore（独立 UserDefaults，避免污染）
    private func makeIsolatedSessionStore() -> PlaybackSessionStore {
        let suiteName = "ColdStartFlashTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return PlaybackSessionStore(defaults: defaults)
    }

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

        let sessionStore = makeIsolatedSessionStore()
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
        let stateManager = PlaybackStateManager(
            playlistManager: playlistManager,
            collectionManager: collectionManager,
            dataService: dataService,
            sessionStore: sessionStore
        )

        let playerCore = StubAudioPlayerCore()
        let coordinator = PlaybackCoordinator(
            collectionManager: collectionManager,
            dataService: dataService,
            statisticsManager: StubStatisticsManager(),
            playerCore: playerCore
        )

        return (coordinator, sessionStore, savedTrackID)
    }

    // MARK: - Bug Condition Test

    @Test("有快照时首帧状态：currentTrack == nil 且 isPlaylistLoaded == false")
    func testFirstFrameStateWithSavedSnapshot() throws {
        let dataService = try createTestDataService()
        let sessionStore = makeIsolatedSessionStore()

        // 创建 playlist 曲目
        for i in 0..<3 {
            let track = SDTrack.makeSample(
                title: "Track \(i)",
                urlString: "file:///tmp/first_frame_\(i).mp3"
            )
            track.isInPlaylist = true
            track.playlistOrder = i
            dataService.insert(track)
        }
        try dataService.save()

        let playlistManager = PlaylistManager(dataService: dataService)
        let savedTrackID = playlistManager.tracks[1].id

        // 保存快照 — 模拟上次退出前正在播放
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
        let coordinator = PlaybackCoordinator(
            collectionManager: collectionManager,
            dataService: dataService,
            statisticsManager: StubStatisticsManager(),
            playerCore: playerCore
        )

        // 模拟冷启动：创建 PlayerViewModel（init 中会启动异步 restoreState）
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

    @Test(
        "Bug 条件核心：有快照时 PlayerViewModel 缺乏恢复阶段标识，UI 无法区分'真实无曲目'和'恢复中'",
        .bug(
            "https://github.com/nicbus/Me2Tune/issues/cold-start-flash",
            "冷启动闪烁：currentTrack == nil 同时表示两种语义"
        )
    )
    func testNoRestorationPhaseDistinction() throws {
        let dataService = try createTestDataService()
        let sessionStore = makeIsolatedSessionStore()

        for i in 0..<3 {
            let track = SDTrack.makeSample(
                title: "Track \(i)",
                urlString: "file:///tmp/distinction_\(i).mp3"
            )
            track.isInPlaylist = true
            track.playlistOrder = i
            dataService.insert(track)
        }
        try dataService.save()

        let playlistManager = PlaylistManager(dataService: dataService)
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
        let coordinator = PlaybackCoordinator(
            collectionManager: collectionManager,
            dataService: dataService,
            statisticsManager: StubStatisticsManager(),
            playerCore: playerCore
        )

        let vm = PlayerViewModel(coordinator: coordinator)

        // === 首帧状态确认 ===
        #expect(vm.currentTrack == nil)
        #expect(vm.isPlaylistLoaded == false)

        // === Bug 条件核心断言 ===
        // 修复后的 UI 渲染逻辑：先检查 isRestoring，
        // 如果 isRestoring == true 且 currentTrack == nil，
        // 则不显示 "no_track"（保持静默/空白）。
        //
        // 修复前：UI 直接用 `currentTrack?.title ?? "no_track"`，
        // 无法区分"真实无曲目"和"恢复中"。
        //
        // 修复后：UI 先检查 `isRestoring`，恢复期间不渲染 no_track。
        // PlayerViewModel 提供了 isRestoring 属性，让 UI 能区分两种状态。

        // 验证 isRestoring 在有快照的首帧为 true
        #expect(
            vm.isRestoring == true,
            "有快照的冷启动首帧，isRestoring 应为 true"
        )

        // 模拟修复后的 UI 渲染逻辑（与 ControlSectionView 一致）：
        // 当 isRestoring == true 且 currentTrack == nil 时，不显示 no_track
        let wouldShowNoTrack: Bool
        if vm.isRestoring && vm.currentTrack == nil {
            wouldShowNoTrack = false  // 恢复期间保持静默，不渲染 no_track
        } else {
            wouldShowNoTrack = (vm.currentTrack?.title ?? "no_track") == "no_track"
        }

        // 在有快照的恢复期间，UI 不应该显示 no_track
        #expect(
            wouldShowNoTrack == false,
            """
            期望行为验证：冷启动有快照时，修复后的 UI 不再渲染 "no_track"。
            isRestoring == true 期间，UI 保持静默/空白状态，
            直到恢复完成后才按实际状态渲染。
            """
        )
    }
}

// MARK: - Minimal Stubs (仅用于此测试文件)

/// 最小化 AudioPlayerCore stub — 不执行任何实际音频操作
@MainActor
private final class StubAudioPlayerCore: AudioPlayerCoreProtocol {
    weak var delegate: (any AudioPlayerCoreDelegate)?
    var isPlaying = false
    var repeatMode: RepeatMode = .off

    func loadTrack(_ track: AudioTrack) async -> Bool { true }
    func enqueueTrack(_ track: AudioTrack) async -> Bool { true }
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func seek(to time: TimeInterval) {}
    func setVolume(_ volume: Double) {}
    func prepareForTrackSwitch() {}
    func getCurrentPlaybackTime() -> TimeInterval { 0 }
    func updateDockIcon(_ artwork: NSImage?) {}
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
