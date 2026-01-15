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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupCommandWHandler()
        setupDisplayModeObserver()
        
        // 立即应用初始模式（无延迟）
        applyInitialMode()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    // MARK: - Dock Icon Click Handler

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let mode = UserDefaults.standard.string(forKey: "displayMode") ?? DisplayMode.full.rawValue
        
        if mode == DisplayMode.mini.rawValue {
            // ✅ 先强制隐藏 Full 窗口（防止系统自动恢复）
            fullModeWindow?.orderOut(nil)
            windowStateMonitor?.isWindowVisible = false
            
            // 然后显示 Mini 窗口
            miniWindowController?.show()
            logger.debug("🔄 Restored Mini window from Dock")
            
            return false // ✅ 阻止系统默认行为
        } else {
            // 先关闭 Mini 窗口
            miniWindowController?.close()
            
            // 然后显示 Full 窗口
            fullModeWindow?.makeKeyAndOrderFront(nil)
            windowStateMonitor?.isWindowVisible = true
            logger.debug("🔄 Restored Full window from Dock")
            
            return false // ✅ 阻止系统默认行为
        }
    }
    
    // MARK: - Mode Management
    
    private func setupDisplayModeObserver() {
        displayModeCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                self?.handleDisplayModeChange()
            }
    }
    
    private func applyInitialMode() {
        let mode = UserDefaults.standard.string(forKey: "displayMode") ?? DisplayMode.full.rawValue
        
        if mode == DisplayMode.mini.rawValue {
            // 立即隐藏 Full 模式窗口
            fullModeWindow?.orderOut(nil)
            
            // 等待 playerViewModel 注入后创建 Mini 窗口
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.switchToMiniMode()
            }
        } else {
            configureFullModeWindow()
        }
    }
    
    private func handleDisplayModeChange() {
        let mode = UserDefaults.standard.string(forKey: "displayMode") ?? DisplayMode.full.rawValue
        
        if mode == DisplayMode.mini.rawValue {
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
        
        // 通知窗口不可见，停止所有刷新
        windowStateMonitor?.isWindowVisible = false
        
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
            
            // 恢复窗口可见状态
            windowStateMonitor?.isWindowVisible = true
            
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
        // displayModeCancellable 会自动在释放时取消订阅
    }
}

// MARK: - Window Interceptor

final class WindowInterceptor: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.miniaturize(nil)
        return false
    }
}
