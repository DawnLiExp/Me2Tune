//
//  PlaybackDecoderQueueTests.swift
//  Me2TuneTests
//
//  Verifies playback-instance identity and deferred preloading notifications.
//

import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("解码器播放实例")
struct PlaybackDecoderQueueTests {
    private func track() -> AudioTrack {
        AudioTrack(id: UUID(), url: URL(fileURLWithPath: "/tmp/queue.wav"), title: "Track",
                   artist: nil, albumTitle: nil, duration: 10, format: .unknown, bookmark: nil)
    }

    @Test("预加载解码完成需等到成为当前曲目，且每个实例只通知一次")
    func earlyCompletionAndDeduplication() {
        var queue = PlaybackDecoderQueue()
        let a = DecoderReference(NSObject()), b = DecoderReference(NSObject())
        let first = track(), next = track()
        queue.register(a, track: first, current: true)
        queue.register(b, track: next, current: false)
        queue.decoded(b.id)
        let result20 = queue.takeCompletedCurrentTrack() == nil
        #expect(result20)
        queue.decoded(a.id)
        let result22 = queue.takeCompletedCurrentTrack()?.id == first.id
        #expect(result22)
        queue.decoded(a.id)
        let result24 = queue.takeCompletedCurrentTrack() == nil
        #expect(result24)
        let result25 = queue.activate(b.id)?.id == next.id
        #expect(result25)
        let result26 = queue.takeCompletedCurrentTrack()?.id == next.id
        #expect(result26)
        let result27 = queue.takeCompletedCurrentTrack() == nil
        #expect(result27)
    }

    @Test("同曲循环的解码器实例独立计数")
    func sameTrackDifferentInstances() {
        var queue = PlaybackDecoderQueue()
        let a = DecoderReference(NSObject()), b = DecoderReference(NSObject())
        let item = track()
        queue.register(a, track: item, current: true)
        queue.register(b, track: item, current: false)
        queue.decoded(a.id)
        let result38 = queue.takeCompletedCurrentTrack() != nil
        #expect(result38)
        queue.decoded(b.id)
        _ = queue.activate(b.id)
        let result41 = queue.takeCompletedCurrentTrack() != nil
        #expect(result41)
    }

    @Test("切歌后的旧完成、激活、取消和失败事件不能影响新曲目")
    func staleEvents() {
        var queue = PlaybackDecoderQueue()
        let old = DecoderReference(NSObject()), new = DecoderReference(NSObject())
        queue.register(old, track: track(), current: true)
        let generation = queue.generation
        queue.reset()
        let next = track()
        queue.register(new, track: next, current: true)
        queue.decoded(old.id)
        queue.rendered(old.id)
        #expect(queue.generation != generation)
        let result56 = queue.activate(old.id) == nil
        #expect(result56)
        let result57 = queue.remove(old.id) == nil
        #expect(result57)
        let result58 = queue.takeCompletedCurrentTrack() == nil
        #expect(result58)
        let result59 = !queue.takeEnd()
        #expect(result59)
        #expect(queue.currentTrack?.id == next.id)
    }

    @Test("预加载失败只移除预加载实例；重复失败无效")
    func removeQueuedFailure() {
        var queue = PlaybackDecoderQueue()
        let a = DecoderReference(NSObject()), b = DecoderReference(NSObject())
        let first = track(), next = track()
        queue.register(a, track: first, current: true)
        queue.register(b, track: next, current: false)
        let result = queue.remove(b.id)
        #expect(result?.track.id == next.id)
        #expect(result?.isCurrent == false)
        let result73 = queue.remove(b.id) == nil
        #expect(result73)
        #expect(queue.currentTrack?.id == first.id)
    }

    @Test("结束通知需要渲染完成且没有后继；重复结束无效")
    func endRequiresCompletedRendering() {
        var queue = PlaybackDecoderQueue()
        let a = DecoderReference(NSObject()), b = DecoderReference(NSObject())
        queue.register(a, track: track(), current: true)
        queue.decoded(a.id)
        let result83 = !queue.takeEnd()
        #expect(result83)
        queue.rendered(a.id)
        queue.register(b, track: track(), current: false)
        let result86 = !queue.takeEnd()
        #expect(result86)
        _ = queue.activate(b.id)
        queue.rendered(b.id)
        let result89 = queue.takeEnd()
        #expect(result89)
        let result90 = !queue.takeEnd()
        #expect(result90)
    }
}
