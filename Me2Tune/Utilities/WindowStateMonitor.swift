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
        case activeFocused
        case inactive
        case hidden
        case miniVisible
        case miniHidden
        
        var updateInterval: TimeInterval {
            switch self {
            case .activeFocused:
                return 0.3
            case .inactive:
                return 0.5
            case .hidden:
                return 2.0
            case .miniVisible:
                return 1.0
            case .miniHidden:
                return 2.0
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
    
    // ✅ 并发安全说明：
    // cancellables使用nonisolated(unsafe)是安全的，因为：
    // 1. Set.removeAll()是线程安全的
    // 2. deinit时对象已进入销毁阶段，不会有并发访问
    // 3. Combine的AnyCancellable.cancel()设计为可以在任何线程调用
    private nonisolated(unsafe) var cancellables = Set<AnyCancellable>()
    private weak var window: NSWindow?
    
    private var isAppActive = true
    private var isWindowKey = true
    private var isWindowMinimized = false
    
    private var isMonitoringFullWindow = true
    
    // MARK: - Lifecycle
    
    // ✅ 并发安全：cancellables.removeAll()是线程安全的
    nonisolated deinit {
        cancellables.removeAll()
    }
    
    // MARK: - Public Methods
    
    func startMonitoring(window: NSWindow) {
        self.window = window
        isMonitoringFullWindow = true
        
        isAppActive = NSApp.isActive
        isWindowKey = window.isKeyWindow
        isWindowMinimized = window.isMiniaturized
        updateVisibilityState()
        
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
    
    func forceSetState(_ state: WindowVisibilityState) {
        guard visibilityState != state else { return }
        
        if state == .miniVisible || state == .miniHidden {
            isMonitoringFullWindow = false
        } else {
            isMonitoringFullWindow = true
        }
        
        visibilityState = state
        NotificationCenter.default.post(name: .windowVisibilityDidChange, object: state)
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
        NotificationCenter.default.post(name: .windowVisibilityDidChange, object: newState)
        logger.debug("🔄 Mini visibility changed: \(newState.description) (interval: \(String(format: "%.1f", newState.updateInterval))s)")
    }
    
    // MARK: - Private Methods
    
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
        NotificationCenter.default.post(name: .windowVisibilityDidChange, object: newState)
        logger.debug("🔄 Visibility changed: \(newState.description) (interval: \(String(format: "%.1f", newState.updateInterval))s)")
    }
}
