//
//  CollapseButtonView.swift
//  Me2Tune
//
//  播放列表折叠按钮组件
//

import SwiftUI

struct CollapseButtonView: View {
    @Binding var isCollapsed: Bool

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4)) {
                isCollapsed.toggle()
            }
        }) {
            ZStack {
                Capsule()
                    .fill(Color.accent.opacity(0.2))
                    .frame(width: 64, height: 6)
                    .shadow(color: Color.accent.opacity(0.4), radius: 6)

                Image(systemName: isCollapsed ? "chevron.compact.up" : "chevron.compact.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.accent)
                    .offset(y: isCollapsed ? -12 : 12)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 20) {
        CollapseButtonView(isCollapsed: .constant(false))
        CollapseButtonView(isCollapsed: .constant(true))
    }
    .padding()
    .background(Color.black)
}
