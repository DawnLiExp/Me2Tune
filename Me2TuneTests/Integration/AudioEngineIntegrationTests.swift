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
    @Test("Saving preloaded tags preserves playback and activation uses refreshed metadata", arguments: TrackTagServiceTests.names)
    func savePreloadedTags(_ name: String) async throws {
        let first = try makeSilentTrack(seconds: 4)
        let (url, service) = try TrackTagServiceTests().setup(name)
        defer {
            try? FileManager.default.removeItem(at: first.url)
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        if url.pathExtension == "m4a" {
            // Use the platform encoder for native playback; metadata-only fixtures also
            // contain very short ffmpeg streams that CoreAudio's callback reader rejects.
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
            let codec = name == "aac.m4a" ? kAudioFormatMPEG4AAC : kAudioFormatAppleLossless
            let output = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: codec,
                AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2])
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 13_230))
            buffer.frameLength = buffer.frameCapacity
            for channel in 0..<2 { buffer.floatChannelData?[channel].initialize(repeating: 0, count: Int(buffer.frameLength)) }
            try output.write(from: buffer)
        }
        let next = await AudioTrack(url: url)
        let data = try createTestDataService()
        for (index, track) in [first, next].enumerated() {
            let stored = SDTrack(from: track)
            stored.isInPlaylist = true; stored.playlistOrder = index
            data.insert(stored)
        }
        try data.save()
        let core = AudioPlayerCore()
        let coordinator = PlaybackCoordinator(collectionManager: CollectionManager(dataService: data),
            dataService: data, statisticsManager: EngineTestStatistics(), playerCore: core,
            defaults: try #require(UserDefaults(suiteName: "TagSaveEngine.\(UUID())")))
        coordinator.playPlaylistTrack(at: 0)
        defer { core.prepareForTrackSwitch() }
        try #require(await waitUntil { coordinator.isPlaying })
        // Submit the successor early so the test does not depend on catching the
        // final audio buffer's brief preload interval during host-app startup.
        coordinator.playerCoreDecodingComplete(for: first)
        try #require(await waitUntil { core.queuedTrackID == next.id && core.getCurrentPlaybackTime() > 0 })
        core.setVolume(0)
        let position = core.getCurrentPlaybackTime()
        #expect(coordinator.beginTagSave(for: url))
        #expect(!coordinator.isPlaybackBlockedForTagSave)
        let snapshot = try await service.read(url: url)
        let jpeg = try Data(contentsOf: TrackTagServiceTests.fixtures.appendingPathComponent("cover.jpg"))
        let receipt = try await service.save(trackID: next.id, baseline: snapshot,
            patch: TagPatch(fields: ["TITLE": "Saved while queued"], artworkChanged: true, artwork: jpeg))
        let saved = try await service.read(url: url)
        try await coordinator.refreshTrackMetadata(id: next.id, snapshot: saved)
        try await service.finishSave(receipt: receipt)
        coordinator.endTagSave()
        #expect(core.isPlaying)
        #expect(core.getCurrentPlaybackTime() >= position)
        #expect(await waitUntil { coordinator.playbackOrder.history == [first.id, next.id] && !coordinator.isPlaying })
        #expect(coordinator.playbackStateManager.currentTrack?.title == "Saved while queued")
        #expect(await waitUntil { coordinator.currentArtwork != nil })
        #expect(!coordinator.isTrackFailed(next.id))
    }

    @Test("Tag save stops current and preloaded playback; manual replay starts a fresh session", arguments: [false, true])
    func stopBeforeTagSave(playing: Bool) async throws {
        let first = try makeSilentTrack(seconds: 4)
        let next = try makeSilentTrack(seconds: 4)
        defer {
            try? FileManager.default.removeItem(at: first.url)
            try? FileManager.default.removeItem(at: next.url)
        }
        let core = AudioPlayerCore()
        #expect(await core.loadTrack(first))
        #expect(core.enqueueTrack(next).enqueued)
        core.setVolume(0)
        if playing {
            core.play()
            #expect(await waitUntil { core.getCurrentPlaybackTime() > 0 })
        }
        core.prepareForTrackSwitch()
        #expect(!core.isPlaying)
        #expect(core.queuedTrackID == nil)
        #expect(core.getCurrentPlaybackTime() == 0)
        // A new session must remain usable and keep the user's volume.
        #expect(await core.loadTrack(first))
        #expect(core.volume == 0)
        core.play()
        #expect(await waitUntil { core.getCurrentPlaybackTime() > 0 })
        core.prepareForTrackSwitch()
    }

    @Test("真实引擎歌词定位：暂停重播与连续点击以最终确认位置为准")
    func lyricSeekingThroughCoordinator() async throws {
        let track = try makeSilentTrack(seconds: 4)
        defer { try? FileManager.default.removeItem(at: track.url) }
        let data = try createTestDataService()
        let core = AudioPlayerCore()
        let coordinator = PlaybackCoordinator(collectionManager: CollectionManager(dataService: data),
            dataService: data, statisticsManager: EngineTestStatistics(), playerCore: core,
            defaults: try #require(UserDefaults(suiteName: "LyricSeeking.\(UUID())")))
        #expect(!coordinator.canSeek)
        coordinator.playAlbum(Album(id: UUID(), name: "Lyrics", folderURL: nil, tracks: [track]))
        defer { core.prepareForTrackSwitch() }
        core.setVolume(0)
        try #require(await waitUntil { coordinator.canSeek && core.getCurrentPlaybackTime() > 0.05 })
        coordinator.pause()
        let revision = coordinator.playbackProgressState.seekRevision
        coordinator.seek(to: 1, trackID: track.id, metadataRevision: track.metadataRevision)
        try #require(await waitUntil { coordinator.playbackProgressState.seekRevision == revision + 1 })
        #expect(abs(coordinator.playbackProgressState.currentTime - 1) < 0.02)
        #expect(!coordinator.isPlaying)
        coordinator.seek(to: 1, trackID: track.id, metadataRevision: track.metadataRevision)
        try #require(await waitUntil { coordinator.playbackProgressState.seekRevision == revision + 2 })
        coordinator.seek(to: 2, trackID: track.id, metadataRevision: track.metadataRevision)
        coordinator.seek(to: 3, trackID: track.id, metadataRevision: track.metadataRevision)
        try #require(await waitUntil { abs(coordinator.playbackProgressState.currentTime - 3) < 0.02 })
        #expect(!core.isPlaying)
        core.prepareForTrackSwitch()
        #expect(!coordinator.canSeek)
    }

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
        #expect(core.enqueueTrack(next).enqueued)
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
            Task { @MainActor in _ = core?.enqueueTrack(tracks[index + 1]) }
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
            if completed < 3 { Task { @MainActor in _ = core?.enqueueTrack(item) } }
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
        #expect(core.enqueueTrack(bad).enqueued)
        core.setVolume(0)
        core.play()
        defer { core.pause() }
        #expect(await waitUntil { !spy.failures.isEmpty })
        #expect(spy.failures.first?.0 == bad.id)
        #expect(spy.failures.first?.1 == false)
        #expect(core.isPlaying)
        #expect(core.currentTrack?.id == first.id)
        #expect(core.enqueueTrack(next).enqueued)
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

    @Test("随机专辑真实播放一轮不重不漏，末尾停止且再次播放重新开始")
    func shuffledAlbumRound() async throws {
        let tracks = try (0..<4).map { _ in try makeSilentTrack(seconds: 0.2) }
        defer { for track in tracks { try? FileManager.default.removeItem(at: track.url) } }
        let data = try createTestDataService()
        let defaults = try #require(UserDefaults(suiteName: "Me2TuneShuffleEngine.\(UUID())"))
        let core = AudioPlayerCore()
        let coordinator = PlaybackCoordinator(collectionManager: CollectionManager(dataService: data),
                                              dataService: data, statisticsManager: EngineTestStatistics(),
                                              playerCore: core, defaults: defaults)
        coordinator.toggleShuffle()
        coordinator.playAlbum(Album(id: UUID(), name: "Shuffle", folderURL: nil, tracks: tracks), startAt: 1)
        defer { core.prepareForTrackSwitch() }
        #expect(await waitUntil { !coordinator.playbackOrder.history.isEmpty })
        core.setVolume(0)
        #expect(await waitUntil { coordinator.playbackOrder.history.count == 4 && !coordinator.isPlaying })
        #expect(coordinator.playbackOrder.history.first == tracks[1].id)
        #expect(Set(coordinator.playbackOrder.history) == Set(tracks.map(\.id)))
        #expect(!coordinator.canGoNext)
        coordinator.play()
        #expect(await waitUntil { coordinator.isPlaying && coordinator.playbackOrder.history.count == 1 })
    }

    @Test("已预加载后切换随机不重载当前音频且只保留一首后继")
    func shuffleToggleRetainsSubmittedAudio() async throws {
        let tracks = try (0..<3).map { _ in try makeSilentTrack(seconds: 0.7) }
        defer { for track in tracks { try? FileManager.default.removeItem(at: track.url) } }
        let data = try createTestDataService()
        let defaults = try #require(UserDefaults(suiteName: "Me2TuneShuffleEngine.\(UUID())"))
        let core = AudioPlayerCore()
        let coordinator = PlaybackCoordinator(collectionManager: CollectionManager(dataService: data),
                                              dataService: data, statisticsManager: EngineTestStatistics(),
                                              playerCore: core, defaults: defaults)
        coordinator.playAlbum(Album(id: UUID(), name: "Modes", folderURL: nil, tracks: tracks))
        defer { core.prepareForTrackSwitch() }
        #expect(await waitUntil { core.getCurrentPlaybackTime() > 0.15 })
        core.setVolume(0)
        #expect(await waitUntil { core.queuedTrackID == tracks[1].id })
        let position = core.getCurrentPlaybackTime()
        coordinator.toggleShuffle()
        coordinator.toggleShuffle()
        coordinator.toggleShuffle()
        #expect(core.getCurrentPlaybackTime() >= position)
        #expect(core.currentTrack?.id == tracks[0].id)
        #expect(core.isPlaying)
        #expect(await waitUntil { coordinator.playbackOrder.history.count == 3 && !coordinator.isPlaying })
        #expect(coordinator.playbackOrder.history == tracks.map(\.id))
    }

    @Test("删除已预加载歌曲后真实引擎恢复暂停位置且不播放被删歌曲")
    func removePreloadedTrackPreservesPausedPosition() async throws {
        let tracks = try (0..<3).map { _ in try makeSilentTrack(seconds: 1.2) }
        defer { for track in tracks { try? FileManager.default.removeItem(at: track.url) } }
        let data = try createTestDataService()
        for (index, track) in tracks.enumerated() {
            let stored = SDTrack(from: track)
            stored.isInPlaylist = true
            stored.playlistOrder = index
            data.insert(stored)
        }
        try data.save()
        let defaults = try #require(UserDefaults(suiteName: "Me2TuneShuffleEngine.\(UUID())"))
        let core = AudioPlayerCore()
        let coordinator = PlaybackCoordinator(collectionManager: CollectionManager(dataService: data),
                                              dataService: data, statisticsManager: EngineTestStatistics(),
                                              playerCore: core, defaults: defaults)
        coordinator.playPlaylistTrack(at: 0)
        defer { core.prepareForTrackSwitch() }
        #expect(await waitUntil { core.getCurrentPlaybackTime() > 0.2 })
        core.setVolume(0)
        #expect(await waitUntil { core.queuedTrackID == tracks[1].id })
        coordinator.pause()
        let position = core.getCurrentPlaybackTime()
        coordinator.removeTrackFromPlaylist(at: 1)
        #expect(await waitUntil { abs(core.getCurrentPlaybackTime() - position) < 0.03 })
        #expect(!core.isPlaying)
        coordinator.play()
        #expect(await waitUntil { coordinator.playbackOrder.history.last == tracks[2].id && !coordinator.isPlaying })
        #expect(!coordinator.playbackOrder.history.contains(tracks[1].id))
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

@MainActor
private final class EngineTestStatistics: StatisticsManagerProtocol {
    var statisticsRevision = 0
    func incrementTodayPlayCount() async {}
    func fetchAggregatedStats(period: StatPeriod) async -> [DailyStatItem] { [] }
    func fetchRecentStatistics(days: Int) async -> [DailyStatItem] { [] }
    func cleanupOldData(keepDays: Int) {}
}
