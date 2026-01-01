//
//  ToolbarButtonView.swift
//  Me2Tune
//
//  工具栏图标按钮组件
//

import SwiftUI

struct ToolbarButtonView: View {
    let icon: String
    let tooltip: String
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isEnabled ? (isHovered ? .primary : .secondary) : .tertiary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(tooltip)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        ToolbarButtonView(icon: "plus.circle", tooltip: "Add", action: {})
        ToolbarButtonView(icon: "xmark.circle", tooltip: "Remove", isEnabled: false, action: {})
    }
    .padding()
    .background(Color.black)
}
