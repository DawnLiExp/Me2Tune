//
//  AppDelegate.swift
//  Me2Tune
//
//  应用代理 - 管理窗口模式切换 + 文件打开处理
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
    
    // ✅ WindowStateMonitor 由 AppDelegate 持有，确保生命周期稳定
    var windowStateMonitor: WindowStateMonitor?
    
    private var currentDisplayMode: DisplayMode = .full
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // ✅ 确保启动时总是Full模式
        UserDefaults.standard.set(DisplayMode.full.rawValue, forKey: "displayMode")
        
        setupCommandWHandler()
        configureFullModeWindow()
        setupDisplayModeObserver()
        
        logger.info("🚀 Application launched successfully")
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
        logger.debug("📂 Open single file: \(filename)")
        let url = URL(fileURLWithPath: filename)
        handleOpenFiles([url])
        return true
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        logger.info("📂 Open \(urls.count) file(s) from system")
        handleOpenFiles(urls)
    }
    
    /// ✅ 优化：简化文件处理逻辑，避免复杂的异步时序
    private func handleOpenFiles(_ urls: [URL]) {
        guard let playerViewModel else {
            logger.error("❌ PlayerViewModel not available for file opening")
            return
        }
        
        let supportedExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ape", "wv", "tta", "mpc"]
        
        // 过滤音频文件
        let audioFiles = urls.filter { url in
            supportedExtensions.contains(url.pathExtension.lowercased())
        }
        
        guard !audioFiles.isEmpty else {
            logger.warning("⚠️ No supported audio files in selection")
            return
        }
        
        logger.info("✅ Processing \(audioFiles.count) audio file(s)")
        
        // ✅ 第一步：同步切换到Full模式（如果需要）
        if currentDisplayMode == .mini {
            logger.debug("🔄 Switching from Mini to Full mode for file opening")
            UserDefaults.standard.set(DisplayMode.full.rawValue, forKey: "displayMode")
            // displayModeObserver会自动处理切换，无需手动延迟
        }
        
        // ✅ 第二步：激活主窗口（同步操作，避免闪烁）
        activateMainWindow()
        
        // ✅ 第三步：异步添加文件并播放
        Task { @MainActor in
            let startIndex = playerViewModel.playlistManager.tracks.count
            
            // 批量添加到播放列表
            playerViewModel.addTracksToPlaylist(urls: audioFiles)
            
            // 等待列表更新完成
            try? await Task.sleep(for: .milliseconds(300))
            
            // 播放第一首新添加的曲目
            if playerViewModel.playlistManager.tracks.indices.contains(startIndex) {
                playerViewModel.playPlaylistTrack(at: startIndex)
                logger.info("▶️ Started playing from index \(startIndex)")
            }
        }
    }
    
    // MARK: - Window Activation
    
    /// ✅ 优化：更健壮的窗口激活逻辑
    private func activateMainWindow() {
        // 优先级：fullModeWindow > 标识符匹配 > 第一个非Panel窗口
        let targetWindow: NSWindow? = {
            if let window = fullModeWindow {
                return window
            }
            
            if let window = NSApp.windows.first(where: { window in
                !(window is NSPanel) && window.identifier?.rawValue == "main"
            }) {
                return window
            }
            
            return NSApp.windows.first { !($0 is NSPanel) }
        }()
        
        guard let window = targetWindow else {
            logger.error("❌ No suitable window found for activation")
            return
        }
        
        // ✅ 确保窗口可见且激活
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        logger.debug("🎯 Activated window: \(window.title.isEmpty ? "Untitled" : window.title)")
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        displayModeCancellable?.cancel()
        displayModeCancellable = nil
        
        if let monitor = commandWMonitor {
            NSEvent.removeMonitor(monitor)
            commandWMonitor = nil
        }
        
        logger.debug("🧹 AppDelegate resources cleaned up")
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
    
    // MARK: - Display Mode Management
    
    private func setupDisplayModeObserver() {
        displayModeCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                self?.handleDisplayModeChange()
            }
    }
    
    /// ✅ 优化：改进模式切换逻辑，避免重复切换
    private func handleDisplayModeChange() {
        let modeString = UserDefaults.standard.string(forKey: "displayMode") ?? DisplayMode.full.rawValue
        guard let mode = DisplayMode(rawValue: modeString) else { return }
        
        guard mode != currentDisplayMode else { return }
        
        let oldMode = currentDisplayMode
        currentDisplayMode = mode
        
        logger.info("🔄 Display mode change: \(oldMode.rawValue) → \(mode.rawValue)")
        
        if mode == .mini {
            switchToMiniMode()
        } else {
            switchToFullMode()
        }
    }
    
    private func switchToMiniMode() {
        guard let playerViewModel else {
            logger.error("❌ PlayerViewModel not available for Mini mode")
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
            logger.error("❌ Full mode window not available")
        }
    }
    
    /// ✅ 优化：改进窗口初始化顺序
    private func configureFullModeWindow() {
        guard let window = fullModeWindow else {
            logger.error("❌ Full mode window not set")
            return
        }
        
        windowDelegate = WindowInterceptor()
        window.delegate = windowDelegate
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        
        // ✅ WindowStateMonitor 的 startMonitoring 在 Me2TuneApp 中调用
        // 延迟加载专辑收藏
        Task { @MainActor [weak collectionManager] in
            collectionManager?.scheduleDelayedLoad(delay: 1.5)
        }
        
        logger.debug("✅ Full mode window configured")
    }
    
    // MARK: - Command+W Handler
    
    private func setupCommandWHandler() {
        commandWMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" {
                let mouseLocation = NSEvent.mouseLocation
                
                // 检测鼠标位置对应的窗口
                for window in NSApp.windows where window.isVisible {
                    let windowFrame = window.frame
                    
                    if windowFrame.contains(mouseLocation) {
                        self.handleCommandW(for: window, reason: "mouse inside")
                        return nil
                    }
                }
                
                // 降级到 keyWindow
                if let window = NSApp.keyWindow {
                    self.handleCommandW(for: window, reason: "fallback to keyWindow")
                }
                
                return nil
            }
            return event
        }
        
        logger.debug("✅ Command+W handler installed")
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
