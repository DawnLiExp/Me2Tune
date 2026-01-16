//
//  MiniPlayerView.swift
//  Me2Tune
//
//  Mini 播放器视图 - 封面填充优化版 + 精细化布局
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
        .frame(width: 440, height: 78) // 🖼️ 窗口尺寸：增加宽度和高度提升呼吸感
        .contextMenu {
            Toggle(isOn: $alwaysOnTop) {
                Label(String(localized: "always_on_top"), systemImage: "pin.fill")
            }
        }
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        HStack(spacing: 0) {
            // 封面：完全填充左侧
            artworkView
                .frame(width: 78, height: 78) // 📐 封面区域尺寸（与窗口高度一致）
            
            // 右侧内容区
            VStack(alignment: .leading, spacing: 10) { // 📏 上下间距 10
                trackInfoRow
                controlsRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14) // 📏 左右内边距 14
            .padding(.vertical, 10) // 📏 上下内边距 10
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
            // 歌曲信息
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
    
    // MARK: - Controls Row (主要调整区域)
    
    private var controlsRow: some View {
        HStack(spacing: 0) {
            // ========== 左侧：主任务组（循环 + 播放控制）==========
            HStack(spacing: 14) { // 📏 小组间距 14（循环 ↔ 播放组）
                // 循环按钮（对齐歌名左边缘）
                repeatButton
                
                // 播放控制组（⏮️▶️⏭️）
                HStack(spacing: 8) { // 📏 播放键组内间距 6（最紧密）
                    controlButton(
                        icon: "backward.end",
                        size: 24, // 🎛️ 前后按钮尺寸
                        enabled: playerViewModel.canGoPrevious,
                        action: playerViewModel.previous
                    )
                    
                    playPauseButton // ▶️ 主焦点按钮
                    
                    controlButton(
                        icon: "forward.end",
                        size: 24, // 🎛️ 前后按钮尺寸
                        enabled: playerViewModel.canGoNext,
                        action: playerViewModel.next
                    )
                }
            }
            
            Spacer(minLength: 24) // 📏 大组间距 24（主任务 ↔ 次任务）
            
            // ========== 右侧：次任务组（音量 + 模式切换）==========
            HStack(spacing: 16) { // 📏 小组间距 14（音量 ↔ 切换）
                // 音量控制
                volumeControl
                
                // 切换按钮（对齐时间右边缘）
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
                .frame(width: 24, height: 24) // 🎛️ 循环按钮尺寸
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
    
    // MARK: - Play/Pause Button (主焦点)
    
    private var playPauseButton: some View {
        Button(action: playerViewModel.togglePlayPause) {
            ZStack {
                // 背景凸起效果
          
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
    
    private var volumeControl: some View {
        HStack(spacing: 6) {
            Button(action: toggleMute) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(miniTheme.colors.controlButtonColor)
                    .frame(width: 20, height: 20) // 🎛️ 音量图标尺寸
            }
            .buttonStyle(.plain)
            
            MiniVolumeSlider(value: $playerViewModel.volume)
                .frame(width: 75, height: 20) // 🎚️ 音量滑块尺寸（够用但不抢焦点）
        }
        .frame(height: 24, alignment: .center) // 🎯 整体垂直居中，与喇叭图标对齐
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
                .frame(width: 22, height: 22) // 🎛️ 切换按钮尺寸（最小，低频操作）
        }
        .buttonStyle(.plain)
    }
    
    private func controlButton(icon: String, size: CGFloat, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size - 8, weight: .medium)) // 📐 图标比按钮框小 8pt
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
    MiniPlayerView()
        .environmentObject(PlayerViewModel())
}
