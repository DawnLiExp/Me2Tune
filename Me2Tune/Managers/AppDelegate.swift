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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowDelegate: WindowInterceptor?
    private var miniWindowController: MiniWindowController?
    private var displayModeCancellable: AnyCancellable?
    private nonisolated(unsafe) var commandWMonitor: Any?
    
    weak var fullModeWindow: NSWindow?
    weak var playerViewModel: PlayerViewModel?
    weak var collectionManager: CollectionManager?
    weak var windowStateMonitor: WindowStateMonitor?
    
    // 记录当前显示模式
    private var currentDisplayMode: DisplayMode = .full
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 启动时总是设置为完整模式
        UserDefaults.standard.set(DisplayMode.full.rawValue, forKey: "displayMode")
        
        setupCommandWHandler()
        configureFullModeWindow()
        setupDisplayModeObserver() // 在窗口配置完成后再监听模式切换
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    // MARK: - Dock Icon Click Handler

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 基于当前运行时状态恢复窗口
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
        
        // ✅ 只在模式真正改变时才切换
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
        
        // ✅ 明确告诉系统：Full 窗口不可见
        windowStateMonitor?.forceSetState(.hidden)
        
        // 隐藏完整模式窗口
        fullModeWindow?.orderOut(nil)
        
        // 创建 Mini 模式窗口
        if miniWindowController == nil {
            miniWindowController = MiniWindowController(playerViewModel: playerViewModel)
        }
        miniWindowController?.show()
        
        logger.info("🎵 Switched to Mini mode")
    }
    
    private func switchToFullMode() {
        // 关闭 Mini 模式窗口
        miniWindowController?.close()
        miniWindowController = nil
        
        // 显示完整模式窗口
        if let window = fullModeWindow {
            window.makeKeyAndOrderFront(nil)
            
            // ✅ Full 窗口重新可见
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
        
        // 延迟加载专辑列表
        Task {
            collectionManager?.scheduleDelayedLoad(delay: 1.5)
        }
    }
    
    // MARK: - Command+W Handler
    
    private func setupCommandWHandler() {
        commandWMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" {
                if let window = NSApp.keyWindow {
                    // 检测是否为 Mini 模式（NSPanel）
                    if window is NSPanel {
                        window.orderOut(nil)
                        logger.debug("⌘+W → Hide Mini window")
                    } else {
                        window.miniaturize(nil)
                        logger.debug("⌘+W → Minimize Full window")
                    }
                }
                return nil
            }
            return event
        }
    }
    
    deinit {
        if let monitor = commandWMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - Window Interceptor

final class WindowInterceptor: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.miniaturize(nil)
        return false
    }
}
