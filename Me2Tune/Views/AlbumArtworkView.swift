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
        .onChange(of: isExpanded) { _, newValue in
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
            // 展开模式：播放时旋转
            if isPlaying {
                startRotation()
            } else {
                stopRotation()
            }
        } else {
            // mini模式：静止不旋转
            stopRotationImmediately()
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
    
    private func stopRotationImmediately() {
        withAnimation(nil) {
            rotation = 0
        }
    }
}
