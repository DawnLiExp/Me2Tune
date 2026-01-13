//
//  ControlSectionView.swift
//  Me2Tune
//
//  播放控制区域 - 进度条+控制按钮+歌曲信息+循环模式+音量控制
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
    
    @Binding var volume: Double
    
    @State private var isSeekingManually = false
    @State private var manualSeekValue: TimeInterval = 0
    @State private var isHoveringTrackInfo = false
    @State private var volumeBeforeMute: Double = 0.7
    @State private var hoverDelayTask: Task<Void, Never>?
    
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
        .onDisappear {
            hoverDelayTask?.cancel()
        }
    }
    
    // MARK: - Track Info Section
    
    private var trackInfoSection: some View {
        ZStack(alignment: .leading) {
            // 歌曲信息（默认显示）
            if !isHoveringTrackInfo || currentTrack == nil {
                VStack(alignment: .leading, spacing: 5) {
                    Text(currentTrack?.title ?? String(localized: "No Track"))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.accent)
                        .lineLimit(1)
                    
                    Text(trackSubtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.tertiaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
            
            // 设置控件（hover时显示）
            if isHoveringTrackInfo, currentTrack != nil {
                settingsControls
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoverDelayTask?.cancel()
            hoverDelayTask = nil
            
            if hovering, currentTrack != nil {
                // 鼠标移入：延迟 0.5 秒后触发
                hoverDelayTask = Task {
                    do {
                        try await Task.sleep(for: .milliseconds(500))
                    } catch {
                        return
                    }
                    
                    guard !Task.isCancelled else { return }
                    
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            isHoveringTrackInfo = true
                        }
                    }
                }
            } else {
                // 鼠标移出
                withAnimation(.easeInOut(duration: 0.3)) {
                    isHoveringTrackInfo = false
                }
            }
        }
    }
    
    private var trackSubtitle: String {
        guard let track = currentTrack else {
            return String(localized: "Ready to play")
        }
        
        let artist = track.artist ?? String(localized: "Unknown Artist")
        let album = track.albumTitle ?? ""
        
        if album.isEmpty {
            return artist
        } else {
            return "\(artist) • \(album)"
        }
    }
    
    // MARK: - Settings Controls (Repeat + Volume + Mini Switch)
    
    private var settingsControls: some View {
        HStack(spacing: 12) {
            switchToMiniButton
            volumeControl
            repeatButton
        }
    }
        
    private var switchToMiniButton: some View {
        Button(action: switchToMiniMode) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 14))
                .foregroundColor(.secondaryText)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Switch to Mini Mode"))
    }
        
    @AppStorage("displayMode") private var displayMode = DisplayMode.full.rawValue
        
    private func switchToMiniMode() {
        displayMode = DisplayMode.mini.rawValue
    }
    
    // MARK: - Repeat Button
    
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
        .help(String(localized: repeatTooltip))
        .rotationEffect(.degrees(rotationAngle))
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

    private var repeatTooltip: String.LocalizationValue {
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
    
    // MARK: - Volume Control
    
    private var volumeControl: some View {
        HStack(spacing: 8) {
            Button(action: toggleMute) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondaryText)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(volume > 0 ? String(localized: "Mute") : String(localized: "Unmute"))
            
            Slider(value: $volume, in: 0 ... 1)
                .frame(width: 100)
                .tint(.accent)
        }
    }
    
    private var volumeIcon: String {
        switch volume {
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
        if volume > 0 {
            volumeBeforeMute = volume
            volume = 0
        } else {
            volume = max(volumeBeforeMute, 0.1)
        }
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
                    .foregroundColor(.playButtonIconColor)
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
                .foregroundColor(enabled ? .controlButtonColor : .controlButtonColor.opacity(0.3))
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
        onToggleRepeat: {},
        volume: .constant(0.7)
    )
    .padding()
    .background(Color.black)
}
