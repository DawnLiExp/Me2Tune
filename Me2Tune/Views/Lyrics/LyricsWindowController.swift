//
//  LyricsWindowController.swift
//  Me2Tune
//
//  歌词窗口控制器 - 懒加载和销毁管理
//

import AppKit
import SwiftUI
import OSLog

private nonisolated let logger = Logger(subsystem: "me2.Me2Tune", category: "Lyrics")

@MainActor
final class LyricsWindowController {
    static let shared = LyricsWindowController()
    
    private var window: NSWindow?
    private weak var playerViewModel: PlayerViewModel?
    
    private init() {}
    
    // MARK: - Public Methods
    
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
            logger.debug("Lyrics window shown (existing)")
            return
        }
        
        createWindow(playerViewModel: playerViewModel)
        logger.info("Lyrics window created and shown")
    }
    
    func close() {
        window?.close()
        window = nil
        logger.debug("Lyrics window closed")
    }
    
    // MARK: - Private Methods
    
    private func createWindow(playerViewModel: PlayerViewModel) {
        let contentView = LyricsView()
            .environmentObject(playerViewModel)
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 440, height: 800)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = String(localized: "lyrics_window_title")
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.center()
        
        // 隐藏标题栏但保留窗口按钮
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        // 背景色与主题一致
        window.backgroundColor = NSColor(ThemeManager.shared.currentTheme.colors.mainBackground)
        
        // 监听置顶设置
        setupAlwaysOnTopObserver(for: window)
        
        // 窗口关闭时清理
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.window = nil
            }
            logger.debug("Lyrics window will close, clearing reference")
        }
        
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
    
    private func setupAlwaysOnTopObserver(for window: NSWindow) {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak window] _ in
            let alwaysOnTop = UserDefaults.standard.bool(forKey: "lyricsAlwaysOnTop")
            Task { @MainActor in
                window?.level = alwaysOnTop ? .floating : .normal
            }
        }
        
        // 初始状态
        let alwaysOnTop = UserDefaults.standard.bool(forKey: "lyricsAlwaysOnTop")
        window.level = alwaysOnTop ? .floating : .normal
    }
}
