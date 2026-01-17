//
//  WindowStateMonitor.swift
//  Me2Tune
//
//  窗口状态监控 - 检测窗口可见性以优化性能（三档刷新频率）
//

import AppKit
import Combine
import Foundation
import OSLog

private let logger = Logger.app

@MainActor
final class WindowStateMonitor: ObservableObject {
    @Published private(set) var visibilityState: WindowVisibilityState = .activeFocused
    
    // MARK: - Types
    
    enum WindowVisibilityState: Equatable {
        case activeFocused // 前台+焦点（最高频率）
        case inactive // 前台无焦点或后台（中等频率）
        case hidden // 完全隐藏/最小化（最低频率）
        
        var updateInterval: TimeInterval {
            switch self {
            case .activeFocused:
                return 0.3 // 5fps - 流畅体验
            case .inactive:
                return 0.5 // 1fps - 平衡
            case .hidden:
                return 2.0 // 0.5fps - 省电
            }
        }
        
        var description: String {
            switch self {
            case .activeFocused:
                return "前台焦点"
            case .inactive:
                return "非活跃"
            case .hidden:
                return "隐藏"
            }
        }
    }
    
    // MARK: - Computed Properties
    
    var isWindowVisible: Bool {
        return visibilityState != .hidden
    }
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private weak var window: NSWindow?
    
    private var isAppActive = true
    private var isWindowKey = true
    private var isWindowMinimized = false
    
    // MARK: - Public Methods
    
    func startMonitoring(window: NSWindow) {
        self.window = window
        
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
        visibilityState = state
        logger.debug("🔄 Force set visibility: \(state.description)")
    }
    
    // MARK: - Private Methods
    
    private func updateVisibilityState() {
        let newState: WindowVisibilityState = if isWindowMinimized {
            .hidden
        } else if isAppActive, isWindowKey {
            .activeFocused
        } else {
            // 前台无焦点 或 后台 → 统一为非活跃
            .inactive
        }
        
        guard visibilityState != newState else { return }
        
        visibilityState = newState
        logger.debug("🔄 Visibility changed: \(newState.description) (interval: \(String(format: "%.1f", newState.updateInterval))s)")
    }
}
