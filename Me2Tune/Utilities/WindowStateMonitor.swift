//
//  WindowStateMonitor.swift
//  Me2Tune
//
//  窗口状态监控 - 检测窗口可见性以优化性能（Full 三档 + Mini 两档）
//

import AppKit
import Foundation
import Observation
import OSLog

private let logger = Logger.app

// MARK: - Window State Monitor

@MainActor
@Observable
final class WindowStateMonitor {
    private(set) var visibilityState: WindowVisibilityState = .activeFocused
    
    // MARK: - Types
    
    enum WindowVisibilityState: Equatable {
        case activeFocused
        case inactive
        case hidden
        case miniVisible
        case miniHidden
        
        var description: String {
            switch self {
            case .activeFocused:
                return "Full前台焦点"
            case .inactive:
                return "Full非活跃"
            case .hidden:
                return "Full隐藏"
            case .miniVisible:
                return "Mini显示"
            case .miniHidden:
                return "Mini最小化"
            }
        }
    }
    
    // MARK: - Computed Properties
    
    var isWindowVisible: Bool {
        return visibilityState == .activeFocused || visibilityState == .inactive
    }
    
    // MARK: - Private Properties
    
    private weak var window: NSWindow?
    private var monitoringTasks: [Task<Void, Never>] = []
    
    private var isAppActive = true
    private var isWindowKey = true
    private var isWindowMinimized = false
    
    private var isMonitoringFullWindow = true
    
    // MARK: - Public Methods
    
    func startMonitoring(window: NSWindow) {
        self.window = window
        isMonitoringFullWindow = true
        
        isAppActive = NSApp.isActive
        isWindowKey = window.isKeyWindow
        isWindowMinimized = window.isMiniaturized
        updateVisibilityState()
        
        startNotificationMonitoring()
        
        logger.info("🔍 Window state monitoring started")
    }
    
    func stopMonitoring() {
        monitoringTasks.forEach { $0.cancel() }
        monitoringTasks.removeAll()
        logger.info("🛑 Window state monitoring stopped")
    }
    
    func forceSetState(_ state: WindowVisibilityState) {
        guard visibilityState != state else { return }
        
        if state == .miniVisible || state == .miniHidden {
            isMonitoringFullWindow = false
        } else {
            isMonitoringFullWindow = true
        }
        
        visibilityState = state
        logger.debug("🔄 Force set visibility: \(state.description)")
    }
    
    func updateMiniWindowState(_ isMinimized: Bool) {
        guard !isMonitoringFullWindow else {
            logger.debug("🔒 Monitoring Full window, ignoring Mini state change")
            return
        }
        
        let newState: WindowVisibilityState = isMinimized ? .miniHidden : .miniVisible
        
        guard visibilityState != newState else { return }
        
        visibilityState = newState
        logger.debug("🔄 Mini visibility changed: \(newState.description)")
    }
    
    // MARK: - Private Methods
    
    private func startNotificationMonitoring() {
        stopMonitoring()
        
        let center = NotificationCenter.default
        
        // App Active
        monitoringTasks.append(Task { [weak self] in
            for await _ in center.notifications(named: NSApplication.didBecomeActiveNotification) {
                self?.handleAppActive(true)
            }
        })
        
        // App Inactive
        monitoringTasks.append(Task { [weak self] in
            for await _ in center.notifications(named: NSApplication.didResignActiveNotification) {
                self?.handleAppActive(false)
            }
        })
        
        // Window Observers
        if let window {
            // Window Key
            monitoringTasks.append(Task { [weak self] in
                for await _ in center.notifications(named: NSWindow.didBecomeKeyNotification, object: window) {
                    self?.handleWindowKey(true)
                }
            })
            
            monitoringTasks.append(Task { [weak self] in
                for await _ in center.notifications(named: NSWindow.didResignKeyNotification, object: window) {
                    self?.handleWindowKey(false)
                }
            })
            
            // Window Miniaturize
            monitoringTasks.append(Task { [weak self] in
                for await _ in center.notifications(named: NSWindow.didMiniaturizeNotification, object: window) {
                    self?.handleWindowMinimized(true)
                }
            })
            
            monitoringTasks.append(Task { [weak self] in
                for await _ in center.notifications(named: NSWindow.didDeminiaturizeNotification, object: window) {
                    self?.handleWindowMinimized(false)
                }
            })
        }
    }
    
    private func handleAppActive(_ isActive: Bool) {
        isAppActive = isActive
        updateVisibilityState()
    }
    
    private func handleWindowKey(_ isKey: Bool) {
        isWindowKey = isKey
        updateVisibilityState()
    }
    
    private func handleWindowMinimized(_ isMinimized: Bool) {
        isWindowMinimized = isMinimized
        updateVisibilityState()
    }
    
    private func updateVisibilityState() {
        guard isMonitoringFullWindow else {
            logger.debug("🔒 Mini mode active, ignoring Full window state change")
            return
        }
        
        let newState: WindowVisibilityState = if isWindowMinimized {
            .hidden
        } else if isAppActive, isWindowKey {
            .activeFocused
        } else {
            .inactive
        }
        
        guard visibilityState != newState else { return }
        
        visibilityState = newState
        logger.debug("🔄 Visibility changed: \(newState.description)")
    }
}
