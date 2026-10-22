//
//  PlaybackLoadControllerTests.swift
//  Me2TuneTests
//
//  Unit tests for isolated playback load and gapless behavior.
//

import AppKit
import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("PlaybackLoadController 单元测试")
struct PlaybackLoadControllerTests {
    @MainActor
    private final class RequestedTrackRecorder {
        var trackIDs: [UUID] = []
    }

    private func makeController(
        tracks: [AudioTrack],
        playerCore: MockLoadPlayerCore,
        repeatMode: RepeatMode = .off,
        onPause: @escaping @MainActor () -> Void = {}
    ) throws -> (controller: PlaybackLoadController, stateManager: PlaybackStateManager, registry: FailedTrackRegistry, requestedTracks: RequestedTrackRecorder) {
        let dataService = try createTestDataService()
        let playlistManager = PlaylistManager(dataService: dataService)
        let collectionManager = CollectionManager(dataService: dataService)
        let stateManager = PlaybackStateManager(
            playlistManager: playlistManager,
            collectionManager: collectionManager,
            dataService: dataService
        )

        let album = Album(
            id: UUID(),
            name: "Test Album",
            folderURL: nil,
            tracks: tracks
        )
        stateManager.switchToAlbum(album)

        let registry = FailedTrackRegistry()
        let requestedTracks = RequestedTrackRecorder()
        let persistenceController = PlaybackPersistenceController(
            saveHandler: {},
            volumeApplyHandler: { _ in }
        )

        let controller = PlaybackLoadController(
            playerCore: playerCore,
            stateManager: stateManager,
            registry: registry,
            persistenceController: persistenceController,
            repeatModeProvider: { repeatMode },
            onPause: onPause,
            onTrackRequested: { track in
                requestedTracks.trackIDs.append(track.id)
            }
        )

        controller.synchronizeOrder()
        playerCore.onStart = { [weak controller] track in controller?.confirmStarted(track) }
        return (controller, stateManager, registry, requestedTracks)
    }

    @Test("start 成功后设置索引并调用 play")
    func testLoadAndPlaySuccessSetsIndexAndPlays() async throws {
        let tracks = makeTracks(count: 3)
        let playerCore = MockLoadPlayerCore()
        let (controller, stateManager, _, _) = try makeController(
            tracks: tracks,
            playerCore: playerCore
        )

        controller.start(controller.order.select(tracks[1].id), automatic: true)

        let loaded = await waitUntil {
            stateManager.currentTrackIndex == 1 && playerCore.playCallCount == 1
        }

        #expect(loaded)
        #expect(playerCore.loadTrackCallIDs == [tracks[1].id])
    }

    @Test("start 会在异步加载前上报请求曲目")
    func testLoadAndPlayReportsRequestedTrack() async throws {
        let tracks = makeTracks(count: 2)
        let playerCore = MockLoadPlayerCore()
        let (controller, _, _, requestedTracks) = try makeController(
            tracks: tracks,
            playerCore: playerCore
        )

        controller.start(controller.order.select(tracks[1].id), automatic: true)

        #expect(requestedTracks.trackIDs == [tracks[1].id])
    }

    @Test("首曲加载失败后标记 failed 并跳到下一首")
    func testLoadFailureMarksFailedAndSkips() async throws {
        let tracks = makeTracks(count: 3)
        let playerCore = MockLoadPlayerCore()
        playerCore.loadResults[tracks[0].id] = false
        playerCore.loadResults[tracks[1].id] = true

        let (controller, _, registry, requestedTracks) = try makeController(
            tracks: tracks,
            playerCore: playerCore
        )

        controller.start(controller.order.select(tracks[0].id), automatic: true)

        let skipped = await waitUntil {
            playerCore.loadTrackCallIDs.count >= 2
        }

        #expect(skipped)
        #expect(playerCore.loadTrackCallIDs.prefix(2) == [tracks[0].id, tracks[1].id])
        #expect(registry.isMarked(tracks[0].id))
        #expect(requestedTracks.trackIDs.prefix(2) == [tracks[0].id, tracks[1].id])
    }

    @Test("所有曲目均失败后触发 onPause")
    func testAllFailedTracksTriggerPause() async throws {
        let tracks = makeTracks(count: 2)
        let playerCore = MockLoadPlayerCore()
        for track in tracks {
            playerCore.loadResults[track.id] = false
        }

        var pauseCallCount = 0
        let (controller, _, _, _) = try makeController(
            tracks: tracks,
            playerCore: playerCore,
            onPause: { pauseCallCount += 1 }
        )

        controller.start(controller.order.select(tracks[0].id), automatic: true)

        let paused = await waitUntil {
            pauseCallCount == 1
        }

        #expect(paused)
        #expect(playerCore.loadTrackCallIDs == [tracks[0].id, tracks[1].id])
    }

    @Test("repeat one 下加载失败直接停止且不跳转")
    func testRepeatOneFailureStopsWithoutSkipping() async throws {
        let tracks = makeTracks(count: 3)
        let playerCore = MockLoadPlayerCore()
        playerCore.loadResults[tracks[0].id] = false

        var pauseCallCount = 0
        let (controller, _, _, _) = try makeController(
            tracks: tracks,
            playerCore: playerCore,
            repeatMode: .one,
            onPause: { pauseCallCount += 1 }
        )

        controller.start(controller.order.select(tracks[0].id), automatic: true)

        let paused = await waitUntil {
            pauseCallCount == 1
        }

        #expect(paused)
        #expect(playerCore.loadTrackCallIDs == [tracks[0].id])
    }

    @Test("gapless 已处理时 handleEndOfTrack 不重复加载")
    func testHandleEndOfTrackSkipsWhenGaplessAlreadyHandled() async throws {
        let tracks = makeTracks(count: 3)
        let playerCore = MockLoadPlayerCore()
        let (controller, stateManager, _, _) = try makeController(
            tracks: tracks,
            playerCore: playerCore
        )

        controller.start(controller.order.select(tracks[0].id), automatic: true)

        let loadedFirst = await waitUntil {
            playerCore.loadTrackCallIDs.count == 1
        }

        #expect(loadedFirst)

        controller.enqueueNextTrack(after: tracks[0])
        #expect(await waitUntil { controller.submitted != nil })
        stateManager.setCurrentTrack(id: tracks[1].id)
        controller.confirmStarted(tracks[1])
        controller.handleEndOfTrack()
        try? await Task.sleep(for: .milliseconds(80))

        #expect(playerCore.loadTrackCallIDs.count == 1)
    }

    @Test("旧加载稍后失败不会覆盖新请求或标记旧曲失败")
    func staleLoadFailureDoesNotRecover() async throws {
        let tracks = makeTracks(count: 2)
        let core = MockLoadPlayerCore()
        core.loadDelays[tracks[0].id] = .milliseconds(150)
        core.loadResults[tracks[0].id] = false
        let (controller, state, registry, _) = try makeController(tracks: tracks, playerCore: core)
        controller.start(controller.order.select(tracks[0].id), automatic: true)
        #expect(await waitUntil { core.loadTrackCallIDs.count == 1 })
        controller.start(controller.order.select(tracks[1].id), automatic: true)
        #expect(await waitUntil { core.playCallCount == 1 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(state.currentTrackIndex == 1)
        #expect(core.playCallCount == 1)
        #expect(!registry.isMarked(tracks[0].id))
    }

    @Test("同步预加载失败会尝试下一首")
    func enqueueFailureTriesSuccessor() async throws {
        let tracks = makeTracks(count: 3)
        let core = MockLoadPlayerCore()
        core.enqueueResults[tracks[1].id] = false
        let (controller, _, registry, _) = try makeController(tracks: tracks, playerCore: core)
        controller.enqueueNextTrack(after: tracks[0])
        #expect(await waitUntil { core.enqueueTrackCallIDs.count == 2 })
        #expect(core.enqueueTrackCallIDs == [tracks[1].id, tracks[2].id])
        #expect(registry.isMarked(tracks[1].id))
    }

    @Test("异步预加载失败去重且不重载当前曲目")
    func asynchronousPreloadFailure() async throws {
        let tracks = makeTracks(count: 3)
        let core = MockLoadPlayerCore()
        let (controller, _, registry, _) = try makeController(tracks: tracks, playerCore: core)
        controller.start(controller.order.select(tracks[0].id), automatic: true)
        #expect(await waitUntil { core.playCallCount == 1 })
        controller.enqueueNextTrack(after: tracks[0])
        #expect(await waitUntil { controller.submitted?.id == tracks[1].id })
        controller.handleDecodingFailure(for: tracks[1], isCurrent: false)
        controller.handleDecodingFailure(for: tracks[1], isCurrent: false)
        #expect(await waitUntil { core.enqueueTrackCallIDs.count == 2 })
        #expect(core.enqueueTrackCallIDs == [tracks[1].id, tracks[2].id])
        #expect(core.loadTrackCallIDs == [tracks[0].id])
        #expect(registry.isMarked(tracks[1].id))
        #expect(!registry.isMarked(tracks[0].id))
    }

    @Test("异步当前曲目失败使仍在等待的旧加载失效")
    func asynchronousCurrentFailureInvalidatesLoad() async throws {
        let tracks = makeTracks(count: 2)
        let core = MockLoadPlayerCore()
        core.loadDelays[tracks[0].id] = .milliseconds(150)
        let (controller, state, registry, _) = try makeController(tracks: tracks, playerCore: core)
        controller.start(controller.order.select(tracks[0].id), automatic: true)
        #expect(await waitUntil { core.loadTrackCallIDs.count == 1 })
        controller.handleDecodingFailure(for: tracks[0], isCurrent: true)
        #expect(await waitUntil { core.playCallCount == 1 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(core.loadTrackCallIDs == tracks.map(\.id))
        #expect(core.playCallCount == 1)
        #expect(state.currentTrackIndex == 1)
        #expect(registry.isMarked(tracks[0].id))
    }

    private func makeTracks(count: Int) -> [AudioTrack] {
        (0..<count).map { index in
            AudioTrack(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/load_controller_track_\(index).mp3"),
                title: "Track \(index)",
                artist: nil,
                albumTitle: nil,
                duration: 120,
                format: .unknown,
                bookmark: nil
            )
        }
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
private final class MockLoadPlayerCore: AudioPlayerCoreProtocol {
    var canSeek = true
    weak var delegate: (any AudioPlayerCoreDelegate)?
    var isPlaying = false
    var repeatMode: RepeatMode = .off

    var onStart: ((AudioTrack) -> Void)?
    private var loadedTrack: AudioTrack?
    var loadResults: [UUID: Bool] = [:]
    var loadDelays: [UUID: Duration] = [:]
    var enqueueResults: [UUID: Bool] = [:]
    private(set) var loadTrackCallIDs: [UUID] = []
    private(set) var enqueueTrackCallIDs: [UUID] = []
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0

    func loadTrack(_ track: AudioTrack, startingAt time: TimeInterval = 0) async -> Bool {
        loadedTrack = track
        loadTrackCallIDs.append(track.id)
        if let delay = loadDelays[track.id] { try? await Task.sleep(for: delay) }
        return loadResults[track.id] ?? true
    }

    func enqueueTrack(_ track: AudioTrack) -> AudioEnqueueResult {
        enqueueTrackCallIDs.append(track.id)
        return (enqueueResults[track.id] ?? true) ? .enqueued(track.id) : .failed
    }

    func play() {
        isPlaying = true
        playCallCount += 1
        if let loadedTrack {
            self.loadedTrack = nil
            onStart?(loadedTrack)
        }
    }

    func pause() {
        isPlaying = false
        pauseCallCount += 1
    }

    func seek(to time: TimeInterval) {}

    func setVolume(_ volume: Double) {}

    func prepareForTrackSwitch() {}

    func getCurrentPlaybackTime() -> TimeInterval {
        0
    }

    func updateDockIcon(_ artwork: NSImage?) {}
}
