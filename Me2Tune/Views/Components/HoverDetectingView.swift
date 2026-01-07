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
        view.onHoverChange = { [weak view] hovering in
            guard view != nil else { return }
            DispatchQueue.main.async {
                self.isHovered = hovering
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: HoverTrackingView, context: Context) {}
}

// MARK: - HoverTrackingView

final class HoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    private var isCurrentlyHovered = false
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        // 移除旧的 tracking areas
        trackingAreas.forEach { removeTrackingArea($0) }
        
        // 添加新的 tracking area
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeInKeyWindow,
            .inVisibleRect
        ]
        
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        
        addTrackingArea(trackingArea)
        
        // ✅ 滚动后验证鼠标是否真的在视图内
        checkMouseLocation()
    }
    
    override func mouseEntered(with event: NSEvent) {
        isCurrentlyHovered = true
        onHoverChange?(true)
    }
    
    override func mouseExited(with event: NSEvent) {
        isCurrentlyHovered = false
        onHoverChange?(false)
    }
    
    // ✅ 验证鼠标实际位置，修正滚动导致的状态错误
    private func checkMouseLocation() {
        guard let window else { return }
        
        let mouseLocation = window.mouseLocationOutsideOfEventStream
        let locationInView = convert(mouseLocation, from: nil)
        let shouldBeHovered = bounds.contains(locationInView)
        
        // 如果状态不匹配，立即修正
        if shouldBeHovered != isCurrentlyHovered {
            isCurrentlyHovered = shouldBeHovered
            onHoverChange?(shouldBeHovered)
        }
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if window != nil {
            checkMouseLocation()
        } else {
            isCurrentlyHovered = false
            onHoverChange?(false)
        }
    }
}
