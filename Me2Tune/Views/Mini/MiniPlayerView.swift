//
//  MiniPlayerView.swift
//  Me2Tune
//
//  Mini 播放器视图 - 封面填充优化版 + 精细化布局
//

import SwiftUI

struct MiniPlayerView: View {
    @Environment(PlayerViewModel.self) private var playerViewModel
    @Environment(\.playbackProgressState) private var playbackProgressState
    @AppStorage("displayMode") private var displayMode = DisplayMode.full.rawValue
    
    private let miniTheme = MiniPlayerTheme()
    
    var body: some View {
        ZStack {
            miniTheme.colors.containerBackground
                .ignoresSafeArea()
            
            contentView
        }
        .frame(width: 440, height: 78)
        .contextMenu {
            @Bindable var settings = SettingsManager.shared
            Toggle(isOn: $settings.miniAlwaysOnTop) {
                Label(String(localized: "always_on_top"), systemImage: "pin.fill")
            }
        }
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        HStack(spacing: 0) {
            artworkView
                .frame(width: 78, height: 78)
            
            VStack(alignment: .leading, spacing: 10) {
                trackInfoRow
                controlsRow // ✅ 直接调用，内部创建 Bindable
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
    
    // MARK: - Artwork (完全填充)
    
    private var artworkView: some View {
        Group {
            if let artwork = playerViewModel.currentArtwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 24))
                            .foregroundColor(.gray.opacity(0.5))
                    )
            }
        }
        .clipped()
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 3,
                topTrailingRadius: 3
            )
        )
    }
    
    // MARK: - Track Info Row
    
    private var trackInfoRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(playerViewModel.currentTrack?.title ?? String(localized: "no_track"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(miniTheme.colors.primaryText)
                    .lineLimit(1)
                
                if let track = playerViewModel.currentTrack {
                    Text("•")
                        .font(.system(size: 12))
                        .foregroundColor(miniTheme.colors.secondaryText.opacity(0.5))
                    
                    Text(track.artist ?? String(localized: "unknown_artist"))
                        .font(.system(size: 12))
                        .foregroundColor(miniTheme.colors.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 8)
            
            if playerViewModel.currentTrack != nil {
                Text(remainingTimeString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(miniTheme.colors.timeDisplayColor)
            }
        }
    }
    
    private var remainingTimeString: String {
        let remaining = max(0, playerViewModel.duration - playbackProgressState.currentTime)
        guard remaining.isFinite, !remaining.isNaN else { return "-0:00" }
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "-%d:%02d", minutes, seconds)
    }
    
    // MARK: - Controls Row
    
    private var controlsRow: some View {
        @Bindable var viewModel = playerViewModel // ✅ 在这里创建 Bindable
        
        return HStack(spacing: 0) {
            HStack(spacing: 14) {
                repeatButton
                
                HStack(spacing: 8) {
                    controlButton(
                        icon: "backward.end",
                        size: 24,
                        enabled: playerViewModel.canGoPrevious,
                        action: playerViewModel.previous
                    )
                    
                    playPauseButton
                    
                    controlButton(
                        icon: "forward.end",
                        size: 24,
                        enabled: playerViewModel.canGoNext,
                        action: playerViewModel.next
                    )
                }
            }
            
            Spacer(minLength: 24)
            
            HStack(spacing: 16) {
                volumeControl(volume: $viewModel.volume) // ✅ 传递 Binding
                switchToFullButton
            }
        }
    }
    
    // MARK: - Repeat Button
    
    private var repeatButton: some View {
        Button(action: { playerViewModel.toggleRepeatMode() }) {
            Image(systemName: repeatIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(repeatColor)
                .frame(width: 24, height: 24)
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
    
    // MARK: - Play/Pause Button
    
    private var playPauseButton: some View {
        Button(action: playerViewModel.togglePlayPause) {
            ZStack {
                Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(miniTheme.colors.primaryText)
            }
        }
        .buttonStyle(.plain)
        .disabled(playerViewModel.currentTrack == nil)
        .opacity(playerViewModel.currentTrack == nil ? 0.5 : 1.0)
    }
    
    // MARK: - Volume Control
    
    private func volumeControl(volume: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Button(action: toggleMute) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(miniTheme.colors.controlButtonColor)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            
            MiniVolumeSlider(value: volume) // ✅ 直接使用 Binding
                .frame(width: 75, height: 20)
        }
        .frame(height: 24, alignment: .center)
    }
    
    @State private var volumeBeforeMute: Double = 0.7
    
    private var volumeIcon: String {
        switch playerViewModel.volume {
        case 0:
            return "speaker.slash.fill"
        case 0.01..<0.33:
            return "speaker.wave.1.fill"
        case 0.33..<0.66:
            return "speaker.wave.2.fill"
        default:
            return "speaker.wave.3.fill"
        }
    }
    
    private func toggleMute() {
        if playerViewModel.volume > 0 {
            volumeBeforeMute = playerViewModel.volume
            playerViewModel.volume = 0
        } else {
            playerViewModel.volume = max(volumeBeforeMute, 0.1)
        }
    }
    
    // MARK: - Switch Button
    
    private var switchToFullButton: some View {
        Button(action: switchToFullMode) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(miniTheme.colors.controlButtonColor.opacity(0.7))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }
    
    private func controlButton(icon: String, size: CGFloat, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size - 8, weight: .medium))
                .foregroundColor(enabled ? miniTheme.colors.controlButtonColor : miniTheme.colors.controlButtonColor.opacity(0.3))
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
    
    // MARK: - Helpers
    
    private func switchToFullMode() {
        displayMode = DisplayMode.full.rawValue
    }
}

#Preview {
    let collectionManager = CollectionManager()
    let coordinator = PlaybackCoordinator(collectionManager: collectionManager)
    let playerViewModel = PlayerViewModel(coordinator: coordinator)

    MiniPlayerView()
        .environment(playerViewModel)
}
