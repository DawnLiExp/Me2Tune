//
//  MiniWindowController.swift
//  Me2Tune
//
//  Mini 模式窗口控制器 - NSPanel 实现
//

import AppKit
import SwiftUI

final class MiniWindowController {
    private var panel: NSPanel?
    private let playerViewModel: PlayerViewModel
    
    init(playerViewModel: PlayerViewModel) {
        self.playerViewModel = playerViewModel
    }
    
    // MARK: - Public Methods
    
    func show() {
        guard panel == nil else {
            panel?.makeKeyAndOrderFront(nil)
            return
        }
        
        createPanel()
    }
    
    func close() {
        panel?.close()
        panel = nil
    }
    
    // MARK: - Private Methods
    
    private func createPanel() {
        let contentView = MiniPlayerView()
            .environmentObject(playerViewModel)
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 440, height: 78)
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 78),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // 窗口配置
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = true
        
        // 圆角效果
        panel.isOpaque = false
        panel.backgroundColor = .clear
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 13
            contentView.layer?.masksToBounds = true
        }
        
        // 窗口行为
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        
        // 监听置顶设置
        setupAlwaysOnTopObserver(for: panel)
        
        // 居中显示
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        
        self.panel = panel
    }
    
    private func setupAlwaysOnTopObserver(for panel: NSPanel) {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak panel] _ in
            let alwaysOnTop = UserDefaults.standard.bool(forKey: "miniAlwaysOnTop")
            Task { @MainActor in
                panel?.level = alwaysOnTop ? .floating : .normal
            }
        }
        
        // 初始状态
        let alwaysOnTop = UserDefaults.standard.bool(forKey: "miniAlwaysOnTop")
        panel.level = alwaysOnTop ? .floating : .normal
    }
}
