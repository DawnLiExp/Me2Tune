//
//  WindowStateMonitor.swift
//  Me2Tune
//
//  窗口状态监控 - 检测窗口可见性以优化性能（Full 三档 + Mini 两档）
//

import AppKit
import Combine
import Foundation
import OSLog

private let logger = Logger.app

// MARK: - Notification Extension

extension Notification.Name {
    static let windowVisibilityDidChange = Notification.Name("WindowVisibilityDidChange")
}

// MARK: - Window State Monitor

@MainActor
final class WindowStateMonitor: ObservableObject {
    @Published private(set) var visibilityState: WindowVisibilityState = .activeFocused
    
    // MARK: - Types
    
    enum WindowVisibilityState: Equatable {
        case activeFocused // Full 前台+焦点（最高频率）
        case inactive // Full 前台无焦点或后台（中等频率）
        case hidden // Full 完全隐藏/最小化（最低频率）
        case miniVisible // Mini 显示状态（前台/后台）
        case miniHidden // Mini 最小化到 dock
        
        var updateInterval: TimeInterval {
            switch self {
            case .activeFocused:
                return 0.3 // 5fps - 流畅体验
            case .inactive:
                return 0.5 // 1fps - 平衡
            case .hidden:
                return 2.0 // 0.5fps - 省电
            case .miniVisible:
                return 1.0 // 1fps - Mini 显示
            case .miniHidden:
                return 2.0 // 0.5fps - Mini 最小化
            }
        }
        
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
    
    private var cancellables = Set<AnyCancellable>()
    private weak var window: NSWindow?
    
    private var isAppActive = true
    private var isWindowKey = true
    private var isWindowMinimized = false
    
    // ✅ 新逻辑：区分是否正在监听 Full 窗口
    private var isMonitoringFullWindow = true
    
    // MARK: - Public Methods
    
    func startMonitoring(window: NSWindow) {
        self.window = window
        isMonitoringFullWindow = true
        
        // 初始状态
        isAppActive = NSApp.isActive
        isWindowKey = window.isKeyWindow
        isWindowMinimized = window.isMiniaturized
        updateVisibilityState()
        
        // 监听应用前后台切换
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.isAppActive = true
                self?.updateVisibilityState()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                self?.isAppActive = false
                self?.updateVisibilityState()
            }
            .store(in: &cancellables)
        
        // 监听窗口焦点变化
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification, object: window)
            .sink { [weak self] _ in
                self?.isWindowKey = true
                self?.updateVisibilityState()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: window)
            .sink { [weak self] _ in
                self?.isWindowKey = false
                self?.updateVisibilityState()
            }
            .store(in: &cancellables)
        
        // 监听窗口最小化/恢复
        NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification, object: window)
            .sink { [weak self] _ in
                self?.isWindowMinimized = true
                self?.updateVisibilityState()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification, object: window)
            .sink { [weak self] _ in
                self?.isWindowMinimized = false
                self?.updateVisibilityState()
            }
            .store(in: &cancellables)
        
        logger.info("🔍 Window state monitoring started")
    }
    
    func stopMonitoring() {
        cancellables.removeAll()
        window = nil
    }
    
    func forceSetState(_ state: WindowVisibilityState) {
        guard visibilityState != state else { return }
        
        // ✅ 进入 Mini 模式时，停止监听 Full 窗口事件
        if state == .miniVisible || state == .miniHidden {
            isMonitoringFullWindow = false
        } else {
            // 离开 Mini 模式，恢复监听 Full 窗口
            isMonitoringFullWindow = true
        }
        
        visibilityState = state
        NotificationCenter.default.post(name: .windowVisibilityDidChange, object: state)
        logger.debug("🔄 Force set visibility: \(state.description)")
    }
    
    /// Mini 模式专用：更新 Mini 窗口状态（显示/最小化）
    func updateMiniWindowState(_ isMinimized: Bool) {
        guard !isMonitoringFullWindow else {
            logger.debug("🔒 Monitoring Full window, ignoring Mini state change")
            return
        }
        
        let newState: WindowVisibilityState = isMinimized ? .miniHidden : .miniVisible
        
        guard visibilityState != newState else { return }
        
        visibilityState = newState
        NotificationCenter.default.post(name: .windowVisibilityDidChange, object: newState)
        logger.debug("🔄 Mini visibility changed: \(newState.description) (interval: \(String(format: "%.1f", newState.updateInterval))s)")
    }
    
    // MARK: - Private Methods
    
    private func updateVisibilityState() {
        // ✅ 如果正在 Mini 模式，忽略 Full 窗口事件
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
        NotificationCenter.default.post(name: .windowVisibilityDidChange, object: newState)
        logger.debug("🔄 Visibility changed: \(newState.description) (interval: \(String(format: "%.1f", newState.updateInterval))s)")
    }
}
