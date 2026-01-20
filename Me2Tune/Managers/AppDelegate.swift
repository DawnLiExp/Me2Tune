//
//  AppDelegate.swift
//  Me2Tune
//
//  应用代理 - 管理窗口模式切换 + Command+W 支持
//

import AppKit
import Combine
import OSLog
import SwiftUI

private let logger = Logger.app

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowDelegate: WindowInterceptor?
    private var miniWindowController: MiniWindowController?
    
    private var displayModeCancellable: AnyCancellable?
    private var commandWMonitor: Any?
    
    weak var fullModeWindow: NSWindow?
    weak var playerViewModel: PlayerViewModel?
    weak var collectionManager: CollectionManager?
    weak var windowStateMonitor: WindowStateMonitor?
    
    private var currentDisplayMode: DisplayMode = .full
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(DisplayMode.full.rawValue, forKey: "displayMode")
        
        setupCommandWHandler()
        configureFullModeWindow()
        setupDisplayModeObserver()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        cleanup()
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        displayModeCancellable?.cancel()
        displayModeCancellable = nil
        
        if let monitor = commandWMonitor {
            NSEvent.removeMonitor(monitor)
            commandWMonitor = nil
        }
        
        logger.debug("AppDelegate resources cleaned up")
    }
    
    // MARK: - Dock Icon Click Handler

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if miniWindowController != nil {
            miniWindowController?.show()
            logger.debug("🔄 Restored Mini window from Dock")
        } else {
            fullModeWindow?.makeKeyAndOrderFront(nil)
            logger.debug("🔄 Restored Full window from Dock")
        }
        
        return false
    }
    
    // MARK: - Mode Management
    
    private func setupDisplayModeObserver() {
        displayModeCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                self?.handleDisplayModeChange()
            }
    }
    
    private func handleDisplayModeChange() {
        let modeString = UserDefaults.standard.string(forKey: "displayMode") ?? DisplayMode.full.rawValue
        guard let mode = DisplayMode(rawValue: modeString) else { return }
        
        guard mode != currentDisplayMode else { return }
        currentDisplayMode = mode
        
        if mode == .mini {
            switchToMiniMode()
        } else {
            switchToFullMode()
        }
    }
    
    private func switchToMiniMode() {
        guard let playerViewModel else {
            logger.error("PlayerViewModel not available")
            return
        }
        
        fullModeWindow?.orderOut(nil)
        
        windowStateMonitor?.forceSetState(.miniVisible)
        playerViewModel.updateWindowVisibility(.miniVisible)
        
        if miniWindowController == nil {
            miniWindowController = MiniWindowController(
                playerViewModel: playerViewModel,
                windowStateMonitor: windowStateMonitor
            )
        }
        miniWindowController?.show()
        
        logger.info("🎵 Switched to Mini mode")
    }

    private func switchToFullMode() {
        miniWindowController?.close()
        miniWindowController = nil
        
        if let window = fullModeWindow {
            window.makeKeyAndOrderFront(nil)
            
            windowStateMonitor?.forceSetState(.activeFocused)
            
            logger.info("🖥️ Switched to Full mode")
        } else {
            logger.error("Full mode window not available")
        }
    }
    
    private func configureFullModeWindow() {
        guard let window = fullModeWindow else { return }
        
        windowDelegate = WindowInterceptor()
        window.delegate = windowDelegate
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        
        windowStateMonitor?.startMonitoring(window: window)
        
        Task { @MainActor [weak collectionManager] in
            collectionManager?.scheduleDelayedLoad(delay: 1.5)
        }
    }
    
    // MARK: - Command+W Handler
    
    private func setupCommandWHandler() {
        commandWMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" {
                let mouseLocation = NSEvent.mouseLocation
                
                for window in NSApp.windows where window.isVisible {
                    let windowFrame = window.frame
                    
                    if windowFrame.contains(mouseLocation) {
                        self.handleCommandW(for: window, reason: "mouse inside")
                        return nil
                    }
                }
                
                if let window = NSApp.keyWindow {
                    self.handleCommandW(for: window, reason: "fallback to keyWindow")
                }
                
                return nil
            }
            return event
        }
    }

    private func handleCommandW(for window: NSWindow, reason: String) {
        if window is NSPanel {
            window.orderOut(nil)
            logger.debug("⌘+W → Hide Mini window (\(reason))")
            return
        }
        
        if window.title.contains("歌词") || window.title.contains("Lyrics") {
            window.miniaturize(nil)
            logger.debug("⌘+W → Minimize Lyrics window (\(reason))")
            return
        }
        
        window.miniaturize(nil)
        logger.debug("⌘+W → Minimize Full window (\(reason))")
    }
}

// MARK: - Window Interceptor

final class WindowInterceptor: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.miniaturize(nil)
        return false
    }
}
