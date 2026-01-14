//
//  NonDraggableView.swift
//  Me2Tune
//
//  阻止窗口拖动的视图包装器 - 用于 Mini 模式交互控件
//

import AppKit
import SwiftUI

/// 包装内容视图，阻止该区域触发窗口拖动
struct NonDraggableView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(NonDraggableHostingView())
    }
}

// MARK: - NSView Implementation

private struct NonDraggableHostingView: NSViewRepresentable {
    func makeNSView(context: Context) -> NonDraggableNSView {
        return NonDraggableNSView()
    }

    func updateNSView(_ nsView: NonDraggableNSView, context: Context) {}
}

private final class NonDraggableNSView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        return false // 🚫 阻止此区域拖动窗口
    }

    // ✅ 关键优化：完全拦截鼠标事件，防止传递给窗口拖动系统
    override func mouseDown(with event: NSEvent) {
        // 不调用 super.mouseDown，事件会被传递给 SwiftUI gesture
        // 这确保事件优先被 SwiftUI 处理，而不是被窗口拖动捕获
    }

    override func mouseDragged(with event: NSEvent) {
        // 同样拦截拖动事件，避免窗口拖动的边缘情况
    }

    // ✅ 额外优化：确保这个区域总是接收事件
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        // 如果没有子视图响应，返回自己以确保事件不穿透
        return result ?? (bounds.contains(point) ? self : nil)
    }
}
