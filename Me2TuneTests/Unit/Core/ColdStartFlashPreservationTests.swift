//
//  ColdStartFlashPreservationTests.swift
//  Me2TuneTests
//
//  保持性测试 — 非恢复阶段行为不变
//
//  **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**
//
//  遵循 observation-first 方法论：先在未修复代码上观察非 bug 输入的行为，
//  然后编写确定性单元测试捕获观察到的基线行为。
//  这些测试在未修复代码上应 PASS — 确认基线行为已正确捕获。
//

import AppKit
import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("冷启动闪烁 — 保持性测试（非恢复阶段行为不变）")
struct ColdStartFlashPreservationTests {

    // MARK: - Helpers

    /// 创建隔离的 PlaybackSessionStore（独立 UserDefaults，避免污染）
    private func makeIsolatedSessionStore() -> PlaybackSessionStore {
        let suiteName = "PreservationTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return PlaybackSessionStore(defaults: defaults)
    }

    /// 创建带有 playlist 曲目的 DataService，返回 (dataService, trackIDs)
    private func makeDataServiceWithPlaylistTracks(count: Int = 3) throws -> (DataService, [UUID]) {
        let dataService = try createTestDataService()
        var trackIDs: [UUID] = []
        for i in 0..<count {
            let track = SDTrack.makeSample(
                title: "Preservation Track \(i)",
                urlString: "file:///tmp/preservation_\(i).mp3"
            )
            track.isInPlaylist = true
            track.playlistOrder = i
            dataService.insert(track)
            trackIDs.append(track.stableId)
        }
        try dataService.save()
        return (dataService, trackIDs)
    }

    // MARK: - Test 1: 无快照时（首次安装）

    /// **Validates: Requirements 3.1**
    ///
    /// 观察：无会话快照时（首次安装），`currentTrack == nil` 且 UI 应显示 "no_track"。
    /// 这是正确行为 — 首次安装确实没有曲目，no_track 是真实状态。
    @Test("首次安装（无快照）：currentTrack == nil，UI 正确显示 no_track")
    func testFreshInstallShowsNoTrack() throws {
        // 无快照的 sessionStore — 模拟首次安装
        let sessionStore = makeIsolatedSessionStore()

        // 确认无快照
        #expect(sessionStore.load() == nil, "首次安装不应有会话快照")

        // 创建空的 dataService（无 playlist 曲目）
        let dataService = try createTestDataService()
        let collectionManager = CollectionManager(dataService: dataService)
        let playerCore = StubAudioPlayerCore()
        let coordinator = PlaybackCoordinator(
            collectionManager: collectionManager,
            dataService: dataService,
            statisticsManager: StubStatisticsManager(),
            playerCore: playerCore
        )

        let vm = PlayerViewModel(coordinator: coordinator)

        // === 基线行为断言 ===
        // 无快照时，currentTrack 应为 nil — 这是真实的"无曲目"状态
        #expect(vm.currentTrack == nil, "首次安装 currentTrack 应为 nil")

        // 模拟 UI 渲染逻辑：ControlSectionView 的实际行为
        let displayTitle = vm.currentTrack?.title ?? "no_track"
        #expect(
            displayTitle == "no_track",
            "首次安装时 UI 应正确显示 no_track（这是真实空态，不是 bug）"
        )

        // 模拟封面渲染逻辑：artwork 为 nil 时应显示默认图标
        #expect(
            vm.currentArtwork == nil,
            "首次安装时 artwork 应为 nil，UI 应显示默认吉他图标（正确行为）"
        )
    }

    // MARK: - Test 2: 手动清空播放列表后

    /// **Validates: Requirements 3.3**
    ///
    /// 观察：手动清空播放列表后，`currentTrack == nil` 且 UI 应显示 "no_track"。
    /// 这是正确行为 — 用户主动清空了列表。
    @Test("清空播放列表后：currentTrack == nil，UI 正确显示 no_track")
    func testClearPlaylistShowsNoTrack() throws {
        let (dataService, _) = try makeDataServiceWithPlaylistTracks(count: 3)
        let sessionStore = makeIsolatedSessionStore()
        let collectionManager = CollectionManager(dataService: dataService)
        let playerCore = StubAudioPlayerCore()
        let coordinator = PlaybackCoordinator(
            collectionManager: collectionManager,
            dataService: dataService,
            statisticsManager: StubStatisticsManager(),
            playerCore: playerCore
        )

        let vm = PlayerViewModel(coordinator: coordinator)

        // 确认 playlist 有曲目
        #expect(vm.playlistManager.tracks.count == 3, "应有 3 首 playlist 曲目")

        // 手动清空播放列表
        vm.clearPlaylist()

        // === 基线行为断言 ===
        // 清空后 currentTrack 应为 nil
        #expect(vm.currentTrack == nil, "清空播放列表后 currentTrack 应为 nil")

        // playlist 应为空
        #expect(vm.playlistManager.isEmpty, "清空后 playlist 应为空")

        // 模拟 UI 渲染逻辑
        let displayTitle = vm.currentTrack?.title ?? "no_track"
        #expect(
            displayTitle == "no_track",
            "清空播放列表后 UI 应正确显示 no_track（用户主动清空，正确行为）"
        )
    }

    // MARK: - Test 3: 恢复失败后（保存的曲目已被删除）

    /// **Validates: Requirements 3.5**
    ///
    /// 观察：恢复失败时（保存的曲目已被删除），正确回退到 "no_track" 状态。
    /// 这是正确行为 — 保存的曲目不存在了，应回退到空态。
    @Test("恢复失败（曲目已删除）：回退到 no_track 状态")
    func testFailedRestoreFallsBackToNoTrack() async throws {
        let dataService = try createTestDataService()
        let sessionStore = makeIsolatedSessionStore()

        // 保存一个指向不存在曲目的快照（模拟曲目已被删除）
        let deletedTrackID = UUID()
        sessionStore.save(
            PlaybackSessionSnapshot(
                sourceKind: .playlist,
                currentTrackID: deletedTrackID,
                albumID: nil,
                volume: 0.7
            )
        )

        // 确认快照存在
        #expect(sessionStore.load() != nil, "快照应存在")

        // 创建 PlaybackStateManager 并执行恢复
        let playlistManager = PlaylistManager(dataService: dataService)
        let collectionManager = CollectionManager(dataService: dataService)
        let stateManager = PlaybackStateManager(
            playlistManager: playlistManager,
            collectionManager: collectionManager,
            dataService: dataService,
            sessionStore: sessionStore
        )

        // 执行恢复 — 因为 playlist 中没有匹配的曲目，恢复应失败
        let restored = await stateManager.restoreState()

        // === 基线行为断言 ===
        // 恢复失败：返回 nil
        #expect(restored == nil, "恢复应失败（曲目已被删除，playlist 中无匹配）")

        // 恢复失败后 currentTrack 应为 nil
        #expect(stateManager.currentTrack == nil, "恢复失败后 currentTrack 应为 nil")
        #expect(stateManager.currentTrackID == nil, "恢复失败后 currentTrackID 应为 nil")

        // 模拟 UI 渲染逻辑 — 恢复失败后应显示 no_track
        let displayTitle = stateManager.currentTrack?.title ?? "no_track"
        #expect(
            displayTitle == "no_track",
            "恢复失败后 UI 应正确回退到 no_track 状态（保存的曲目已不存在）"
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
    func incrementTodayPlayCount() async {}
    func fetchAggregatedStats(period: StatPeriod) async -> [DailyStatItem] { [] }
    func fetchRecentStatistics(days: Int) async -> [DailyStatItem] { [] }
    func cleanupOldData(keepDays: Int) {}
}
