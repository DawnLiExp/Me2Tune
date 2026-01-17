//
//  WindowStateMonitor.swift
//  Me2Tune
//
//  窗口状态监控 - 优化版（动态监听 + 防抖）
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
        case activeFocused
        case inactive
        case hidden
        
        var updateInterval: TimeInterval {
            switch self {
            case .activeFocused:
                return 0.3
            case .inactive:
                return 0.5
            case .hidden:
                return 2.0
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
    
    // 简化状态追踪：只需 2 个核心状态
    private var isMinimized = false
    private var isAppActive = true
    
    // 防抖任务
    private var debounceTask: Task<Void, Never>?
    
    // 动态焦点监听器引用
    private var focusObservers: [Any] = []
    
    // MARK: - Public Methods
    
    func startMonitoring(window: NSWindow) {
        self.window = window
        
        // 初始状态
        isMinimized = window.isMiniaturized
        isAppActive = NSApp.isActive
        updateVisibilityState()
        
        // ========== 核心监听（始终启用）==========
        
        // 1. 应用前后台切换
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppActivated()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppDeactivated()
            }
            .store(in: &cancellables)
        
        // 2. 窗口最小化/恢复
        NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification, object: window)
            .sink { [weak self] _ in
                self?.handleMinimized()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification, object: window)
            .sink { [weak self] _ in
                self?.handleRestored()
            }
            .store(in: &cancellables)
        
        // ========== 焦点监听（动态启用）==========
        
        // 只在前台+非最小化时监听焦点
        if !isMinimized && isAppActive {
            enableFocusMonitoring()
        }
        
        logger.info("🔍 Window monitoring started (optimized)")
    }
    
    func stopMonitoring() {
        debounceTask?.cancel()
        disableFocusMonitoring()
        cancellables.removeAll()
        window = nil
    }
    
    func forceSetState(_ state: WindowVisibilityState) {
        guard visibilityState != state else { return }
        visibilityState = state
        logger.debug("🔄 Force set: \(state.description)")
    }
    
    // MARK: - Dynamic Focus Monitoring
    
    private func enableFocusMonitoring() {
        guard let window, focusObservers.isEmpty else { return }
        
        let becomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleFocusGained()
            }
        }
        
        let resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleFocusLost()
            }
        }
        
        focusObservers = [becomeKeyObserver, resignKeyObserver]
        logger.debug("✅ Focus monitoring enabled")
    }
    
    private func disableFocusMonitoring() {
        guard !focusObservers.isEmpty else { return }
        
        focusObservers.forEach { NotificationCenter.default.removeObserver($0) }
        focusObservers.removeAll()
        logger.debug("❌ Focus monitoring disabled")
    }
    
    // MARK: - Event Handlers
    
    private func handleAppActivated() {
        isAppActive = true
        
        // 恢复焦点监听
        if !isMinimized {
            enableFocusMonitoring()
        }
        
        debounceStateUpdate(delay: 0.3)
    }
    
    private func handleAppDeactivated() {
        isAppActive = false
        
        // 禁用焦点监听（后台时不需要）
        disableFocusMonitoring()
        
        debounceStateUpdate(delay: 0.3)
    }
    
    private func handleMinimized() {
        isMinimized = true
        
        // 禁用焦点监听（最小化时不需要）
        disableFocusMonitoring()
        
        // 立即切换到 hidden 状态（无延迟）
        updateVisibilityState()
    }
    
    private func handleRestored() {
        isMinimized = false
        
        // 恢复焦点监听
        if isAppActive {
            enableFocusMonitoring()
        }
        
        // 优先恢复（100ms 延迟）
        debounceStateUpdate(delay: 0.1)
    }
    
    private func handleFocusGained() {
        debounceStateUpdate(delay: 0.5)
    }
    
    private func handleFocusLost() {
        debounceStateUpdate(delay: 0.5)
    }
    
    // MARK: - State Update with Debounce
    
    private func debounceStateUpdate(delay: TimeInterval) {
        debounceTask?.cancel()
        
        debounceTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            } catch {
                return
            }
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self.updateVisibilityState()
            }
        }
    }
    
    private func updateVisibilityState() {
        let newState: WindowVisibilityState
        
        if isMinimized {
            newState = .hidden
        } else if isAppActive, window?.isKeyWindow == true {
            newState = .activeFocused
        } else {
            newState = .inactive
        }
        
        guard visibilityState != newState else { return }
        
        visibilityState = newState
        logger.debug("🔄 Visibility: \(newState.description) (interval: \(String(format: "%.1f", newState.updateInterval))s)")
    }
    
}
