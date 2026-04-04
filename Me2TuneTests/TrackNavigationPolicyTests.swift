//
//  TrackNavigationPolicyTests.swift
//  Me2TuneTests
//
//  Unit tests for pure playback navigation policy.
//

import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("TrackNavigationPolicy 单元测试")
struct TrackNavigationPolicyTests {
    @Test("nextIndex - off/all/one")
    func testNextIndexMatrix() {
        #expect(TrackNavigationPolicy.nextIndex(after: 1, count: 3, repeatMode: .off) == 2)
        #expect(TrackNavigationPolicy.nextIndex(after: 2, count: 3, repeatMode: .off) == nil)
        #expect(TrackNavigationPolicy.nextIndex(after: 2, count: 3, repeatMode: .all) == 0)
        #expect(TrackNavigationPolicy.nextIndex(after: 1, count: 3, repeatMode: .all) == 2)
        #expect(TrackNavigationPolicy.nextIndex(after: 1, count: 3, repeatMode: .one) == 1)
    }

    @Test("previousIndex - off/all/one")
    func testPreviousIndexMatrix() {
        #expect(TrackNavigationPolicy.previousIndex(before: 1, count: 3, repeatMode: .off) == 0)
        #expect(TrackNavigationPolicy.previousIndex(before: 0, count: 3, repeatMode: .off) == nil)
        #expect(TrackNavigationPolicy.previousIndex(before: 0, count: 3, repeatMode: .all) == 2)
        #expect(TrackNavigationPolicy.previousIndex(before: 2, count: 3, repeatMode: .all) == 1)
        #expect(TrackNavigationPolicy.previousIndex(before: 2, count: 3, repeatMode: .one) == 2)
    }

    @Test("nextValidIndex - 跳过失败并支持 all 回绕")
    func testNextValidIndex() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let tracks = [makeTrack(id1), makeTrack(id2), makeTrack(id3)]

        #expect(
            TrackNavigationPolicy.nextValidIndex(
                after: 0,
                tracks: tracks,
                repeatMode: .off,
                failedIDs: [id2]
            ) == 2
        )

        #expect(
            TrackNavigationPolicy.nextValidIndex(
                after: 2,
                tracks: tracks,
                repeatMode: .all,
                failedIDs: []
            ) == 0
        )

        #expect(
            TrackNavigationPolicy.nextValidIndex(
                after: 0,
                tracks: tracks,
                repeatMode: .all,
                failedIDs: [id1, id2, id3],
                maxAttempts: tracks.count
            ) == nil
        )
    }

    @Test("previousValidIndex - 仅向前线性查找")
    func testPreviousValidIndex() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let tracks = [makeTrack(id1), makeTrack(id2), makeTrack(id3)]

        #expect(TrackNavigationPolicy.previousValidIndex(before: 3, tracks: tracks, failedIDs: [id3]) == 1)
        #expect(TrackNavigationPolicy.previousValidIndex(before: 1, tracks: tracks, failedIDs: [id1]) == nil)
    }

    @Test("isGaplessAlreadyHandled")
    func testGaplessHandledGuard() {
        #expect(TrackNavigationPolicy.isGaplessAlreadyHandled(currentIndex: 2, expectedNext: 2))
        #expect(!TrackNavigationPolicy.isGaplessAlreadyHandled(currentIndex: 1, expectedNext: 2))
        #expect(!TrackNavigationPolicy.isGaplessAlreadyHandled(currentIndex: nil, expectedNext: 2))
    }

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
}
