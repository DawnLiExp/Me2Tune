//
//  WindowStateMonitor.swift
//  Me2Tune
//
//  窗口状态监控 - 检测窗口可见性以优化性能
//

import AppKit
import Combine
import Foundation

@MainActor
final class WindowStateMonitor: ObservableObject {
    @Published private(set) var isWindowVisible = true
    
    private var cancellables = Set<AnyCancellable>()
    private weak var window: NSWindow?
    
    func startMonitoring(window: NSWindow) {
        self.window = window
        
        // 初始状态
        isWindowVisible = !window.isMiniaturized
        
        // 监听窗口最小化
        NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification, object: window)
            .sink { [weak self] _ in
                self?.isWindowVisible = false
            }
            .store(in: &cancellables)
        
        // 监听窗口恢复
        NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification, object: window)
            .sink { [weak self] _ in
                self?.isWindowVisible = true
            }
            .store(in: &cancellables)
    }
    
    func stopMonitoring() {
        cancellables.removeAll()
        window = nil
    }
}
