//
//  LyricsWindowController.swift
//  Me2Tune
//
//  歌词窗口控制器 - 懒加载和销毁管理
//

import AppKit
import OSLog
import SwiftUI

private let logger = Logger.lyrics

@MainActor
final class LyricsWindowController {
    static let shared = LyricsWindowController()
    
    private var window: LyricsWindow?
    private var dockCoordinator: LyricsWindowDockCoordinator?
    private weak var playerViewModel: PlayerViewModel?
    
    private init() {}
    
    // MARK: - Public Properties & Methods
    
    var isDocked: Bool {
        dockCoordinator?.isDocked ?? false
    }
    
    func undockIfDocked() {
        dockCoordinator?.undock()
    }
    
    func setup(playerViewModel: PlayerViewModel) {
        self.playerViewModel = playerViewModel
    }
    
    func show() {
        guard let playerViewModel else {
            logger.error("PlayerViewModel not available")
            return
        }
        
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        createWindow(playerViewModel: playerViewModel)
        logger.info("Lyrics window created")
    }
    
    func close() {
        dockCoordinator?.cleanup()
        dockCoordinator = nil
        window?.close()
        window = nil
    }
    
    // MARK: - Private Methods
    
    private func resolveMainWindow() -> NSWindow? {
        if let window = (NSApp.delegate as? AppDelegate)?.fullModeWindow {
            return window
        }
        return NSApp.windows.first { !($0 is NSPanel) && $0.identifier?.rawValue == "main" }
    }
    
    private func createWindow(playerViewModel: PlayerViewModel) {
        let contentView = LyricsView()
            .environment(playerViewModel)
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 440, height: 750)
        
        let window = LyricsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = String(localized: "lyrics_window_title")
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(ThemeManager.shared.currentTheme.colors.mainBackground)
        window.isMovableByWindowBackground = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        let main = resolveMainWindow()
        let coordinator = LyricsWindowDockCoordinator(mainWindow: main, lyricsWindow: window)
        window.dockCoordinator = coordinator
        self.dockCoordinator = coordinator
        
        // 初始位置：如果主窗口可见且屏幕有空位，默认吸附到主窗口右侧（空间不足则左侧，都不足则居中）
        if let main, main.isVisible, !main.isMiniaturized, let screen = main.screen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            let rightX = main.frame.maxX
            let leftX = main.frame.minX - 440
            let targetY = main.frame.maxY - window.frame.height
            
            if rightX + 440 <= screenFrame.maxX {
                window.setInitialFrameOrigin(NSPoint(x: rightX, y: targetY))
                coordinator.dock(edge: .right, notify: false)
            } else if leftX >= screenFrame.minX {
                window.setInitialFrameOrigin(NSPoint(x: leftX, y: targetY))
                coordinator.dock(edge: .left, notify: false)
            } else if screenFrame.width >= 495 + 440 {
                // 屏幕宽度足以容纳双面板，自适应微调主窗口位置留出右侧空间并吸附
                let newMainX = screenFrame.minX + max(0, (screenFrame.width - 495 - 440) / 2)
                main.setFrameOrigin(NSPoint(x: newMainX, y: main.frame.minY))
                window.setInitialFrameOrigin(NSPoint(x: main.frame.maxX, y: targetY))
                coordinator.dock(edge: .right, notify: false)
            } else {
                // 极窄屏幕兜底吸附在右侧
                window.setInitialFrameOrigin(NSPoint(x: rightX, y: targetY))
                coordinator.dock(edge: .right, notify: false)
            }
        } else {
            window.center()
        }
        
        setupAlwaysOnTopObserver(for: window)
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dockCoordinator?.cleanup()
                self?.dockCoordinator = nil
                self?.window = nil
            }
        }
        
        window.orderFront(nil)
        main?.makeKey()
        self.window = window
    }
    
    private func setupAlwaysOnTopObserver(for window: NSWindow) {
        withObservationTracking {
            let alwaysOnTop = SettingsManager.shared.lyricsAlwaysOnTop
            if self.dockCoordinator?.isDocked != true {
                window.level = alwaysOnTop ? .floating : .normal
            }
        } onChange: { [weak self, weak window] in
            Task { @MainActor in
                guard let window else { return }
                self?.setupAlwaysOnTopObserver(for: window)
            }
        }
    }
}
