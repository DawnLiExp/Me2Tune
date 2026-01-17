//
//  MiniWindowController.swift
//  Me2Tune
//
//  Mini 模式窗口控制器 - NSPanel 实现 + 最小化检测
//

import AppKit
import SwiftUI

final class MiniWindowController {
    private var panel: NSPanel?
    private let playerViewModel: PlayerViewModel
    private weak var windowStateMonitor: WindowStateMonitor?
    
    init(playerViewModel: PlayerViewModel, windowStateMonitor: WindowStateMonitor?) {
        self.playerViewModel = playerViewModel
        self.windowStateMonitor = windowStateMonitor
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
    
    // ✅ 窗口隐藏/最小化时调用
    func handleWindowHidden() {
        windowStateMonitor?.updateMiniWindowState(true)
    }
    
    // ✅ 窗口显示/恢复时调用
    func handleWindowVisible() {
        windowStateMonitor?.updateMiniWindowState(false)
    }
    
    // MARK: - Private Methods
    
    private func createPanel() {
        let contentView = MiniPlayerView()
            .environmentObject(playerViewModel)
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 440, height: 78)
        
        let panel = MiniPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 78),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // ✅ 建立双向关联
        panel.controller = self
        
        // 窗口配置
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        
        // 圆角效果
        panel.isOpaque = false
        panel.backgroundColor = .clear
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 12
            contentView.layer?.masksToBounds = true
        }
        
        // 窗口行为
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        panel.hidesOnDeactivate = false
        
        // 监听置顶设置
        setupAlwaysOnTopObserver(for: panel)
        
        // 居中显示
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        
        // ✅ 初始状态：Mini 显示
        windowStateMonitor?.forceSetState(.miniVisible)
        
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

// MARK: - Custom Mini Panel

private final class MiniPanel: NSPanel {
    weak var controller: MiniWindowController?
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return false
    }
    
    // ✅ 处理 Command+W
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "w"
        {
            orderOut(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    
    // ✅ 重写 orderOut - 统一处理为最小化状态
    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        controller?.handleWindowHidden()
    }
    
    // ✅ 重写 miniaturize - 统一处理为最小化状态
    override func miniaturize(_ sender: Any?) {
        super.miniaturize(sender)
        controller?.handleWindowHidden()
    }
    
    // ✅ 窗口恢复时调用
    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        controller?.handleWindowVisible()
    }
}
