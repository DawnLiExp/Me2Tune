//
//  LyricsWindowDockCoordinator.swift
//  Me2Tune
//
//  歌词窗口吸附联动协调器 - 支持靠近磁吸停靠与主面板父子窗口同步移动
//

import AppKit
import OSLog

// MARK: - Notifications

extension Notification.Name {
    static let lyricsWindowDidDock = Notification.Name("lyricsWindowDidDock")
    static let lyricsWindowDidUndock = Notification.Name("lyricsWindowDidUndock")
}

// MARK: - Dock Edge

enum LyricsDockEdge: Sendable, Equatable {
    case left
    case right
}

private let logger = Logger.lyrics

@MainActor
final class LyricsWindowDockCoordinator: NSObject {
    typealias DockEdge = LyricsDockEdge
    
    weak var mainWindow: NSWindow?
    weak var lyricsWindow: NSWindow?
    
    private(set) var isDocked = false
    private(set) var dockEdge: DockEdge = .right
    
    /// 吸附阈值（像素距离小于该值时触发磁吸）
    private let snapThreshold: CGFloat = 28.0
    /// 脱离阈值（像素位移大于该值时触发解绑，需大于吸附阈值以形成防抖滞后区间）
    private let detachThreshold: CGFloat = 36.0
    
    /// 吸附时在 Y 轴上的相对偏移量（通常为 0，即顶部对齐）
    private(set) var dockedOffsetY: CGFloat = 0.0
    
    private var resizeObserver: Any?
    private var lyricsMoveObserver: Any?
    
    // MARK: - Lifecycle
    
    init(mainWindow: NSWindow? = nil, lyricsWindow: NSWindow? = nil) {
        self.mainWindow = mainWindow
        self.lyricsWindow = lyricsWindow
        super.init()
        
        setupObservers()
    }
    
    func configure(mainWindow: NSWindow?, lyricsWindow: NSWindow?) {
        cleanupObservers()
        self.mainWindow = mainWindow
        self.lyricsWindow = lyricsWindow
        setupObservers()
    }
    
    // MARK: - Frame Interception (Called from LyricsWindow.setFrameOrigin)
    
    func targetOrigin(for proposedOrigin: NSPoint, windowSize: NSSize) -> NSPoint {
        guard let main = mainWindow, main.isVisible, !main.isMiniaturized else {
            if isDocked {
                undock()
            }
            return proposedOrigin
        }
        
        let mFrame = main.frame
        let lWidth = windowSize.width
        let lHeight = windowSize.height
        
        if isDocked {
            // 已吸附状态：检测是否被拖拽脱离
            let expectedX = (dockEdge == .right) ? mFrame.maxX : (mFrame.minX - lWidth)
            let expectedY = mFrame.maxY - lHeight + dockedOffsetY
            
            // 计算向外拉开的位移
            let pullDistance: CGFloat
            if dockEdge == .right {
                pullDistance = proposedOrigin.x - expectedX
            } else {
                pullDistance = expectedX - proposedOrigin.x
            }
            let deltaY = abs(proposedOrigin.y - expectedY)
            
            if pullDistance > detachThreshold || deltaY > 48.0 {
                // 拖拽距离超过脱离阈值，解除吸附
                undock()
                return proposedOrigin
            } else {
                // 处于吸附保持防抖区间，磁吸保持锁定在吸附位置
                return NSPoint(x: expectedX, y: expectedY)
            }
        } else {
            // 未吸附状态：检测是否靠近主窗口边缘
            let verticalOverlap = (proposedOrigin.y + lHeight > mFrame.minY + 30) && (proposedOrigin.y < mFrame.maxY - 30)
            guard verticalOverlap else { return proposedOrigin }
            
            let distRight = abs(proposedOrigin.x - mFrame.maxX)
            let distLeft = abs((proposedOrigin.x + lWidth) - mFrame.minX)
            let distTop = abs((proposedOrigin.y + lHeight) - mFrame.maxY)
            let distBottom = abs(proposedOrigin.y - mFrame.minY)
            
            // 判定垂直对齐吸附目标（优先顶部对齐，其次底部对齐，否则保持当前 Y）
            let snapY: CGFloat
            if distTop <= snapThreshold {
                snapY = mFrame.maxY - lHeight
            } else if distBottom <= snapThreshold {
                snapY = mFrame.minY
            } else {
                snapY = proposedOrigin.y
            }
            
            if distRight <= snapThreshold {
                dockedOffsetY = snapY - (mFrame.maxY - lHeight)
                dock(edge: .right)
                return NSPoint(x: mFrame.maxX, y: snapY)
            } else if distLeft <= snapThreshold {
                dockedOffsetY = snapY - (mFrame.maxY - lHeight)
                dock(edge: .left)
                return NSPoint(x: mFrame.minX - lWidth, y: snapY)
            }
            
            return proposedOrigin
        }
    }
    
    // MARK: - Docking Control
    
    func dock(edge: DockEdge, notify: Bool = true) {
        guard !isDocked, let main = mainWindow, let lyrics = lyricsWindow else { return }
        dockEdge = edge
        isDocked = true
        main.addChildWindow(lyrics, ordered: .above)
        logger.info("🔗 Lyrics window docked to main window (\(edge == .right ? "right" : "left"))")
        
        if notify {
            // 触发 Force Touch 触控板吸附对齐触感反馈
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            // 发送吸附通知，携带停靠侧信息以驱动微弹动效
            NotificationCenter.default.post(
                name: .lyricsWindowDidDock,
                object: self,
                userInfo: ["edge": edge]
            )
        }
    }
    
    func undock(notify: Bool = true) {
        guard isDocked, let main = mainWindow, let lyrics = lyricsWindow else { return }
        main.removeChildWindow(lyrics)
        isDocked = false
        
        // 恢复用户在设置中设定的置顶级别
        let alwaysOnTop = SettingsManager.shared.lyricsAlwaysOnTop
        lyrics.level = alwaysOnTop ? .floating : .normal
        
        logger.info("🔓 Lyrics window undocked from main window")
        
        if notify {
            NotificationCenter.default.post(name: .lyricsWindowDidUndock, object: self)
        }
    }
    
    func cleanup() {
        if isDocked {
            undock(notify: false)
        }
        cleanupObservers()
        mainWindow = nil
        lyricsWindow = nil
    }
    
    // MARK: - Observers
    
    private func setupObservers() {
        cleanupObservers()
        guard let main = mainWindow else { return }
        
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: main,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMainWindowResized()
            }
        }
        
        if let lyrics = lyricsWindow {
            lyricsMoveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: lyrics,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleLyricsWindowMoved()
                }
            }
        }
    }
    
    private func cleanupObservers() {
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
            resizeObserver = nil
        }
        if let observer = lyricsMoveObserver {
            NotificationCenter.default.removeObserver(observer)
            lyricsMoveObserver = nil
        }
    }
    
    private func handleMainWindowResized() {
        guard isDocked, let main = mainWindow, let lyrics = lyricsWindow else { return }
        let mFrame = main.frame
        let lWidth = lyrics.frame.width
        let lHeight = lyrics.frame.height
        
        let newX = (dockEdge == .right) ? mFrame.maxX : (mFrame.minX - lWidth)
        let newY = mFrame.maxY - lHeight + dockedOffsetY
        lyrics.setFrameOrigin(NSPoint(x: newX, y: newY))
    }
    
    private func handleLyricsWindowMoved() {
        guard !isDocked, let lyrics = lyricsWindow else { return }
        let currentOrigin = lyrics.frame.origin
        let newOrigin = targetOrigin(for: currentOrigin, windowSize: lyrics.frame.size)
        if newOrigin != currentOrigin {
            lyrics.setFrameOrigin(newOrigin)
        }
    }
}

// MARK: - Snappable Lyrics Window Subclass

final class LyricsWindow: NSWindow {
    weak var dockCoordinator: LyricsWindowDockCoordinator?
    
    private var isDraggingWindow = false
    private var hasMovedDuringDrag = false
    private var dragStartMouseLocation: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero
    
    func setInitialFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
    }
    
    override func setFrameOrigin(_ newOrigin: NSPoint) {
        let finalOrigin = dockCoordinator?.targetOrigin(for: newOrigin, windowSize: frame.size) ?? newOrigin
        super.setFrameOrigin(finalOrigin)
    }
    
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if isClickInInteractiveArea(event) {
                super.sendEvent(event)
                return
            }
            dragStartMouseLocation = NSEvent.mouseLocation
            dragStartWindowOrigin = frame.origin
            isDraggingWindow = true
            hasMovedDuringDrag = false
            super.sendEvent(event)
            return
            
        case .leftMouseDragged:
            if isDraggingWindow {
                let currentMouse = NSEvent.mouseLocation
                let deltaX = currentMouse.x - dragStartMouseLocation.x
                let deltaY = currentMouse.y - dragStartMouseLocation.y
                
                if !hasMovedDuringDrag && hypot(deltaX, deltaY) < 2.0 {
                    super.sendEvent(event)
                    return
                }
                hasMovedDuringDrag = true
                
                let proposedOrigin = NSPoint(
                    x: dragStartWindowOrigin.x + deltaX,
                    y: dragStartWindowOrigin.y + deltaY
                )
                setFrameOrigin(proposedOrigin)
                return
            }
            super.sendEvent(event)
            
        case .leftMouseUp:
            if isDraggingWindow {
                isDraggingWindow = false
                hasMovedDuringDrag = false
                if let coordinator = dockCoordinator, coordinator.isDocked, let main = coordinator.mainWindow {
                    let mFrame = main.frame
                    let lWidth = frame.width
                    let lHeight = frame.height
                    let settledX = (coordinator.dockEdge == .right) ? mFrame.maxX : (mFrame.minX - lWidth)
                    let settledY = mFrame.maxY - lHeight + coordinator.dockedOffsetY
                    super.setFrameOrigin(NSPoint(x: settledX, y: settledY))
                }
            }
            super.sendEvent(event)
            
        default:
            super.sendEvent(event)
        }
    }
    
    private func isClickInInteractiveArea(_ event: NSEvent) -> Bool {
        let location = event.locationInWindow
        
        // 1. 窗口标准按钮（关闭/最小化/缩放等）
        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = standardWindowButton(buttonType), !button.isHidden {
                let hitRect = button.frame.insetBy(dx: -8, dy: -8)
                if hitRect.contains(location) {
                    return true
                }
            }
        }
        
        // 2. 检查点击视图是否属于非拖拽区域或交互控件
        guard let contentView else { return false }
        return isPointInInteractiveView(view: contentView, windowPoint: location)
    }
    
    private func isPointInInteractiveView(view: NSView, windowPoint: NSPoint) -> Bool {
        let localPoint = view.convert(windowPoint, from: nil)
        guard view.bounds.contains(localPoint) else { return false }
        
        if !view.mouseDownCanMoveWindow || view is NSControl {
            return true
        }
        
        for subview in view.subviews {
            if isPointInInteractiveView(view: subview, windowPoint: windowPoint) {
                return true
            }
        }
        return false
    }
}
