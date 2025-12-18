//
//  AlbumArtworkView.swift
//  Me2Tune
//
//  专辑封面视图：可收拢的拟真唱片旋转动画
//

import SwiftUI

struct AlbumArtworkView: View {
    let artwork: NSImage?
    let isPlaying: Bool
    let currentTrack: AudioTrack?
    @Binding var isExpanded: Bool
    
    @State private var rotation: Double = 0
    @State private var isHoveringToggle = false
    @State private var rotationTimer: Timer?
    
    private let artworkSize: CGFloat = 220
    private let miniArtworkSize: CGFloat = 48
    
    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedView
            } else {
                miniView
            }
        }
        .frame(width: 350)
        .background(Color(white: 0.1))
        .onChange(of: isPlaying) { _, newValue in
            updateRotation(isPlaying: newValue)
        }
        .onChange(of: isExpanded) { _, _ in
            updateRotation(isPlaying: isPlaying)
        }
        .onAppear {
            updateRotation(isPlaying: isPlaying)
        }
    }
    
    // MARK: - Expanded View
    
    private var expandedView: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [Color(white: 0.12), Color(white: 0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                ZStack {
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
                    
                    Circle()
                        .fill(Color.black)
                        .frame(width: 24, height: 24)
                    
                    Circle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 16, height: 16)
                }
                .rotationEffect(.degrees(rotation))
            }
            .frame(height: 350)
            
            // Toggle Button
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHoveringToggle ? .primary : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(isHoveringToggle ? 0.1 : 0.05))
                    )
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .onHover { hovering in
                isHoveringToggle = hovering
            }
        }
    }
    
    // MARK: - Mini View
    
    private var miniView: some View {
        HStack(spacing: 12) {
            // Mini Artwork (静止不旋转)
            ZStack {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black.opacity(0.3)
                    Image(systemName: "music.note")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: miniArtworkSize, height: miniArtworkSize)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            
            // Track Info
            if let track = currentTrack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    
                    Text(track.artist ?? String(localized: "unknown_artist"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("No Track")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            // Toggle Button
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHoveringToggle ? .primary : .secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(isHoveringToggle ? 0.1 : 0.05))
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHoveringToggle = hovering
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 64)
    }
    
    // MARK: - Animation Logic
    
    private func updateRotation(isPlaying: Bool) {
        if isExpanded {
            if isPlaying {
                startRotation()
            } else {
                stopRotation()
            }
        } else {
            stopRotationImmediately()
        }
    }
    
    private func startRotation() {
        // 使用Timer手动控制旋转，每0.016秒(约60fps)更新一次
        stopRotation() // 先停止已有的timer
        
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            // 每10秒转360度，即每秒36度，每帧0.6度
            rotation += 0.6
            // 避免数值过大，超过360时取模
            if rotation >= 360 {
                rotation = rotation.truncatingRemainder(dividingBy: 360)
            }
        }
    }
    
    private func stopRotation() {
        // 停止Timer，rotation保持当前值
        rotationTimer?.invalidate()
        rotationTimer = nil
    }
    
    private func stopRotationImmediately() {
        stopRotation()
        rotation = 0
    }
}
