//
//  HoverDetectingView.swift
//  Me2Tune
//
//  NSView 级别的 hover 检测
//

import AppKit
import SwiftUI

struct HoverDetectingView: NSViewRepresentable {
    @Binding var isHovered: Bool
    
    func makeNSView(context: Context) -> HoverTrackingView {
        let view = HoverTrackingView()
        view.onHoverChange = { hovering in
            // 直接在主线程更新，无需 DispatchQueue
            self.isHovered = hovering
        }
        return view
    }
    
    func updateNSView(_ nsView: HoverTrackingView, context: Context) {
        // 空实现，避免不必要的更新
    }
}

// MARK: - HoverTrackingView

final class HoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    private var isCurrentlyHovered = false
    
    // MARK: - Tracking Area Management
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        // 移除旧的 tracking areas
        trackingAreas.forEach { removeTrackingArea($0) }
        
        // 添加新的 tracking area（使用更精简的选项）
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeInKeyWindow,
            .inVisibleRect // 自动调整到可见区域
        ]
        
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        
        addTrackingArea(trackingArea)
        
        // ✅ 修复滚动 bug：更新 tracking area 后立即验证鼠标位置
        checkMouseLocation()
    }
    
    // MARK: - Mouse Events
    
    override func mouseEntered(with event: NSEvent) {
        setHoverState(true)
    }
    
    override func mouseExited(with event: NSEvent) {
        setHoverState(false)
    }
    
    // MARK: - Window Lifecycle
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if window != nil {
            checkMouseLocation()
        } else {
            setHoverState(false)
        }
    }
    
    // MARK: - Helper Methods
    
    /// 设置 hover 状态（避免重复回调）
    private func setHoverState(_ shouldBeHovered: Bool) {
        guard shouldBeHovered != isCurrentlyHovered else { return }
        isCurrentlyHovered = shouldBeHovered
        onHoverChange?(shouldBeHovered)
    }
    
    /// 验证鼠标实际位置，修正滚动导致的状态错误
    private func checkMouseLocation() {
        guard let window else {
            setHoverState(false)
            return
        }
        
        let mouseLocation = window.mouseLocationOutsideOfEventStream
        let locationInView = convert(mouseLocation, from: nil)
        let shouldBeHovered = bounds.contains(locationInView)
        
        setHoverState(shouldBeHovered)
    }
}
