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
                colors: [Color(white: 0.02), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            vinylGlowLayer
            playlistGlowLayer
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
                                albumGlowColor.opacity(0.51),
                                albumGlowColor.opacity(0.35),
                                albumGlowColor.opacity(0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 60,
                            endRadius: 200
                        )
                    )
                    .frame(width: 450, height: 400)
                    .blur(radius: 40)
                
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                albumGlowColor.opacity(0.25),
                                albumGlowColor.opacity(0.1),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 460, height: 380)
                    .blur(radius: 35)
                    .offset(y: 80)
            }
            .offset(y: 0)
            
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
                            Color(hex: "#00E5FF").opacity(0.25),
                            Color(hex: "#00E5FF").opacity(0.12),
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
    }
}

#Preview {
    BackgroundLayerView(albumGlowColor: Color(hex: "#FF4466"))
}
