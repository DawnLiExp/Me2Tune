//
//  MiniPlayerView.swift
//  Me2Tune
//
//  Mini 播放器视图 - 增强版布局
//

import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var playerViewModel: PlayerViewModel
    @AppStorage("displayMode") private var displayMode = DisplayMode.full.rawValue
    @AppStorage("miniAlwaysOnTop") private var alwaysOnTop = false
    
    private let miniTheme = MiniPlayerTheme()
    
    var body: some View {
        ZStack {
            miniTheme.colors.containerBackground
                .ignoresSafeArea()
            
            contentView
        }
        .frame(width: 420, height: 78)
        .contextMenu {
            Toggle(isOn: $alwaysOnTop) {
                Label("Always on Top", systemImage: "pin.fill")
            }
        }
        .onChange(of: alwaysOnTop) { _, newValue in
            updateWindowLevel(alwaysOnTop: newValue)
        }
        .onAppear {
            updateWindowLevel(alwaysOnTop: alwaysOnTop)
        }
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        HStack(spacing: 12) {
            artworkView
            
            VStack(alignment: .leading, spacing: 8) {
                trackInfoRow
                controlsRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    // MARK: - Artwork
    
    private var artworkView: some View {
        Group {
            if let artwork = playerViewModel.currentArtwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 20))
                            .foregroundColor(.gray.opacity(0.5))
                    )
            }
        }
        .frame(width: 50, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    // MARK: - Track Info Row
    
    private var trackInfoRow: some View {
        HStack(spacing: 6) {
            // 歌曲信息
            HStack(spacing: 6) {
                Text(playerViewModel.currentTrack?.title ?? "No Track")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(miniTheme.colors.primaryText)
                    .lineLimit(1)
                
                if let track = playerViewModel.currentTrack {
                    Text("•")
                        .font(.system(size: 12))
                        .foregroundColor(miniTheme.colors.secondaryText.opacity(0.5))
                    
                    Text(track.artist ?? "Unknown Artist")
                        .font(.system(size: 12))
                        .foregroundColor(miniTheme.colors.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 8)
            
            // 剩余时间
            if playerViewModel.currentTrack != nil {
                Text(remainingTimeString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(miniTheme.colors.timeDisplayColor)
            }
        }
    }
    
    private var remainingTimeString: String {
        let remaining = max(0, playerViewModel.duration - playerViewModel.currentTime)
        guard remaining.isFinite, !remaining.isNaN else { return "-0:00" }
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "-%d:%02d", minutes, seconds)
    }
    
    // MARK: - Controls Row
    
    private var controlsRow: some View {
        HStack(spacing: 0) {
            repeatButton
                .padding(.trailing, 14)
            
            // 播放控制组（紧密排列）
            HStack(spacing: 10) {
                controlButton(
                    icon: "backward.end",
                    size: 15,
                    enabled: playerViewModel.canGoPrevious,
                    action: playerViewModel.previous
                )
                
                playPauseButton
                
                controlButton(
                    icon: "forward.end",
                    size: 15,
                    enabled: playerViewModel.canGoNext,
                    action: playerViewModel.next
                )
            }
            .padding(.trailing, 14)
            
            // 音量控制
            volumeControl
                .padding(.trailing, 14)
            
            Spacer(minLength: 0)
            
            // 切换按钮
            switchToFullButton
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
            Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(miniTheme.colors.primaryText)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(playerViewModel.currentTrack == nil)
        .opacity(playerViewModel.currentTrack == nil ? 0.5 : 1.0)
    }
    
    // MARK: - Volume Control
    
    private var volumeControl: some View {
        HStack(spacing: 6) {
            Button(action: toggleMute) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(miniTheme.colors.controlButtonColor)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            
            Slider(value: $playerViewModel.volume, in: 0...1)
                .frame(width: 70)
                .tint(miniTheme.colors.accent.opacity(0.8))
        }
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
                .font(.system(size: 11))
                .foregroundColor(miniTheme.colors.controlButtonColor)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }
    
    private func controlButton(icon: String, size: CGFloat, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(enabled ? miniTheme.colors.controlButtonColor : miniTheme.colors.controlButtonColor.opacity(0.3))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
    
    // MARK: - Helpers
    
    private func switchToFullMode() {
        displayMode = DisplayMode.full.rawValue
    }
    
    private func updateWindowLevel(alwaysOnTop: Bool) {
        guard let window = NSApp.windows.first else { return }
        window.level = alwaysOnTop ? .floating : .normal
    }
}

#Preview {
    MiniPlayerView()
        .environmentObject(PlayerViewModel())
}
