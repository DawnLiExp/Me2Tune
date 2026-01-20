//
//  MiniWindowController.swift
//  Me2Tune
//
//  Mini 模式窗口控制器 - NSPanel 实现 + 最小化检测
//

import AppKit
import SwiftUI

// ✅ 标记MainActor：所有UI操作必须在主线程
@MainActor
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
    
    func handleWindowHidden() {
        windowStateMonitor?.updateMiniWindowState(true)
    }
    
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
        
        panel.controller = self
        
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        
        panel.isOpaque = false
        panel.backgroundColor = .clear
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 12
            contentView.layer?.masksToBounds = true
        }
        
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        panel.hidesOnDeactivate = false
        
        setupAlwaysOnTopObserver(for: panel)
        
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        
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
            // ✅ 显式使用MainActor
            Task { @MainActor in
                panel?.level = alwaysOnTop ? .floating : .normal
            }
        }
        
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
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "w"
        {
            orderOut(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        // ✅ 在主线程调用controller方法
        Task { @MainActor [weak controller] in
            controller?.handleWindowHidden()
        }
    }
    
    override func miniaturize(_ sender: Any?) {
        super.miniaturize(sender)
        Task { @MainActor [weak controller] in
            controller?.handleWindowHidden()
        }
    }
    
    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        Task { @MainActor [weak controller] in
            controller?.handleWindowVisible()
        }
    }
}
