//
//  AudioEngineIntegrationTests.swift
//  Me2TuneTests
//
//  Real SFBAudioEngine playback using generated silent audio, with no library dependencies.
//

import AppKit
import AVFoundation
import Foundation
import SFBAudioEngine
import Testing
@testable import Me2Tune

@MainActor
@Suite("SFBAudioEngine 0.14 实际播放", .serialized)
struct AudioEngineIntegrationTests {
    @Test("暂停跳转、连续跳转及原地跳转均确认实际位置")
    func pausedAndRapidSeeking() async throws {
        let track = try makeSilentTrack(seconds: 4)
        defer { try? FileManager.default.removeItem(at: track.url) }
        let spy = AudioCoreSpy()
        let core = AudioPlayerCore()
        core.delegate = spy
        #expect(await core.loadTrack(track))
        core.setVolume(0)
        core.play()
        defer { core.pause() }
        #expect(await waitUntil { core.getCurrentPlaybackTime() > 0.05 })
        core.pause()
        core.seek(to: 1)
        #expect(await waitUntil { spy.seekTimes.count == 1 })
        #expect(abs((spy.seekTimes.last ?? -1) - 1) < 0.02)
        #expect(!core.isPlaying)
        core.seek(to: 1)
        #expect(await waitUntil { spy.seekTimes.count == 2 })
        core.seek(to: 2)
        core.seek(to: 3)
        #expect(await waitUntil { abs((spy.seekTimes.last ?? -1) - 3) < 0.02 })
        #expect(!core.isPlaying)
        let count = spy.seekTimes.count
        core.seek(to: .nan)
        core.seek(to: -1)
        try await Task.sleep(for: .milliseconds(80))
        #expect(spy.seekTimes.count == count)
        #expect(spy.errors.isEmpty)
    }

    @Test("播放中跳转保持播放且越界跳转被限制到末帧")
    func playingAndClampedSeeking() async throws {
        let track = try makeSilentTrack(seconds: 4)
        defer { try? FileManager.default.removeItem(at: track.url) }
        let spy = AudioCoreSpy()
        let core = AudioPlayerCore()
        core.delegate = spy
        #expect(await core.loadTrack(track))
        core.setVolume(0)
        core.play()
        defer { core.pause() }
        #expect(await waitUntil { core.getCurrentPlaybackTime() > 0.05 })
        core.seek(to: 1)
        #expect(await waitUntil { !spy.seekTimes.isEmpty })
        #expect(core.isPlaying)
        core.pause()
        core.seek(to: 100)
        #expect(await waitUntil { spy.seekTimes.count == 2 })
        let last = try #require(spy.seekTimes.last)
        #expect(last < 4 && last > 3.99)
        #expect(!core.isPlaying)
    }

    @Test("同格式和不同采样率的短音频顺序切换并结束", arguments: [44_100.0, 48_000.0])
    func shortTrackTransition(nextSampleRate: Double) async throws {
        let first = try makeSilentTrack(seconds: 0.25)
        let next = try makeSilentTrack(seconds: 0.25, sampleRate: nextSampleRate)
        defer {
            try? FileManager.default.removeItem(at: first.url)
            try? FileManager.default.removeItem(at: next.url)
        }
        let spy = AudioCoreSpy()
        let core = AudioPlayerCore()
        core.delegate = spy
        #expect(await core.loadTrack(first))
        #expect(await core.enqueueTrack(next))
        core.setVolume(0)
        core.play()
        defer { core.pause() }
        #expect(await waitUntil { spy.endCount == 1 })
        #expect(spy.nowPlayingIDs == [first.id, next.id])
        #expect(spy.decodedIDs == [first.id, next.id])
        #expect(!core.isPlaying)
        #expect(spy.errors.isEmpty)
    }

    @Test("手动切歌后旧引擎事件不能覆盖新曲目")
    func manualSwitchDiscardsOldEvents() async throws {
        let first = try makeSilentTrack(seconds: 0.1)
        let next = try makeSilentTrack(seconds: 2)
        defer {
            try? FileManager.default.removeItem(at: first.url)
            try? FileManager.default.removeItem(at: next.url)
        }
        let spy = AudioCoreSpy()
        let core = AudioPlayerCore()
        core.delegate = spy
        #expect(await core.loadTrack(first))
        core.setVolume(0)
        core.play()
        core.prepareForTrackSwitch()
        #expect(await core.loadTrack(next))
        spy.nowPlayingIDs.removeAll()
        core.play()
        defer { core.pause() }
        #expect(await waitUntil { core.getCurrentPlaybackTime() > 0.15 })
        #expect(core.currentTrack?.id == next.id)
        #expect(spy.nowPlayingIDs.allSatisfy { $0 == next.id })
        #expect(spy.endCount == 0)
    }

    @Test("自动预加载连续三首短音频，不重复播放")
    func automaticThreeTrackPlayback() async throws {
        let tracks = try (0..<3).map { _ in try makeSilentTrack(seconds: 0.15) }
        defer { for track in tracks { try? FileManager.default.removeItem(at: track.url) } }
        let spy = AudioCoreSpy()
        let core = AudioPlayerCore()
        core.delegate = spy
        spy.onDecoded = { [weak core] track in
            guard let index = tracks.firstIndex(where: { $0.id == track.id }), index + 1 < tracks.count else { return }
            Task { @MainActor in _ = await core?.enqueueTrack(tracks[index + 1]) }
        }
        #expect(await core.loadTrack(tracks[0]))
        core.setVolume(0)
        core.play()
        defer { core.pause() }
        #expect(await waitUntil { spy.endCount == 1 })
        #expect(spy.nowPlayingIDs == tracks.map(\.id))
        #expect(spy.decodedIDs == tracks.map(\.id))
    }

    @Test("同曲的三个播放实例连续循环")
    func repeatedPlaybackInstances() async throws {
        let track = try makeSilentTrack(seconds: 0.15)
        defer { try? FileManager.default.removeItem(at: track.url) }
        let spy = AudioCoreSpy()
        let core = AudioPlayerCore()
        core.delegate = spy
        var completed = 0
        spy.onDecoded = { [weak core] item in
            completed += 1
            if completed < 3 { Task { @MainActor in _ = await core?.enqueueTrack(item) } }
        }
        #expect(await core.loadTrack(track))
        core.setVolume(0)
        core.play()
        defer { core.pause() }
        #expect(await waitUntil { spy.endCount == 1 })
        #expect(spy.nowPlayingIDs == Array(repeating: track.id, count: 3))
        #expect(spy.decodedIDs.count == 3)
    }

    @Test("预加载损坏文件不终止当前曲目，可继续入队后继")
    func corruptedPreloadDoesNotStopCurrentTrack() async throws {
        let first = try makeSilentTrack(seconds: 1)
        let bad = try makeSilentTrack(seconds: 0.2)
        let next = try makeSilentTrack(seconds: 0.2)
        defer {
            for item in [first, bad, next] { try? FileManager.default.removeItem(at: item.url) }
        }
        try Data([82, 73, 70, 70, 4, 0, 0, 0, 87, 65, 86, 69]).write(to: bad.url)
        let spy = AudioCoreSpy()
        let core = AudioPlayerCore()
        core.delegate = spy
        #expect(await core.loadTrack(first))
        #expect(await core.enqueueTrack(bad))
        core.setVolume(0)
        core.play()
        defer { core.pause() }
        #expect(await waitUntil { !spy.failures.isEmpty })
        #expect(spy.failures.first?.0 == bad.id)
        #expect(spy.failures.first?.1 == false)
        #expect(core.isPlaying)
        #expect(core.currentTrack?.id == first.id)
        #expect(await core.enqueueTrack(next))
        #expect(await waitUntil { spy.endCount == 1 })
        #expect(spy.nowPlayingIDs == [first.id, next.id])
    }

    @Test("损坏 WAV 经异步解码中止回调报告失败")
    func corruptedAudioReportsDecoderFailure() async throws {
        let track = try makeSilentTrack(seconds: 1)
        defer { try? FileManager.default.removeItem(at: track.url) }
        try Data([82, 73, 70, 70, 4, 0, 0, 0, 87, 65, 86, 69]).write(to: track.url)
        let spy = AudioCoreSpy()
        let core = AudioPlayerCore()
        core.delegate = spy
        _ = await core.loadTrack(track)
        core.setVolume(0)
        core.play()
        defer { core.pause() }
        #expect(await waitUntil { !spy.failures.isEmpty })
        #expect(spy.failures.first?.0 == track.id)
        #expect(spy.failures.first?.1 == true)
        #expect(spy.endCount == 0)
    }

    @Test("M4A 分组不会覆盖内嵌歌词")
    func mp4GroupingDoesNotReplaceLyrics() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let output = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ])
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: 4410))
            buffer.frameLength = 4410
            for channel in 0..<Int(buffer.format.channelCount) {
                buffer.floatChannelData?[channel].initialize(repeating: 0, count: Int(buffer.frameLength))
            }
            try output.write(from: buffer)
        }
        let audioFile = try SFBAudioEngine.AudioFile(readingPropertiesAndMetadataFrom: url)
        audioFile.metadata.lyrics = "[00:00.00]Expected lyrics"
        audioFile.metadata.grouping = "Different grouping text"
        try audioFile.writeMetadata()
        let reader = FileMetadataReader()
        let result = await reader.metadata(for: url, includingArtworkData: false)
        #expect(result?.lyricsText == "[00:00.00]Expected lyrics")
    }

    private func makeSilentTrack(seconds: Double, sampleRate: Double = 44_100) throws -> AudioTrack {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
        let frames = AVAudioFrameCount(seconds * sampleRate)
        do {
            let output = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
            buffer.frameLength = frames
            for channel in 0..<2 {
                buffer.floatChannelData?[channel].initialize(repeating: 0, count: Int(frames))
            }
            try output.write(from: buffer)
        }
        return AudioTrack(id: UUID(), url: url, title: url.lastPathComponent,
                          artist: nil, albumTitle: nil, duration: seconds, format: .unknown, bookmark: nil)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < .seconds(5) {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

@MainActor
private final class AudioCoreSpy: AudioPlayerCoreDelegate {
    var seekTimes: [TimeInterval] = []
    var nowPlayingIDs: [UUID] = []
    var decodedIDs: [UUID] = []
    var endCount = 0
    var errors: [Error] = []
    var failures: [(UUID, Bool)] = []
    var onDecoded: ((AudioTrack) -> Void)?
    func playerCoreDidUpdatePlaybackState(_ isPlaying: Bool) {}
    func playerCoreDidUpdateTime(currentTime: TimeInterval, duration: TimeInterval) {}
    func playerCoreDidLoadTrack(_ track: AudioTrack, artwork: NSImage?) {}
    func playerCoreDidEncounterError(_ error: Error) { errors.append(error) }
    func playerCoreDidConfirmSeek(to time: TimeInterval) { seekTimes.append(time) }
    func playerCoreDecodingFailed(for track: AudioTrack, isCurrent: Bool) { failures.append((track.id, isCurrent)) }
    func playerCoreDidReachEnd() { endCount += 1 }
    func playerCoreDecodingComplete(for track: AudioTrack) {
        decodedIDs.append(track.id)
        onDecoded?(track)
    }
    func playerCoreNowPlayingChanged(to track: AudioTrack?) {
        if let track { nowPlayingIDs.append(track.id) }
    }
}
