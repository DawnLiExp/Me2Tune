//
//  EmptyStateView.swift
//  Me2Tune
//
//  统计功能空状态组件 - 无播放记录时显示
//

import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text(String(localized: "stat_empty_title", defaultValue: "No Records"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)

            Text(String(localized: "stat_empty_subtitle", defaultValue: "Start listening to fill your music footprint"))
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView()
        .frame(height: 240)
}
