import AppKit
import Observation

@MainActor
@Observable
final class LyricsWindowState {
    var isVisible = false {
        didSet {
            if !isVisible { refreshDriver.stop() }
        }
    }
    var isDocked = false
    @ObservationIgnored let refreshDriver = LyricsRefreshDriver()
}

enum WindowDockingGeometry {
    enum Edge: CaseIterable {
        case right, left, below, above
    }

    static let gap: CGFloat = 6
    static let tolerance: CGFloat = 12

    static func edges(for mode: DisplayMode) -> [Edge] {
        mode == .full ? [.right, .left] : [.below, .above]
    }

    static func frame(for edge: Edge, player: NSRect, lyricsSize: NSSize, scale: CGFloat) -> NSRect {
        let origin: NSPoint
        switch edge {
        case .right: origin = NSPoint(x: player.maxX + gap, y: player.maxY - lyricsSize.height)
        case .left: origin = NSPoint(x: player.minX - gap - lyricsSize.width, y: player.maxY - lyricsSize.height)
        case .below: origin = NSPoint(x: player.minX, y: player.minY - gap - lyricsSize.height)
        case .above: origin = NSPoint(x: player.minX, y: player.maxY + gap)
        }
        let scale = max(1, scale)
        return NSRect(x: (origin.x * scale).rounded() / scale,
                      y: (origin.y * scale).rounded() / scale,
                      width: lyricsSize.width, height: lyricsSize.height)
    }

    static func snapEdge(player: NSRect, lyrics: NSRect, mode: DisplayMode,
                         visibleFrame: NSRect, scale: CGFloat) -> Edge? {
        var best: (edge: Edge, distance: CGFloat)?
        for edge in edges(for: mode) {
            let target = frame(for: edge, player: player, lyricsSize: lyrics.size, scale: scale)
            let dx = abs(target.minX - lyrics.minX)
            let dy = abs(target.minY - lyrics.minY)
            guard visibleFrame.contains(target), dx <= tolerance, dy <= tolerance else { continue }
            let distance = dx * dx + dy * dy
            if distance < (best?.distance ?? .infinity) { best = (edge, distance) }
        }
        return best?.edge
    }

    static func clampedOrigin(of frame: NSRect, to visibleFrame: NSRect) -> NSPoint {
        // If the fixed window is taller than the screen, keep its title bar reachable.
        NSPoint(x: max(visibleFrame.minX, min(frame.minX, visibleFrame.maxX - frame.width)),
                y: frame.height > visibleFrame.height ? visibleFrame.maxY - frame.height
                    : max(visibleFrame.minY, min(frame.minY, visibleFrame.maxY - frame.height)))
    }
}

@MainActor
final class WindowDockingCoordinator {
    typealias Edge = WindowDockingGeometry.Edge

    private(set) var lyricsState = LyricsWindowState()
    private(set) weak var playerWindow: NSWindow?
    private(set) weak var lyricsWindow: NSWindow?
    private(set) var edge: Edge?
    private(set) var mode: DisplayMode = .full
    private var originalCollectionBehavior: NSWindow.CollectionBehavior = []
    private var observers: [NSObjectProtocol] = []
    private var windowObservations: [NSKeyValueObservation] = []
    private var mouseMonitor: Any?
    private weak var mouseDownWindow: NSWindow?
    private weak var draggingWindow: NSWindow?
    private var dragTimer: Timer?
    private var isApplyingGeometry = false
    private var isReconcilingVisibility = false
    private var hiddenWithPlayer = false
    private var playerIsMinimizing = false
    private var transferDocking = false

    init() {
        observeWindowPolicy()
    }

    var isTrackingDrag: Bool { dragTimer != nil }
    var observationCount: Int { observers.count + windowObservations.count + (mouseMonitor == nil ? 0 : 1) }

    func bindPlayer(_ window: NSWindow, mode: DisplayMode) {
        guard playerWindow !== window || self.mode != mode else { return }
        let shouldTransfer = transferDocking || edge != nil
        detach(revealHidden: false)
        playerWindow = window
        self.mode = mode
        playerIsMinimizing = false
        transferDocking = false
        updateWindowPolicy()
        installObservations()
        if shouldTransfer { placeDocked(preferred: WindowDockingGeometry.edges(for: mode).first) }
        presentationChanged()
    }

    func prepareForPlayerChange() {
        let shouldTransfer = edge != nil
        detach(revealHidden: false)
        transferDocking = shouldTransfer
        removeObservations()
        playerWindow = nil
    }

    func bindLyrics(_ window: NSWindow, state: LyricsWindowState? = nil) {
        guard lyricsWindow !== window else { return }
        unbindLyrics()
        lyricsState = state ?? LyricsWindowState()
        lyricsWindow = window
        originalCollectionBehavior = window.collectionBehavior
        installObservations()
        updateWindowPolicy()
        presentationChanged()
    }

    func unbindLyrics() {
        detach(revealHidden: false)
        removeObservations()
        lyricsWindow = nil
        transferDocking = false
        lyricsState.isVisible = false
    }

    func shutdown() {
        unbindLyrics()
        playerWindow = nil
    }

    func detach(revealHidden: Bool = true) {
        cancelDrag()
        edge = nil
        lyricsState.isDocked = false
        if let lyricsWindow { lyricsWindow.parent?.removeChildWindow(lyricsWindow) }
        // Detaching through the menu should not leave a hidden independent window.
        let shouldShow = hiddenWithPlayer && revealHidden
        hiddenWithPlayer = false
        updateWindowPolicy()
        if shouldShow { lyricsWindow?.orderFront(nil) }
        presentationChanged()
    }

    func updateWindowPolicy() {
        if mode == .mini {
            playerWindow?.level = SettingsManager.shared.miniAlwaysOnTop ? .floating : .normal
        }
        guard let lyricsWindow else { return }
        if edge != nil, let playerWindow {
            lyricsWindow.level = playerWindow.level
            lyricsWindow.collectionBehavior = playerWindow.collectionBehavior
        } else {
            lyricsWindow.level = SettingsManager.shared.lyricsAlwaysOnTop ? .floating : .normal
            lyricsWindow.collectionBehavior = originalCollectionBehavior
        }
    }

    private func observeWindowPolicy() {
        // One subscription per coordinator, not one lingering subscription per opened window.
        withObservationTracking {
            _ = SettingsManager.shared.lyricsAlwaysOnTop
            _ = SettingsManager.shared.miniAlwaysOnTop
            updateWindowPolicy()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeWindowPolicy() }
        }
    }

    func presentationChanged() {
        guard !isReconcilingVisibility else { return }
        isReconcilingVisibility = true
        defer { isReconcilingVisibility = false }
        guard let lyricsWindow else {
            lyricsState.isVisible = false
            return
        }
        if edge != nil, let playerWindow {
            let playerVisible = playerWindow.isVisible && !playerWindow.isMiniaturized && !playerIsMinimizing
            if !playerVisible, !lyricsWindow.isMiniaturized {
                hiddenWithPlayer = true
                if lyricsWindow.isVisible { lyricsWindow.orderOut(nil) }
            } else if playerVisible, hiddenWithPlayer {
                hiddenWithPlayer = false
                lyricsWindow.orderFront(nil)
            }
            // orderOut removes native parentage; keep the logical docking while hidden.
            if playerVisible, lyricsWindow.isVisible, !lyricsWindow.isMiniaturized,
               lyricsWindow.parent !== playerWindow {
                updateWindowPolicy()
                playerWindow.addChildWindow(lyricsWindow, ordered: .above)
            }
        }
        lyricsState.isVisible = lyricsWindow.isVisible && !lyricsWindow.isMiniaturized
            && !NSApp.isHidden && !hiddenWithPlayer
    }

    func lyricsWillMiniaturize() {
        // A child hidden with its player is not a user-requested minimization.
        if !playerIsMinimizing { detach() }
        lyricsState.isVisible = false
    }

    func snapLyricsIfClose() {
        guard let playerWindow, let lyricsWindow, let screen = playerWindow.screen,
              playerWindow.isVisible, !playerWindow.isMiniaturized,
              !playerWindow.styleMask.contains(.fullScreen), lyricsWindow.isVisible,
              !lyricsWindow.isMiniaturized else { return }
        guard let edge = WindowDockingGeometry.snapEdge(
            player: playerWindow.frame, lyrics: lyricsWindow.frame, mode: mode,
            visibleFrame: screen.visibleFrame, scale: screen.backingScaleFactor
        ) else { return }
        attach(at: edge, screen: screen)
    }

    func revalidateDocking() {
        guard let edge, draggingWindow == nil else { return }
        placeDocked(preferred: edge)
    }

    private func placeDocked(preferred: Edge?) {
        guard let playerWindow, let lyricsWindow, let screen = playerWindow.screen else { return }
        var candidates = WindowDockingGeometry.edges(for: mode)
        if let preferred, candidates.contains(preferred) {
            candidates.removeAll { $0 == preferred }
            candidates.insert(preferred, at: 0)
        }
        for edge in candidates {
            let frame = WindowDockingGeometry.frame(for: edge, player: playerWindow.frame,
                                                    lyricsSize: lyricsWindow.frame.size, scale: screen.backingScaleFactor)
            if screen.visibleFrame.contains(frame) {
                attach(at: edge, screen: screen)
                return
            }
        }
        detach()
        moveLyrics(to: WindowDockingGeometry.clampedOrigin(of: lyricsWindow.frame, to: screen.visibleFrame))
    }

    private func attach(at edge: Edge, screen: NSScreen) {
        guard let playerWindow, let lyricsWindow else { return }
        let target = WindowDockingGeometry.frame(for: edge, player: playerWindow.frame,
                                                 lyricsSize: lyricsWindow.frame.size, scale: screen.backingScaleFactor)
        moveLyrics(to: target.origin)
        self.edge = edge
        lyricsState.isDocked = true
        updateWindowPolicy()
        if lyricsWindow.parent !== playerWindow {
            lyricsWindow.parent?.removeChildWindow(lyricsWindow)
            playerWindow.addChildWindow(lyricsWindow, ordered: .above)
        }
        presentationChanged()
    }

    private func moveLyrics(to origin: NSPoint) {
        guard let lyricsWindow, lyricsWindow.frame.origin != origin else { return }
        isApplyingGeometry = true
        defer { isApplyingGeometry = false }
        lyricsWindow.setFrameOrigin(origin)
    }

    private func attemptBeginDrag(_ window: NSWindow) {
        guard !isApplyingGeometry, draggingWindow == nil, !window.inLiveResize,
              NSEvent.pressedMouseButtons & 1 != 0 else { return }
        let source = mouseDownWindow ?? NSApp.currentEvent?.window
        let isPointerOnWindow = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == window.windowNumber
        // The title bar can be dragged by Window Server without updating NSApp.currentEvent.
        guard source === window || isPointerOnWindow else { return }
        beginDrag(window)
    }

    func beginDrag(_ window: NSWindow) {
        guard !isApplyingGeometry, draggingWindow == nil,
              window === lyricsWindow || window === playerWindow else { return }
        if window === lyricsWindow { detach() }
        draggingWindow = window
        // Window Server dragging may consume mouseUp. Poll only during an actual move.
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if NSEvent.pressedMouseButtons & 1 == 0 { self?.finishDrag() }
            }
        }
        dragTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func finishDrag() {
        guard let dragged = draggingWindow else { cancelDrag(); return }
        cancelDrag()
        if dragged === lyricsWindow { snapLyricsIfClose() }
        else { revalidateDocking() }
    }

    private func cancelDrag() {
        dragTimer?.invalidate()
        dragTimer = nil
        draggingWindow = nil
        mouseDownWindow = nil
    }

    private func observe(_ name: Notification.Name, object: AnyObject?, action: @escaping @MainActor (WindowDockingCoordinator) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        })
    }

    private func installObservations() {
        removeObservations()
        guard let lyricsWindow else { return }
        var windows = [lyricsWindow]
        if let playerWindow { windows.append(playerWindow) }
        for window in windows {
            windowObservations.append(window.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.presentationChanged() }
            })
            observe(NSWindow.willMoveNotification, object: window) { [weak window] coordinator in
                if let window { coordinator.attemptBeginDrag(window) }
            }
            observe(NSWindow.didMoveNotification, object: window) { [weak window] coordinator in
                guard let window, !coordinator.isApplyingGeometry else { return }
                coordinator.attemptBeginDrag(window)
                if window === coordinator.playerWindow { coordinator.revalidateDocking() }
            }
            observe(NSWindow.didDeminiaturizeNotification, object: window) { coordinator in
                coordinator.playerIsMinimizing = false
                coordinator.presentationChanged()
            }
            observe(NSWindow.didMiniaturizeNotification, object: window) { $0.presentationChanged() }
        }
        observe(NSWindow.willMiniaturizeNotification, object: lyricsWindow) { $0.lyricsWillMiniaturize() }
        observe(NSWindow.willCloseNotification, object: lyricsWindow) { $0.unbindLyrics() }
        if let playerWindow {
            observe(NSWindow.willMiniaturizeNotification, object: playerWindow) {
                $0.playerIsMinimizing = true
                $0.presentationChanged()
            }
            observe(NSWindow.willCloseNotification, object: playerWindow) {
                $0.detach()
                $0.playerWindow = nil
                $0.installObservations()
            }
            observe(NSWindow.willEnterFullScreenNotification, object: playerWindow) { $0.detach() }
            observe(NSWindow.didResizeNotification, object: playerWindow) { [weak playerWindow] coordinator in
                if playerWindow?.inLiveResize == false { coordinator.revalidateDocking() }
            }
            observe(NSWindow.didEndLiveResizeNotification, object: playerWindow) { $0.revalidateDocking() }
            observe(NSWindow.didChangeScreenNotification, object: playerWindow) { $0.revalidateDocking() }
        }
        observe(NSApplication.didChangeScreenParametersNotification, object: nil) { $0.revalidateDocking() }
        observe(NSApplication.didResignActiveNotification, object: nil) { $0.cancelDrag() }
        observe(NSApplication.didHideNotification, object: nil) { $0.cancelDrag(); $0.presentationChanged() }
        observe(NSApplication.didUnhideNotification, object: nil) { $0.presentationChanged() }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseDown {
                self.mouseDownWindow = event.window
            } else {
                self.finishDrag()
            }
            return event
        }
    }

    private func removeObservations() {
        cancelDrag()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        windowObservations.forEach { $0.invalidate() }
        windowObservations.removeAll()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }
}
