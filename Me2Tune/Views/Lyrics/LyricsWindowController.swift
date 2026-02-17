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
            return
        }
        
        createWindow(playerViewModel: playerViewModel)
        logger.info("Lyrics window created")
    }
    
    func close() {
        window?.close()
        window = nil
    }
    
    // MARK: - Private Methods
    
    private func createWindow(playerViewModel: PlayerViewModel) {
        let contentView = LyricsView()
            .environment(playerViewModel)
        
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
        
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(ThemeManager.shared.currentTheme.colors.mainBackground)
        window.isMovableByWindowBackground = true
        
        setupAlwaysOnTopObserver(for: window)
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.window = nil
            }
        }
        
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
    
    private func setupAlwaysOnTopObserver(for window: NSWindow) {
        withObservationTracking {
            let alwaysOnTop = SettingsManager.shared.lyricsAlwaysOnTop
            window.level = alwaysOnTop ? .floating : .normal
        } onChange: { [weak self, weak window] in
            Task { @MainActor in
                guard let window else { return }
                self?.setupAlwaysOnTopObserver(for: window)
            }
        }
    }
}
