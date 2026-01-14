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
        return false  // 🚫 阻止此区域拖动窗口
    }
}
