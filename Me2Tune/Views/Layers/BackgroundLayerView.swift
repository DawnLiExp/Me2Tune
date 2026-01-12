//
//  BackgroundLayerView.swift
//  Me2Tune
//
//  背景光晕层 - 唱片和播放列表光晕效果
//

import SwiftUI

struct BackgroundLayerView: View {
    let albumGlowColor: Color
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.gradientTop, .mainBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            
            Group {
                vinylGlowLayer
                playlistGlowLayer
            }
            .drawingGroup()
        }
    }
    
    // MARK: - Vinyl Glow
    
    private var vinylGlowLayer: some View {
        VStack {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                albumGlowColor.opacity(0.58),
                                albumGlowColor.opacity(0.31),
                                albumGlowColor.opacity(0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 60,
                            endRadius: 250
                        )
                    )
                    .frame(width: 480, height: 320)
                    // 模糊效果非常耗电，确保半径适中
                    .blur(radius: 30)
            }
            .offset(y: 66)
            
            Spacer()
        }
        .allowsHitTesting(false)
    }
    
    // MARK: - Playlist Glow
    
    private var playlistGlowLayer: some View {
        VStack {
            Spacer()
            
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.accent.opacity(0.16),
                            Color.accent.opacity(0.08),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 80,
                        endRadius: 220
                    )
                )
                .frame(width: 480, height: 150)
                .blur(radius: 30)
                .padding(.bottom, 40)
        }
        .allowsHitTesting(false)
    }
}
