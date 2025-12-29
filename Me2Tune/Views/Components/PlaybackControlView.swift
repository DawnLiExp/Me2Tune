//
//  PlaybackControlView.swift
//  Me2Tune
//
//  播放控制面板：进度条+控制按钮+歌曲信息
//

import SwiftUI

struct PlaybackControlView: View {
    let currentTrack: AudioTrack?
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let canGoPrevious: Bool
    let canGoNext: Bool
    
    let onPlayPause: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSeek: (TimeInterval) -> Void
    
    @State private var isSeekingManually = false
    @State private var manualSeekValue: TimeInterval = 0
    
    var body: some View {
        VStack(spacing: 0) {
            progressBar
                .frame(height: 3)
                .padding(.horizontal, 28)
            
            HStack(spacing: 20) {
                trackInfo
                
                Spacer()
                
                controlButtons
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.controlBackground)
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            )
            .padding(.horizontal, 12)
        }
    }
    
    // MARK: - Track Info
    
    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(currentTrack?.title ?? "No Track")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.accent)
                .lineLimit(1)
            
            Text(trackSubtitle)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(.tertiaryText)
                .lineLimit(1)
        }
    }
    
    private var trackSubtitle: String {
        guard let track = currentTrack else {
            return "Ready to play"
        }
        
        let artist = track.artist ?? "Unknown Artist"
        let album = track.albumTitle ?? ""
        
        if album.isEmpty {
            return artist
        } else {
            return "\(artist) • \(album)"
        }
    }
    
    // MARK: - Control Buttons
    
    private var controlButtons: some View {
        HStack(spacing: 26) {
            controlButton(
                icon: "backward.fill",
                size: 18,
                enabled: canGoPrevious,
                action: onPrevious
            )
            
            playPauseButton
            
            controlButton(
                icon: "forward.fill",
                size: 18,
                enabled: canGoNext,
                action: onNext
            )
        }
    }
    
    private var playPauseButton: some View {
        Button(action: onPlayPause) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.3), radius: 6)
                
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(currentTrack == nil)
        .opacity(currentTrack == nil ? 0.5 : 1.0)
    }
    
    private func controlButton(icon: String, size: CGFloat, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(enabled ? .white.opacity(0.7) : .white.opacity(0.3))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!enabled)
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: width, height: height)
                
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.accent, .accent.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * progress, height: height)
                    .shadow(color: .accentGlow, radius: 4)
            }
            .overlay(
                // 透明扩展交互层
                Color.clear
                    .frame(height: 20)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isSeekingManually {
                                    isSeekingManually = true
                                }
                                let newProgress = min(max(0, value.location.x / width), 1)
                                manualSeekValue = newProgress * max(duration, 0.1)
                            }
                            .onEnded { value in
                                let newProgress = min(max(0, value.location.x / width), 1)
                                let seekTime = newProgress * max(duration, 0.1)
                                onSeek(seekTime)
                                isSeekingManually = false
                            }
                    )
            )
        }
    }
    
    private var progress: CGFloat {
        let time = isSeekingManually ? manualSeekValue : currentTime
        let total = max(duration, 0.1)
        return CGFloat(min(max(time / total, 0), 1))
    }
}

#Preview {
    PlaybackControlView(
        currentTrack: nil,
        currentTime: 130,
        duration: 240,
        isPlaying: true,
        canGoPrevious: true,
        canGoNext: true,
        onPlayPause: {},
        onPrevious: {},
        onNext: {},
        onSeek: { _ in }
    )
    .padding()
    .background(Color.black)
}
