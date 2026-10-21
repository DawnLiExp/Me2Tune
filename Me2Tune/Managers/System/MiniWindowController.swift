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
    private weak var dockingCoordinator: WindowDockingCoordinator?
    
    init(playerViewModel: PlayerViewModel, windowStateMonitor: WindowStateMonitor?, dockingCoordinator: WindowDockingCoordinator) {
        self.playerViewModel = playerViewModel
        self.windowStateMonitor = windowStateMonitor
        self.dockingCoordinator = dockingCoordinator
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
        dockingCoordinator?.presentationChanged()
    }
    
    func handleWindowVisible() {
        windowStateMonitor?.updateMiniWindowState(false)
        dockingCoordinator?.presentationChanged()
    }
    
    // MARK: - Private Methods
    
    private func createPanel() {
        let monitor = windowStateMonitor ?? WindowStateMonitor()
        let contentView = MiniPlayerView()
            .environment(playerViewModel) // ✅ 使用 .environment()
            .environment(monitor)
            .environment(\.playbackProgressState, playerViewModel.playbackProgressState)
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 440, height: 78)
        
        let panel = MiniPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 78),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        panel.controller = self
        panel.identifier = NSUserInterfaceItemIdentifier("mini")
        
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
        
        panel.center()
        self.panel = panel
        dockingCoordinator?.bindPlayer(panel, mode: .mini)
        panel.makeKeyAndOrderFront(nil)
        
        windowStateMonitor?.forceSetState(.miniVisible)
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
        controller?.handleWindowHidden()
    }
    
    override func miniaturize(_ sender: Any?) {
        super.miniaturize(sender)
        controller?.handleWindowHidden()
    }
    
    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        controller?.handleWindowVisible()
    }
}
