//
//  MiniVolumeSlider.swift
//  Me2Tune
//
//  Mini 模式音量滑块 - 自定义视图，缩小圆点避免抢焦点
//

import SwiftUI

struct MiniVolumeSlider: View {
    @Binding var value: Double
    
    // 🎚️ 样式参数
    private let trackHeight: CGFloat = 2.2      // 轨道高度
    private let thumbDiameter: CGFloat = 10    // 圆点直径（缩小）
    
    var body: some View {
        NonDraggableView {  // 🚫 阻止拖动窗口
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 背景轨道
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: trackHeight)
                        .cornerRadius(trackHeight / 2)
                    
                    // 进度轨道
                    Rectangle()
                        .fill(Color(hex: "#00E5FF").opacity(0.7))
                        .frame(
                            width: geometry.size.width * CGFloat(value),
                            height: trackHeight
                        )
                        .cornerRadius(trackHeight / 2)
                    
                    // 圆点（拖动手柄）
                    Circle()
                        .fill(Color(hex: "#CCCCCC"))
                        .frame(width: thumbDiameter, height: thumbDiameter)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .offset(x: geometry.size.width * CGFloat(value) - thumbDiameter / 2)
                }
                .frame(maxHeight: .infinity, alignment: .center)  // 🎯 垂直居中对齐
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gestureValue in
                            let newValue = min(max(0, gestureValue.location.x / geometry.size.width), 1)
                            value = newValue
                        }
                )
            }
            .frame(height: 20)
        }
    }
}
