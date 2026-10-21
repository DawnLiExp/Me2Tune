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
    
    private(set) var window: NSWindow?
    private weak var playerViewModel: PlayerViewModel?
    private weak var dockingCoordinator: WindowDockingCoordinator?
    private var closeObserver: NSObjectProtocol?
    
    private init() {}
    
    // MARK: - Public Methods
    
    func setup(playerViewModel: PlayerViewModel, dockingCoordinator: WindowDockingCoordinator) {
        self.playerViewModel = playerViewModel
        self.dockingCoordinator = dockingCoordinator
    }
    
    func show() {
        guard let playerViewModel else {
            logger.error("PlayerViewModel not available")
            return
        }
        
        if let existingWindow = window {
            if existingWindow.isMiniaturized { existingWindow.deminiaturize(nil) }
            existingWindow.makeKeyAndOrderFront(nil)
            dockingCoordinator?.presentationChanged()
            return
        }
        
        createWindow(playerViewModel: playerViewModel)
        logger.info("Lyrics window created")
    }
    
    func close() {
        window?.close()
    }
    
    // MARK: - Private Methods
    
    private func createWindow(playerViewModel: PlayerViewModel) {
        guard let dockingCoordinator else { return }
        let windowState = LyricsWindowState()
        let contentView = LyricsView(windowState: windowState, onDetach: { [weak dockingCoordinator] in
            dockingCoordinator?.detach()
        })
            .environment(playerViewModel)
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 440, height: 800)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 800),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = String(localized: "lyrics_window_title")
        window.identifier = NSUserInterfaceItemIdentifier("lyrics")
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.center()
        
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(ThemeManager.shared.currentTheme.colors.mainBackground)
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        self.window = window
        dockingCoordinator.bindLyrics(window, state: windowState)

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.dockingCoordinator?.unbindLyrics()
                self.window = nil
                if let observer = self.closeObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.closeObserver = nil
                }
            }
        }
        
        window.makeKeyAndOrderFront(nil)
        dockingCoordinator.presentationChanged()
    }
}
