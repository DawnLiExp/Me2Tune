//
//  StatCard.swift
//  Me2Tune
//
//  统计卡片组件 - 用于在设置页展示概览数据
//

import SwiftUI

struct StatCard: View {
    let title: String
    let value: Int
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.accentColor.opacity(0.7))
            
            Text(value.formatted())
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.primary)
                .contentTransition(.numericText())
            
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

#Preview {
    StatCard(title: "Songs", value: 1234, icon: "music.note")
        .padding()
        .frame(width: 150)
}
