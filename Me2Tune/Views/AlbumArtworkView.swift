//
//  AlbumArtworkView.swift
//  Me2Tune
//
//  专辑封面视图：拟真唱片旋转动画
//

import SwiftUI

struct AlbumArtworkView: View {
    let artwork: NSImage?
    let isPlaying: Bool
    
    @State private var rotation: Double = 0
    
    private let artworkSize: CGFloat = 220
    
    var body: some View {
        GeometryReader { _ in
            ZStack {
                // 暗色渐变背景
                LinearGradient(
                    colors: [
                        Color(white: 0.12),
                        Color(white: 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                    
                // 唱片容器
                VStack {
                    Spacer()
                        
                    ZStack {
                        // 背景圆盘
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.9),
                                        Color.gray.opacity(0.7)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: artworkSize, height: artworkSize)
                            
                        // 封面图片
                        Group {
                            if let artwork {
                                Image(nsImage: artwork)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "music.note")
                                    .font(.system(size: 60))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: artworkSize * 0.6, height: artworkSize * 0.6)
                        .clipShape(Circle())
                            
                        // 中心圆点
                        Circle()
                            .fill(Color.black)
                            .frame(width: 24, height: 24)
                            
                        Circle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(width: 16, height: 16)
                    }
                    .rotationEffect(.degrees(rotation))
                        
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: isPlaying) { _, newValue in
            if newValue {
                startRotation()
            } else {
                stopRotation()
            }
        }
        .onAppear {
            if isPlaying {
                startRotation()
            }
        }
    }
        
    private func startRotation() {
        withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
        
    private func stopRotation() {
        withAnimation(.linear(duration: 0.5)) {
            rotation = 0
        }
    }
}
