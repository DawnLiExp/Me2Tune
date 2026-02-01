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
    
    // ✅ 关键优化：WindowStateMonitor 不再是 weak（AppDelegate 持有它）
    var windowStateMonitor: WindowStateMonitor?
    
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
        RemoteCommandController.shared.disable()
        
        if let viewModel = playerViewModel {
            viewModel.saveState()
            logger.info("💾 Playback state saved on termination")
        }
        
        cleanup()
    }
    
    // MARK: - File Opening
    
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        handleOpenFiles([url])
        return true
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        handleOpenFiles(urls)
    }
    
    private func handleOpenFiles(_ urls: [URL]) {
        guard let playerViewModel else {
            logger.error("PlayerViewModel not available for file opening")
            return
        }
        
        let supportedExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ape", "wv", "tta", "mpc"]
        
        // 过滤出支持的音频文件
        let audioFiles = urls.filter { url in
            supportedExtensions.contains(url.pathExtension.lowercased())
        }
        
        guard !audioFiles.isEmpty else {
            logger.warning("No supported audio files in selection")
            return
        }
        
        logger.info("📂 Opening \(audioFiles.count) file(s)")
        
        // 切换到全屏模式(如果在 Mini 模式)
        if currentDisplayMode == .mini {
            UserDefaults.standard.set(DisplayMode.full.rawValue, forKey: "displayMode")
            // 等待模式切换完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.activateMainWindow()
            }
        } else {
            activateMainWindow()
        }
        
        // 批量添加到播放列表并播放第一首
        Task { @MainActor in
            let startIndex = playerViewModel.playlistManager.tracks.count
            
            playerViewModel.addTracksToPlaylist(urls: audioFiles)
            
            // 等待加载完成后播放第一首新添加的曲目
            try? await Task.sleep(for: .milliseconds(500))
            
            if playerViewModel.playlistManager.tracks.indices.contains(startIndex) {
                playerViewModel.playPlaylistTrack(at: startIndex)
            }
        }
    }
    
    // MARK: - Window Activation Helper
    
    private func activateMainWindow() {
        // 查找主窗口（非 Mini 模式的窗口）
        if let mainWindow = NSApp.windows.first(where: { window in
            !(window is NSPanel) && window.identifier?.rawValue == "main"
        }) {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            logger.debug("🎯 Activated existing main window")
        } else if let window = fullModeWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            logger.debug("🎯 Activated full mode window")
        } else {
            // 备用方案：激活第一个非 Panel 窗口
            if let firstWindow = NSApp.windows.first(where: { !($0 is NSPanel) }) {
                firstWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                logger.debug("🎯 Activated first available window")
            }
        }
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
        
        // ✅ 注意：WindowStateMonitor 的 startMonitoring 在 Me2TuneApp 中调用
        
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
