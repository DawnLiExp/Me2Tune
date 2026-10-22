import AppKit
import SwiftUI
import Testing
@testable import Me2Tune

@MainActor
@Suite("歌词原生窗口交互", .serialized)
struct LyricsInteractionTests {
    @Test("原生按钮点击定位，滚动暂停跟随，返回不改变播放位置")
    func pointerAndScrollRouting() async throws {
        let fixture = try await LyricsInteractionFixture.make()
        defer { fixture.close() }
        let row = try #require(fixture.lyricRow(at: 2))
        let initialFrame = fixture.window.frame
        let point = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        fixture.click(at: point)
        #expect(await fixture.waitUntil { fixture.core.seeks == [20] })
        #expect(fixture.window.frame == initialFrame)
        #expect(!fixture.viewModel.isPlaying)
        #expect(await fixture.waitUntil { fixture.returnControl == nil })
        fixture.drag(at: point, by: NSSize(width: 90, height: 90))
        try await Task.sleep(for: .milliseconds(100))
        #expect(fixture.core.seeks == [20])
        #expect(fixture.window.frame == initialFrame)

        let scroll = try #require(fixture.descendants(of: fixture.host).compactMap { $0 as? NSScrollView }.first)
        let oldOrigin = scroll.contentView.bounds.origin
        await fixture.scroll(scroll, phase: .began, delta: 0)
        await fixture.scroll(scroll, phase: .changed, delta: -160)
        await fixture.scroll(scroll, phase: .ended, delta: 0)
        await fixture.scroll(scroll, phase: [], delta: -30, momentum: 1)
        await fixture.scroll(scroll, phase: [], delta: -20, momentum: 2)
        await fixture.scroll(scroll, phase: [], delta: 0, momentum: 3)
        #expect(await fixture.waitUntil { scroll.contentView.bounds.origin != oldOrigin })
        #expect(await fixture.waitUntil { fixture.returnControl != nil })
        #expect(fixture.core.seeks == [20])
        #expect(fixture.window.frame == initialFrame)

        let browsedOrigin = scroll.contentView.bounds.origin
        fixture.core.currentTime = 50
        // Allow a real refresh tick and the existing highlight transition to settle.
        try await Task.sleep(for: .milliseconds(700))
        #expect(scroll.contentView.bounds.origin == browsedOrigin)
        fixture.saveSnapshot("browsing")
        let back = try #require(fixture.returnControl)
        fixture.click(at: back.convert(NSPoint(x: back.bounds.midX, y: back.bounds.midY), to: nil))
        #expect(await fixture.waitUntil { fixture.returnControl == nil })
        #expect(fixture.core.seeks == [20])
        #expect(fixture.core.currentTime == 50)
        #expect(fixture.window.frame == initialFrame)
        let resumedOrigin = scroll.contentView.bounds.origin
        fixture.core.currentTime = 60
        #expect(await fixture.waitUntil { scroll.contentView.bounds.origin != resumedOrigin })
    }
    @Test("定位标记区域同样可点击，标题区保留原生拖窗入口")
    func markerHitAreaAndHeader() async throws {
        let fixture = try await LyricsInteractionFixture.make()
        defer { fixture.close() }
        let row = try #require(fixture.lyricRow(at: 2))
        let edge = row.convert(NSPoint(x: row.bounds.maxX - 9, y: row.bounds.midY), to: nil)
        let before = fixture.window.frame
        fixture.click(at: edge)
        #expect(await fixture.waitUntil { fixture.core.seeks == [20] })
        #expect(fixture.window.frame == before)
        let headerPoint = fixture.host.convert(NSPoint(x: 220, y: 775), from: nil)
        let header = try #require(fixture.host.hitTest(headerPoint))
        #expect(fixture.window.isMovableByWindowBackground)
        #expect(header.mouseDownCanMoveWindow)
    }

}

@MainActor
private final class LyricsInteractionFixture {
    let folder: URL
    let core: LyricsInteractionCore
    let viewModel: PlayerViewModel
    let window: NSWindow
    let host: NSView
    let state: LyricsWindowState

    private init(folder: URL, core: LyricsInteractionCore, viewModel: PlayerViewModel,
                 window: NSWindow, host: NSView, state: LyricsWindowState) {
        self.folder = folder; self.core = core; self.viewModel = viewModel
        self.window = window; self.host = host; self.state = state
    }

    static func make() async throws -> LyricsInteractionFixture {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Lyrics.wav")
        let lrc = (0..<30).map { index in
            let time = String(format: "%02d:%02d", index * 10 / 60, index * 10 % 60)
            return "[\(time)]Lyric line \(index)\n[\(time)]第 \(index) 句歌词"
        }.joined(separator: "\n")
        try lrc.write(to: url.deletingPathExtension().appendingPathExtension("lrc"), atomically: true, encoding: .utf8)
        let track = AudioTrack(id: UUID(), url: url, title: "Lyrics interaction check", artist: "Test fixture",
                              albumTitle: nil, duration: 300, format: .unknown, bookmark: nil)
        let data = try createTestDataService()
        let core = LyricsInteractionCore()
        let coordinator = PlaybackCoordinator(collectionManager: CollectionManager(dataService: data),
            dataService: data, playerCore: core,
            defaults: try #require(UserDefaults(suiteName: "LyricsInteraction.\(UUID())")))
        let viewModel = PlayerViewModel(coordinator: coordinator)
        let state = LyricsWindowState()
        state.isVisible = true
        let host = NSHostingView(rootView: LyricsView(windowState: state).environment(viewModel))
        let window = NSWindow(contentRect: NSRect(x: 160, y: 120, width: 440, height: 800),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Lyrics interaction verification"
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        let fixture = LyricsInteractionFixture(folder: folder, core: core, viewModel: viewModel,
                                               window: window, host: host, state: state)
        try #require(await fixture.waitUntil { viewModel.isPlaylistLoaded })
        coordinator.playAlbum(Album(id: UUID(), name: "Lyrics", folderURL: nil, tracks: [track]))
        try #require(await fixture.waitUntil { viewModel.isPlaying })
        coordinator.pause()
        try #require(await fixture.waitUntil { fixture.lyricRow(at: 2) != nil })
        // Let the initial ScrollViewReader positioning settle before pointer events.
        try await Task.sleep(for: .milliseconds(300))
        fixture.saveSnapshot("initial")
        return fixture
    }

    func saveSnapshot(_ name: String) {
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("me2tune-lyrics-\(name).png")
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        print("SNAPSHOT", url.path)
    }

    func close() {
        state.isVisible = false
        window.close()
        try? FileManager.default.removeItem(at: folder)
    }

    func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    var scrollView: NSScrollView? {
        descendants(of: host).compactMap { $0 as? NSScrollView }.first
    }

    // Inspect our own transparent mouse-routing views, not SwiftUI's private view types.
    func lyricRow(at index: Int) -> NSView? {
        guard let scrollView else { return nil }
        let rows = descendants(of: scrollView).filter { String(describing: type(of: $0)) == "NonDraggableNSView" }
        return rows.indices.contains(index) ? rows[index] : nil
    }

    var returnControl: NSView? {
        guard let scrollView else { return nil }
        return descendants(of: host).first {
            String(describing: type(of: $0)) == "NonDraggableNSView"
                && !$0.isDescendant(of: scrollView)
                && $0.convert(NSPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: nil).y < 100
        }
    }

    func waitUntil(_ condition: () -> Bool) async -> Bool {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < .seconds(3) {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    func click(at point: NSPoint) {
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime + 0.01, windowNumber: window.windowNumber,
            context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
    }

    func drag(at point: NSPoint, by delta: NSSize) {
        let destination = NSPoint(x: point.x + delta.width, y: point.y + delta.height)
        let timestamp = ProcessInfo.processInfo.systemUptime
        let events = [(NSEvent.EventType.leftMouseDown, point), (.leftMouseDragged, destination), (.leftMouseUp, destination)].enumerated().map { index, item in
            NSEvent.mouseEvent(with: item.0, location: item.1, modifierFlags: [], timestamp: timestamp + Double(index) * 0.02,
                windowNumber: window.windowNumber, context: nil, eventNumber: index + 10, clickCount: 1, pressure: index == 2 ? 0 : 1)!
        }
        NSApp.postEvent(events[2], atStart: true)
        NSApp.postEvent(events[1], atStart: true)
        window.sendEvent(events[0])
    }

    func scroll(_ view: NSScrollView, phase: NSEvent.Phase, delta: Int32, momentum: Int64 = 0) async {
        let cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                              wheel1: delta, wheel2: 0, wheel3: 0)!
        // CGScrollPhase and NSEvent.Phase use different bit values.
        let cgPhase: Int64 = phase.isEmpty ? 0 : (phase == .began ? 1 : (phase == .changed ? 2 : 4))
        cgEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: cgPhase)
        cgEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        let event = NSEvent(cgEvent: cgEvent)!
        view.scrollWheel(with: event)
        try? await Task.sleep(for: .milliseconds(60))
    }
}

@MainActor
private final class LyricsInteractionCore: AudioPlayerCoreProtocol {
    weak var delegate: (any AudioPlayerCoreDelegate)?
    var isPlaying = false
    var canSeek = true
    var repeatMode: RepeatMode = .off
    var currentTime: TimeInterval = 20
    var track: AudioTrack?
    var seeks: [TimeInterval] = []
    func loadTrack(_ track: AudioTrack, startingAt time: TimeInterval) async -> Bool {
        self.track = track
        delegate?.playerCoreDidLoadTrack(track, artwork: nil)
        return true
    }
    func enqueueTrack(_ track: AudioTrack) -> AudioEnqueueResult { .failed }
    func play() {
        isPlaying = true
        delegate?.playerCoreDidUpdatePlaybackState(true)
        delegate?.playerCoreNowPlayingChanged(to: track)
    }
    func pause() { isPlaying = false; delegate?.playerCoreDidUpdatePlaybackState(false) }
    func seek(to time: TimeInterval) {
        seeks.append(time); currentTime = time
        delegate?.playerCoreDidUpdateTime(currentTime: time, duration: 300)
        delegate?.playerCoreDidConfirmSeek(to: time)
    }
    func setVolume(_ volume: Double) {}
    func prepareForTrackSwitch() {}
    func getCurrentPlaybackTime() -> TimeInterval { currentTime }
    func updateDockIcon(_ artwork: NSImage?) {}
}
