//
//  MiniPlayerView.swift
//  Me2Tune
//
//  Mini 播放器视图 - 紧凑横条布局
//

import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var playerViewModel: PlayerViewModel
    @AppStorage("displayMode") private var displayMode = DisplayMode.full.rawValue
    
    private let miniTheme = MiniPlayerTheme()
    
    var body: some View {
        ZStack {
            miniTheme.colors.containerBackground
                .ignoresSafeArea()
            
            contentView
        }
        .frame(width: 390, height: 60)
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        HStack(spacing: 10) {
            // 封面
            artworkView

            trackInfoView
                .frame(width: 180)
    
            controlsView
     
            rightButtonsView
        }
        .padding(.horizontal, 12)
        .frame(height: 60)
    }
    
    // MARK: - Artwork
    
    private var artworkView: some View {
        Group {
            if let artwork = playerViewModel.currentArtwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 18))
                            .foregroundColor(.gray.opacity(0.5))
                    )
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
    
    // MARK: - Track Info
    
    private var trackInfoView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(playerViewModel.currentTrack?.title ?? "No Track")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(miniTheme.colors.primaryText)
                .lineLimit(1)
            
            Text(trackSubtitle)
                .font(.system(size: 11))
                .foregroundColor(miniTheme.colors.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var trackSubtitle: String {
        guard let track = playerViewModel.currentTrack else {
            return "Ready to play"
        }
        
        return track.artist ?? "Unknown Artist"
    }
    
    // MARK: - Controls
    
    private var controlsView: some View {
        HStack(spacing: 14) {
            controlButton(
                icon: "backward.end",
                size: 16,
                enabled: playerViewModel.canGoPrevious,
                action: playerViewModel.previous
            )
            
            playPauseButton
       
            controlButton(
                icon: "forward.end",
                size: 16,
                enabled: playerViewModel.canGoNext,
                action: playerViewModel.next
            )
        }
    }
    
    private var playPauseButton: some View {
        Button(action: playerViewModel.togglePlayPause) {
            Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(miniTheme.colors.primaryText)
        }
        .buttonStyle(.plain)
        .disabled(playerViewModel.currentTrack == nil)
        .opacity(playerViewModel.currentTrack == nil ? 0.5 : 1.0)
    }
    
    private var rightButtonsView: some View {
        HStack(spacing: 10) {
            repeatButton
          
            Button(action: switchToFullMode) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11))
                    .foregroundColor(miniTheme.colors.controlButtonColor)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var repeatButton: some View {
        Button(action: { playerViewModel.toggleRepeatMode() }) {
            Image(systemName: repeatIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(repeatColor)
        }
        .buttonStyle(.plain)
    }
    
    private var repeatIcon: String {
        switch playerViewModel.repeatMode {
        case .off, .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }
    
    private var repeatColor: Color {
        playerViewModel.repeatMode == .off
            ? miniTheme.colors.controlButtonColor.opacity(0.5)
            : miniTheme.colors.accent
    }
    
    private func controlButton(icon: String, size: CGFloat, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(enabled ? miniTheme.colors.controlButtonColor : miniTheme.colors.controlButtonColor.opacity(0.3))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
    
    // MARK: - Helpers
    
    private func switchToFullMode() {
        displayMode = DisplayMode.full.rawValue
    }
}

// MARK: - Display Mode Enum

enum DisplayMode: String, Codable {
    case full
    case mini
}

#Preview {
    MiniPlayerView()
        .environmentObject(PlayerViewModel())
}
