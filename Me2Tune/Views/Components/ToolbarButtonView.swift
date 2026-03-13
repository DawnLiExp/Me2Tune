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
                .foregroundStyle(
                    isEnabled
                        ? (isHovered ? Color.accent : Color.secondaryText)
                        : Color.tertiaryText
                )
                .frame(width: 24, height: 24)
                .scaleEffect(isHovered && isEnabled ? 1.12 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.65), value: isHovered)
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
