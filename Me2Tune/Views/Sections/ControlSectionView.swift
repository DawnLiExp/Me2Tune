//
//  ControlSectionView.swift
//  Me2Tune
//
//  播放控制区域 - 进度条+控制按钮+歌曲信息+循环模式
//

import SwiftUI

struct ControlSectionView: View {
    let currentTrack: AudioTrack?
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let canGoPrevious: Bool
    let canGoNext: Bool
    let repeatMode: PlayerViewModel.RepeatMode
    
    let onPlayPause: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onToggleRepeat: () -> Void
    
    @State private var isSeekingManually = false
    @State private var manualSeekValue: TimeInterval = 0
    @State private var isHoveringTrackInfo = false
    
    var body: some View {
        VStack(spacing: 0) {
            progressBar
                .frame(height: 3)
                .padding(.horizontal, 28)
            
            HStack(spacing: 10) {
                trackInfoSection
                
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
    
    // MARK: - Track Info Section
    
    private var trackInfoSection: some View {
        HStack(spacing: 0) {
            if isHoveringTrackInfo, currentTrack != nil {
                repeatButton
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
            
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isHoveringTrackInfo = hovering
            }
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
    
    // MARK: - Repeat Button
    
    private var repeatButton: some View {
        Button(action: {
            onToggleRepeat()
        }) {
            Image(systemName: repeatIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(repeatMode == .off ? .secondaryText : .accent)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(repeatTooltip)
        .rotationEffect(.degrees(rotationAngle))
        .scaleEffect(scaleEffect)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: repeatMode)
    }
    
    private var repeatIcon: String {
        switch repeatMode {
        case .off, .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }
    
    private var repeatTooltip: String {
        switch repeatMode {
        case .off:
            return "Repeat: Off"
        case .all:
            return "Repeat: All"
        case .one:
            return "Repeat: One"
        }
    }
    
    private var rotationAngle: Double {
        repeatMode == .off ? 0 : 180
    }
    
    private var scaleEffect: Double {
        repeatMode == .off ? 1.0 : 1.0
    }
    
    // MARK: - Control Buttons
    
    private var controlButtons: some View {
        HStack(spacing: 20) {
            controlButton(
                icon: "backward.end",
                size: 20,
                enabled: canGoPrevious,
                action: onPrevious
            )
            
            controlButton(
                icon: "forward.end",
                size: 20,
                enabled: canGoNext,
                action: onNext
            )
            
            playPauseButton
        }
    }
    
    private var playPauseButton: some View {
        Button(action: onPlayPause) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.playButtonBackground)
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
    ControlSectionView(
        currentTrack: nil,
        currentTime: 130,
        duration: 240,
        isPlaying: true,
        canGoPrevious: true,
        canGoNext: true,
        repeatMode: .off,
        onPlayPause: {},
        onPrevious: {},
        onNext: {},
        onSeek: { _ in },
        onToggleRepeat: {}
    )
    .padding()
    .background(Color.black)
}
