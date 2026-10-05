//
//  PlaybackShuffleControllerTests.swift
//  Me2TuneTests
//
//  Unit tests for PlaybackShuffleController.
//

import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("PlaybackShuffleController 单元测试")
struct PlaybackShuffleControllerTests {
    private func makeTrack(_ id: UUID) -> AudioTrack {
        AudioTrack(
            id: id,
            url: URL(fileURLWithPath: "/tmp/\(id.uuidString).mp3"),
            title: id.uuidString,
            artist: nil,
            albumTitle: nil,
            duration: 120,
            format: .unknown,
            bookmark: nil
        )
    }

    @Test("toggle 切换 shuffle 状态与队列初始化")
    func testToggleAndReshuffle() {
        let controller = PlaybackShuffleController()
        controller.isEnabled = false

        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let tracks = [makeTrack(id1), makeTrack(id2), makeTrack(id3)]

        // 切换为开启
        controller.toggle(tracks: tracks, currentTrackID: id1)
        #expect(controller.isEnabled)
        #expect(controller.upcomingIDs.count == 2)
        #expect(!controller.upcomingIDs.contains(id1))
        #expect(controller.upcomingIDs.contains(id2))
        #expect(controller.upcomingIDs.contains(id3))

        // 切换为关闭
        controller.toggle(tracks: tracks, currentTrackID: id1)
        #expect(!controller.isEnabled)
        #expect(controller.upcomingIDs.isEmpty)
        #expect(controller.historyIDs.isEmpty)
    }

    @Test("consumeNextValidTrackID 顺序消费与历史入栈")
    func testConsumeNextValidTrackID() {
        let controller = PlaybackShuffleController()
        controller.isEnabled = true

        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let tracks = [makeTrack(id1), makeTrack(id2), makeTrack(id3)]

        controller.reshuffle(tracks: tracks, currentTrackID: id1)
        #expect(controller.upcomingIDs.count == 2)

        // 消费第 1 首
        let next1 = controller.consumeNextValidTrackID(
            tracks: tracks,
            currentTrackID: id1,
            repeatMode: .off,
            failedIDs: []
        )
        #expect(next1 != nil)
        #expect(next1 != id1)
        #expect(controller.historyIDs == [id1])
        #expect(controller.upcomingIDs.count == 1)

        // 消费第 2 首
        let next2 = controller.consumeNextValidTrackID(
            tracks: tracks,
            currentTrackID: next1,
            repeatMode: .off,
            failedIDs: []
        )
        #expect(next2 != nil)
        #expect(next2 != next1)
        #expect(controller.historyIDs == [id1, next1!])
        #expect(controller.upcomingIDs.isEmpty)

        // 列表已耗尽且 repeatMode 为 off
        let next3 = controller.consumeNextValidTrackID(
            tracks: tracks,
            currentTrackID: next2,
            repeatMode: .off,
            failedIDs: []
        )
        #expect(next3 == nil)
    }

    @Test("consumeNextValidTrackID 过滤标记为失败的曲目")
    func testSkipFailedTracks() {
        let controller = PlaybackShuffleController()
        controller.isEnabled = true

        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let tracks = [makeTrack(id1), makeTrack(id2), makeTrack(id3)]

        controller.reshuffle(tracks: tracks, currentTrackID: id1)
        // 假设 id2 失败
        let next = controller.consumeNextValidTrackID(
            tracks: tracks,
            currentTrackID: id1,
            repeatMode: .off,
            failedIDs: [id2]
        )
        #expect(next == id3)
        #expect(controller.historyIDs == [id1])
    }

    @Test("repeatMode == .all 在耗尽时自动重新洗牌循环")
    func testRepeatAllRefill() {
        let controller = PlaybackShuffleController()
        controller.isEnabled = true

        let id1 = UUID()
        let id2 = UUID()
        let tracks = [makeTrack(id1), makeTrack(id2)]

        controller.reshuffle(tracks: tracks, currentTrackID: id1)
        #expect(controller.upcomingIDs == [id2])

        _ = controller.consumeNextValidTrackID(
            tracks: tracks,
            currentTrackID: id1,
            repeatMode: .all,
            failedIDs: []
        )
        #expect(controller.upcomingIDs.isEmpty)

        // 下一次应该重新洗牌并继续提供曲目
        let loopedNext = controller.consumeNextValidTrackID(
            tracks: tracks,
            currentTrackID: id2,
            repeatMode: .all,
            failedIDs: []
        )
        #expect(loopedNext == id1)
    }

    @Test("consumePreviousTrackID 回退到历史曲目并将当前曲目放回待播队首")
    func testConsumePreviousTrackID() {
        let controller = PlaybackShuffleController()
        controller.isEnabled = true

        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let tracks = [makeTrack(id1), makeTrack(id2), makeTrack(id3)]

        controller.reshuffle(tracks: tracks, currentTrackID: id1)

        let next1 = controller.consumeNextValidTrackID(
            tracks: tracks,
            currentTrackID: id1,
            repeatMode: .off,
            failedIDs: []
        )!

        // 当前播放为 next1，点击上一首应该回退到 id1
        let prev = controller.consumePreviousTrackID(
            tracks: tracks,
            currentTrackID: next1,
            failedIDs: []
        )
        #expect(prev == id1)
        #expect(controller.historyIDs.isEmpty)
        #expect(controller.upcomingIDs.first == next1)
    }

    @Test("handleTrackStarted 与 handleTracksRemoved / handleTracksAdded")
    func testTrackModifications() {
        let controller = PlaybackShuffleController()
        controller.isEnabled = true

        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let id4 = UUID()
        let tracks = [makeTrack(id1), makeTrack(id2), makeTrack(id3)]

        controller.reshuffle(tracks: tracks, currentTrackID: id1)

        // 手动切换到 id2
        controller.handleTrackStarted(newTrackID: id2, previousTrackID: id1, tracks: tracks)
        #expect(!controller.upcomingIDs.contains(id2))
        #expect(controller.historyIDs.contains(id1))

        // 添加新曲目 id4
        controller.handleTracksAdded(newTracks: [makeTrack(id4)])
        #expect(controller.upcomingIDs.contains(id4))

        // 删除曲目 id3
        controller.handleTracksRemoved(removedIDs: [id3])
        #expect(!controller.upcomingIDs.contains(id3))
    }
}
