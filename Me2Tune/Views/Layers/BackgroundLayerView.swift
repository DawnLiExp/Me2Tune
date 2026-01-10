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
            .ignoresSafeArea()
            
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
                                albumGlowColor.opacity(0.56),
                                albumGlowColor.opacity(0.31),
                                albumGlowColor.opacity(0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 60,
                            endRadius: 380
                        )
                    )
                    .frame(width: 450, height: 330)
                    // 模糊效果非常耗电，确保半径适中
                    .blur(radius: 40)
            }
            .offset(y: 30)
            
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
                            Color.accent.opacity(0.21),
                            Color.accent.opacity(0.11),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 80,
                        endRadius: 320
                    )
                )
                .frame(width: 460, height: 180)
                .blur(radius: 35)
                .padding(.bottom, 40)
        }
        .allowsHitTesting(false)
    }
}
