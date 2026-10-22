import AppKit
import Testing
@testable import Me2Tune

@MainActor
@Suite("歌词窗口吸附", .serialized)
struct WindowDockingCoordinatorTests {
    @Test("使用窗口外框对齐四个方向，保留标题栏高度")
    func geometryUsesOuterFrames() {
        let player = NSRect(x: 100, y: 200, width: 495, height: 822)
        let size = NSSize(width: 440, height: 822)
        let expected: [(WindowDockingGeometry.Edge, NSPoint)] = [
            (.right, NSPoint(x: 601, y: 200)), (.left, NSPoint(x: -346, y: 200)),
            (.below, NSPoint(x: 100, y: -628)), (.above, NSPoint(x: 100, y: 1028))
        ]
        for (edge, origin) in expected {
            let target = WindowDockingGeometry.frame(for: edge, player: player, lyricsSize: size, scale: 2)
            #expect(target.origin == origin)
            #expect(target.size == size)
        }
    }

    @Test("两档吸附均需要横纵都在 12 pt 内", arguments: [0.0, 12.0, 12.01, -12.0, -12.01], [0.0, 6.0])
    func snapTolerance(offset: Double, gap: Double) {
        let player = NSRect(x: 100, y: 500, width: 200, height: 150)
        let screen = NSRect(x: 0, y: 0, width: 1400, height: 1000)
        for delta in [NSPoint(x: offset, y: 0), NSPoint(x: 0, y: offset)] {
            let lyrics = NSRect(x: 300 + gap + delta.x, y: 550 + delta.y, width: 100, height: 100)
            let result = WindowDockingGeometry.snapEdge(player: player, lyrics: lyrics, mode: .full,
                                                        visibleFrame: screen, scale: 1, gap: gap)
            #expect(result == (abs(offset) <= 12 ? .right : nil))
        }
    }

    @Test("负坐标显示器与不同缩放比例")
    func negativeScreenAndPixelAlignment() {
        let player = NSRect(x: -1500.2, y: 200.3, width: 180, height: 100)
        let size = NSSize(width: 100, height: 80)
        let target = WindowDockingGeometry.frame(for: .right, player: player, lyricsSize: size, scale: 2)
        #expect(target.origin == NSPoint(x: -1314, y: 220.5))
        #expect(WindowDockingGeometry.snapEdge(player: player, lyrics: target, mode: .full,
                                               visibleFrame: NSRect(x: -1920, y: 0, width: 1920, height: 1080),
                                               scale: 2) == .right)
    }

    @Test("Mini 只吸附上下，屏幕放不下时保持独立")
    func modeAndSpaceConstraints() {
        let player = NSRect(x: 100, y: 700, width: 440, height: 78)
        let screen = NSRect(x: 0, y: 0, width: 1200, height: 900)
        let below = NSRect(x: 100, y: -128, width: 440, height: 822)
        #expect(WindowDockingGeometry.snapEdge(player: player, lyrics: below, mode: .mini,
                                               visibleFrame: screen, scale: 2) == nil)
        let side = NSRect(x: 546, y: 0, width: 440, height: 778)
        #expect(WindowDockingGeometry.snapEdge(player: player, lyrics: side, mode: .mini,
                                               visibleFrame: screen, scale: 2) == nil)
        let fitting = NSRect(x: 100, y: 594, width: 440, height: 100)
        #expect(WindowDockingGeometry.snapEdge(player: player, lyrics: fitting, mode: .mini,
                                               visibleFrame: screen, scale: 2) == .below)
    }

    @Test("超高窗口仍保留标题栏可达")
    func oversizedWindowClamping() {
        let frame = NSRect(x: -300, y: -500, width: 440, height: 822)
        #expect(WindowDockingGeometry.clampedOrigin(of: frame, to: NSRect(x: 0, y: 30, width: 1000, height: 700))
                == NSPoint(x: 0, y: -92))
    }

    @Test("拖近吸附后原生绑定，拆开恢复独立桌面和置顶偏好")
    func attachmentAndPolicy() throws {
        let (coordinator, player, lyrics) = try makePair()
        defer { coordinator.shutdown() }
        let independentBehavior = lyrics.collectionBehavior
        player.level = .floating
        player.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        coordinator.snapLyricsIfClose()
        #expect(lyrics.parent === player)
        #expect(coordinator.lyricsState.isDocked)
        #expect(lyrics.level == player.level)
        // AppKit additionally sets ignoresCycle on attached child windows.
        #expect(lyrics.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(lyrics.collectionBehavior.contains(.fullScreenNone))
        player.level = .normal
        coordinator.updateWindowPolicy()
        #expect(lyrics.level == .normal)
        coordinator.detach()
        #expect(lyrics.parent == nil)
        #expect(!coordinator.lyricsState.isDocked)
        #expect(lyrics.collectionBehavior == independentBehavior)
        #expect(lyrics.level == .normal)
    }

    @Test("程序定位不启动拖动，窗口缩放后重新顶部对齐")
    func programmaticMoveAndResize() throws {
        let (coordinator, player, lyrics) = try makePair()
        defer { coordinator.shutdown() }
        coordinator.snapLyricsIfClose()
        player.setFrame(NSRect(origin: player.frame.origin, size: NSSize(width: 220, height: 180)), display: false)
        coordinator.revalidateDocking()
        #expect(coordinator.edge == .right)
        #expect(!coordinator.isTrackingDrag)
        #expect(lyrics.frame.maxY == player.frame.maxY)
        #expect(lyrics.frame.minX == player.frame.maxX + 6)
    }

    @Test("拖动歌词拆开，松手只结算一次，拖播放器不拆开")
    func dragLifecycle() throws {
        let (coordinator, player, lyrics) = try makePair()
        defer { coordinator.shutdown() }
        coordinator.snapLyricsIfClose()
        coordinator.beginDrag(player)
        #expect(lyrics.parent === player)
        #expect(coordinator.isTrackingDrag)
        coordinator.beginDrag(player)
        coordinator.finishDrag()
        #expect(!coordinator.isTrackingDrag)
        coordinator.beginDrag(lyrics)
        #expect(lyrics.parent == nil)
        #expect(coordinator.isTrackingDrag)
        coordinator.finishDrag()
        #expect(lyrics.parent === player)
        #expect(!coordinator.isTrackingDrag)
        coordinator.finishDrag()
        #expect(lyrics.parent === player)
    }

    @Test("隐藏跟随并恢复，歌词刷新同步停止")
    func hideAndRestore() throws {
        let (coordinator, player, lyrics) = try makePair()
        defer { coordinator.shutdown() }
        coordinator.snapLyricsIfClose()
        coordinator.lyricsState.refreshDriver.update(isVisible: true) {}
        player.orderOut(nil)
        #expect(!lyrics.isVisible)
        #expect(!coordinator.lyricsState.isVisible)
        #expect(!coordinator.lyricsState.refreshDriver.isRunning)
        #expect(coordinator.edge == .right)
        player.orderFront(nil)
        #expect(lyrics.isVisible)
        #expect(coordinator.lyricsState.isVisible)
        #expect(lyrics.parent === player)
    }

    @Test("播放器最小化暂时隐藏，单独最小化歌词清除吸附")
    func minimization() throws {
        let (coordinator, player, lyrics) = try makePair()
        defer { coordinator.shutdown() }
        coordinator.snapLyricsIfClose()
        NotificationCenter.default.post(name: NSWindow.willMiniaturizeNotification, object: player)
        #expect(!coordinator.lyricsState.isVisible)
        #expect(coordinator.edge == .right)
        NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: player)
        #expect(coordinator.lyricsState.isVisible)
        coordinator.lyricsWillMiniaturize()
        lyrics.testMiniaturized = true
        coordinator.presentationChanged()
        #expect(coordinator.edge == nil)
        #expect(!coordinator.lyricsState.isVisible)
        player.orderOut(nil)
        player.orderFront(nil)
        #expect(!coordinator.lyricsState.isVisible)
    }

    @Test("切换模式转移原生父窗口，自由状态不自动吸附")
    func modeTransfer() throws {
        let (coordinator, player, lyrics) = try makePair()
        let mini = DockingTestWindow(frame: player.frame)
        defer { coordinator.shutdown() }
        coordinator.snapLyricsIfClose()
        coordinator.prepareForPlayerChange()
        #expect(lyrics.parent == nil)
        coordinator.bindPlayer(mini, mode: .mini)
        #expect(coordinator.edge == .below)
        #expect(lyrics.parent === mini)
        coordinator.prepareForPlayerChange()
        coordinator.bindPlayer(player, mode: .full)
        #expect(coordinator.edge == .right)
        #expect(lyrics.parent === player)
        coordinator.detach()
        coordinator.prepareForPlayerChange()
        coordinator.bindPlayer(mini, mode: .mini)
        #expect(lyrics.parent == nil)
        #expect(coordinator.edge == nil)
    }

    @Test("未打开歌词时 Mini 仍应用原有置顶偏好")
    func miniPolicyWithoutLyrics() throws {
        let (coordinator, player, _) = try makePair()
        defer { coordinator.shutdown() }
        coordinator.unbindLyrics()
        player.level = .statusBar
        coordinator.bindPlayer(player, mode: .mini)
        #expect(player.level == .normal)
        #expect(coordinator.observationCount == 0)
    }

    @Test("空间不足时换侧，两侧均不足时解除并夹回可用区域")
    func fallbackAndInsufficientSpace() throws {
        let (coordinator, player, lyrics) = try makePair()
        defer { coordinator.shutdown() }
        let screen = try #require(player.screen).visibleFrame
        coordinator.snapLyricsIfClose()
        player.setFrameOrigin(NSPoint(x: screen.maxX - player.frame.width, y: player.frame.minY))
        coordinator.revalidateDocking()
        #expect(coordinator.edge == .left)
        lyrics.setContentSize(NSSize(width: screen.width, height: 100))
        coordinator.revalidateDocking()
        #expect(coordinator.edge == nil)
        #expect(lyrics.parent == nil)
        #expect(lyrics.frame.minX == screen.minX)
    }

    @Test("关闭、全屏和失活释放拖动会话，不自动恢复关闭的歌词")
    func cancellationAndClosure() throws {
        let (coordinator, player, lyrics) = try makePair()
        defer { coordinator.shutdown() }
        coordinator.snapLyricsIfClose()
        coordinator.beginDrag(player)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        #expect(!coordinator.isTrackingDrag)
        NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: player)
        #expect(coordinator.edge == nil)
        coordinator.snapLyricsIfClose()
        let closedState = coordinator.lyricsState
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: lyrics)
        #expect(coordinator.lyricsWindow == nil)
        #expect(coordinator.observationCount == 0)
        #expect(!coordinator.lyricsState.isVisible)
        player.orderOut(nil)
        player.orderFront(nil)
        #expect(coordinator.lyricsWindow == nil)
        coordinator.bindLyrics(lyrics)
        #expect(coordinator.edge == nil)
        #expect(coordinator.lyricsState !== closedState)
        #expect(!closedState.isVisible)
        closedState.refreshDriver.update(isVisible: closedState.isVisible) {
            Issue.record("A closed view's late load must not restart refresh")
        }
        #expect(!closedState.refreshDriver.isRunning)
    }

    @Test("反复绑定及 20 次开关不累计监听或持有歌词窗口")
    func repeatedLifecycle() throws {
        let (coordinator, player, initialLyrics) = try makePair()
        defer { coordinator.shutdown() }
        let count = coordinator.observationCount
        coordinator.bindPlayer(player, mode: .full)
        coordinator.bindLyrics(initialLyrics)
        #expect(coordinator.observationCount == count)
        coordinator.unbindLyrics()
        for _ in 0..<20 {
            weak var releasedWindow: NSWindow?
            autoreleasepool {
                let lyrics = DockingTestWindow(frame: initialLyrics.frame)
                releasedWindow = lyrics
                coordinator.bindLyrics(lyrics)
                #expect(coordinator.observationCount == count)
                coordinator.beginDrag(lyrics)
                coordinator.unbindLyrics()
                #expect(coordinator.observationCount == 0)
                #expect(!coordinator.isTrackingDrag)
            }
            #expect(releasedWindow == nil)
        }
    }

    @Test("两档间距的真实窗口跟随、隐藏和恢复", arguments: [false, true], LyricsDockingSpacing.allCases)
    func nativeWindowGroup(isMini: Bool, spacing: LyricsDockingSpacing) throws {
        let screen = try #require(NSScreen.main).visibleFrame
        let playerFrame = NSRect(x: screen.midX - 220, y: screen.midY, width: 180, height: 100)
        let player: NSWindow
        if isMini {
            let panel = NSPanel(contentRect: playerFrame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
            player = panel
        } else {
            player = NSWindow(contentRect: playerFrame, styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        }
        let lyrics = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 80),
                              styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        player.isReleasedWhenClosed = false
        lyrics.isReleasedWhenClosed = false
        let suite = "Me2Tune.DockingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsManager(defaults: defaults)
        settings.lyricsDockingSpacing = spacing
        let coordinator = WindowDockingCoordinator(settings: settings)
        defer {
            coordinator.shutdown()
            lyrics.close()
            player.close()
        }
        player.orderFront(nil)
        lyrics.orderFront(nil)
        lyrics.setFrameOrigin(WindowDockingGeometry.frame(for: isMini ? .below : .right, player: player.frame,
                                                           lyricsSize: lyrics.frame.size,
                                                           scale: try #require(player.screen).backingScaleFactor,
                                                           gap: spacing.gap).origin)
        coordinator.bindPlayer(player, mode: isMini ? .mini : .full)
        coordinator.bindLyrics(lyrics)
        coordinator.snapLyricsIfClose()
        #expect(lyrics.parent === player)
        #expect(isMini ? player.frame.minY - lyrics.frame.maxY == spacing.gap
                : lyrics.frame.minX - player.frame.maxX == spacing.gap)
        let oldOrigin = lyrics.frame.origin
        player.setFrameOrigin(NSPoint(x: player.frame.minX + 20, y: player.frame.minY - 20))
        #expect(lyrics.frame.origin == NSPoint(x: oldOrigin.x + 20, y: oldOrigin.y - 20))
        #expect(!coordinator.isTrackingDrag)
        player.orderOut(nil)
        #expect(!lyrics.isVisible)
        #expect(!coordinator.lyricsState.isVisible)
        player.orderFront(nil)
        #expect(lyrics.isVisible)
        #expect(coordinator.lyricsState.isVisible)
        #expect(lyrics.parent === player)
    }

    @Test("间距默认留空、保存两档并在重新读取时恢复，无效值回退")
    func spacingPersistence() throws {
        let suite = "Me2Tune.DockingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsManager(defaults: defaults)
        #expect(settings.lyricsDockingSpacing == .spaced)
        settings.lyricsDockingSpacing = .flush
        #expect(SettingsManager(defaults: defaults).lyricsDockingSpacing == .flush)
        settings.lyricsDockingSpacing = .spaced
        #expect(SettingsManager(defaults: defaults).lyricsDockingSpacing == .spaced)
        defaults.set("unknown", forKey: "lyricsDockingSpacing")
        #expect(SettingsManager(defaults: defaults).lyricsDockingSpacing == .spaced)
    }

    @Test("切换间距仅移动已吸附歌词，模式切换和重开沿用选择")
    func spacingChangesWhileDocked() async throws {
        let suite = "Me2Tune.DockingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsManager(defaults: defaults)
        let (coordinator, player, lyrics) = try makePair(settings: settings)
        defer { coordinator.shutdown() }
        coordinator.snapLyricsIfClose()
        let anchorFrame = player.frame
        settings.lyricsDockingSpacing = .flush
        // The Observation callback hops once to MainActor after the setter completes.
        for _ in 0..<100 where lyrics.frame.minX != player.frame.maxX { await Task.yield() }
        #expect(lyrics.frame.minX == player.frame.maxX)
        #expect(player.frame == anchorFrame)
        #expect(lyrics.parent === player)
        #expect(!coordinator.isTrackingDrag)
        let mini = DockingTestWindow(frame: anchorFrame)
        coordinator.prepareForPlayerChange()
        coordinator.bindPlayer(mini, mode: .mini)
        #expect(lyrics.frame.maxY == mini.frame.minY)
        settings.lyricsDockingSpacing = .spaced
        for _ in 0..<100 where mini.frame.minY - lyrics.frame.maxY != 6 { await Task.yield() }
        #expect(mini.frame.minY - lyrics.frame.maxY == 6)
        #expect(mini.frame == anchorFrame)
        coordinator.unbindLyrics()
        coordinator.bindLyrics(lyrics)
        #expect(coordinator.edge == nil)
        #expect(settings.lyricsDockingSpacing == .spaced)
        coordinator.snapLyricsIfClose()
        #expect(coordinator.edge == .below)
        #expect(mini.frame.minY - lyrics.frame.maxY == 6)
    }

    @Test("自由窗口修改偏好不移动、不主动吸附")
    func spacingChangesWhileDetached() async throws {
        let suite = "Me2Tune.DockingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsManager(defaults: defaults)
        let (coordinator, player, lyrics) = try makePair(settings: settings)
        defer { coordinator.shutdown() }
        let original = lyrics.frame
        settings.lyricsDockingSpacing = .flush
        for _ in 0..<10 { await Task.yield() }
        #expect(lyrics.frame == original)
        #expect(coordinator.edge == nil)
        #expect(lyrics.parent == nil)
        coordinator.snapLyricsIfClose()
        #expect(lyrics.frame.minX == player.frame.maxX)
    }

    @Test("四方向紧贴与屏幕边缘不多留六点空间")
    func flushGeometryAndScreenEdge() {
        let player = NSRect(x: 100, y: 200, width: 200, height: 100)
        let size = NSSize(width: 100, height: 80)
        for (edge, origin) in [(WindowDockingGeometry.Edge.right, NSPoint(x: 300, y: 220)),
                               (.left, NSPoint(x: 0, y: 220)), (.below, NSPoint(x: 100, y: 120)),
                               (.above, NSPoint(x: 100, y: 300))] {
            #expect(WindowDockingGeometry.frame(for: edge, player: player, lyricsSize: size, scale: 2, gap: 0).origin == origin)
        }
        let lyrics = NSRect(x: 300, y: 220, width: 100, height: 80)
        let screen = NSRect(x: 0, y: 0, width: 400, height: 400)
        #expect(WindowDockingGeometry.snapEdge(player: player, lyrics: lyrics, mode: .full,
                                               visibleFrame: screen, scale: 2, gap: 0) == .right)
        #expect(WindowDockingGeometry.snapEdge(player: player, lyrics: lyrics, mode: .full,
                                               visibleFrame: screen, scale: 2, gap: 6) == nil)
    }

    private func makePair(settings: SettingsManager? = nil) throws -> (WindowDockingCoordinator, DockingTestWindow, DockingTestWindow) {
        let screen = try #require(NSScreen.main).visibleFrame
        let player = DockingTestWindow(frame: NSRect(x: screen.minX + screen.width / 3,
                                                    y: screen.minY + screen.height / 2,
                                                    width: 180, height: 100))
        let lyrics = DockingTestWindow(frame: NSRect(x: player.frame.maxX + 6, y: player.frame.maxY - 80,
                                                    width: 100, height: 80))
        let defaults = try #require(UserDefaults(suiteName: "Me2Tune.DockingTests.\(UUID().uuidString)"))
        let coordinator = WindowDockingCoordinator(settings: settings ?? SettingsManager(defaults: defaults))
        coordinator.bindPlayer(player, mode: .full)
        coordinator.bindLyrics(lyrics)
        return (coordinator, player, lyrics)
    }
}

@MainActor
private final class DockingTestWindow: NSWindow {
    private var testVisible = true
    var testMiniaturized = false

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
    }

    override var isVisible: Bool { testVisible }
    override var isMiniaturized: Bool { testMiniaturized }
    override var screen: NSScreen? { NSScreen.main }

    override func orderOut(_ sender: Any?) { setVisible(false) }
    override func orderFront(_ sender: Any?) { setVisible(true) }

    private func setVisible(_ visible: Bool) {
        guard testVisible != visible else { return }
        willChangeValue(forKey: "visible")
        testVisible = visible
        didChangeValue(forKey: "visible")
    }
}
