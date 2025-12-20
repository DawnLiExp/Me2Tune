//
//  PlayerControlsView.swift
//  Me2Tune
//
//  紧凑型播放控制面板 - 循环播放和音量控制
//

import SwiftUI

struct PlayerControlsView: View {
    let currentTrack: AudioTrack?
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let canGoPrevious: Bool
    let canGoNext: Bool
    let repeatMode: AudioPlayerManager.RepeatMode
    let volume: Double
    
    let onPlayPause: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onToggleMiniMode: () -> Void
    let onToggleRepeat: () -> Void
    let onVolumeChange: (Double) -> Void
    
    @State private var isSeekingManually = false
    @State private var manualSeekValue: TimeInterval = 0
    @State private var showRemainingTime = false
    @State private var hoveredButton: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Progress Bar (分界线)
            
            progressBar
            
            // MARK: - Controls Row 1: 循环 + 音量 + 时间
            
            HStack(spacing: 12) {
                // 循环播放按钮
                Button(action: onToggleRepeat) {
                    Image(systemName: repeatIcon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(repeatMode != .off ? .orange : (hoveredButton == "repeat" ? .primary : .secondary))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .onHover { hoveredButton = $0 ? "repeat" : nil }
                
                Spacer()
                
                // 音量控制
                HStack(spacing: 8) {
                    Button(action: { onVolumeChange(max(0, volume - 0.1)) }) {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(hoveredButton == "volume-down" ? .primary : .secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .onHover { hoveredButton = $0 ? "volume-down" : nil }
                    
                    CompactVolumeSlider(value: Binding(
                        get: { volume },
                        set: { onVolumeChange($0) },
                    ))
                    .frame(width: 80)
                    
                    Button(action: { onVolumeChange(min(1, volume + 0.1)) }) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(hoveredButton == "volume-up" ? .primary : .secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .onHover { hoveredButton = $0 ? "volume-up" : nil }
                }
                
                Spacer()
                
                // 时间显示（固定宽度避免挤压）
                Button(action: { showRemainingTime.toggle() }) {
                    Text(timeText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            // MARK: - Controls Row 2: 播放控制
            
            HStack(spacing: 0) {
                IconButton(
                    icon: "ellipsis",
                    size: 16,
                    isHovered: hoveredButton == "mini",
                    isEnabled: true,
                    action: onToggleMiniMode,
                )
                .onHover { hoveredButton = $0 ? "mini" : nil }
                
                Spacer()
                
                HStack(spacing: 20) {
                    IconButton(
                        icon: "backward.fill",
                        size: 18,
                        isHovered: hoveredButton == "prev",
                        isEnabled: canGoPrevious,
                        action: onPrevious,
                    )
                    .onHover { hoveredButton = $0 ? "prev" : nil }
                    
                    playPauseButton
                    
                    IconButton(
                        icon: "forward.fill",
                        size: 18,
                        isHovered: hoveredButton == "next",
                        isEnabled: canGoNext,
                        action: onNext,
                    )
                    .onHover { hoveredButton = $0 ? "next" : nil }
                }
                
                Spacer()
                
                IconButton(
                    icon: "magnifyingglass",
                    size: 16,
                    isHovered: hoveredButton == "search",
                    isEnabled: false,
                ) {}
                    .onHover { hoveredButton = $0 ? "search" : nil }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 扩大的点击区域（透明）
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 16)
                
                // 视觉进度条（紧贴顶部）
                VStack(spacing: 0) {
                    ZStack(alignment: .leading) {
                        // 背景轨道
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 2)
                        
                        // 进度轨道
                        Rectangle()
                            .fill(Color.orange)
                            .frame(
                                width: max(0, geometry.size.width * progress - 4),
                                height: 2,
                            )
                        
                        // 进度圆点（始终占据空间，用透明度控制显示）
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                            .shadow(color: Color.orange.opacity(0.5), radius: 2, x: 0, y: 1)
                            .offset(x: geometry.size.width * progress - 4, y: 0)
                            .opacity((isPlaying || isSeekingManually) ? 1.0 : 0.0)
                    }
                    
                    Spacer()
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isSeekingManually {
                            isSeekingManually = true
                        }
                        let newProgress = min(max(0, value.location.x / geometry.size.width), 1)
                        manualSeekValue = newProgress * max(duration, 0.1)
                    }
                    .onEnded { value in
                        let newProgress = min(max(0, value.location.x / geometry.size.width), 1)
                        let seekTime = newProgress * max(duration, 0.1)
                        onSeek(seekTime)
                        isSeekingManually = false
                    },
            )
        }
        .frame(height: 16)
    }
    
    // MARK: - Play/Pause Button
    
    private var playPauseButton: some View {
        Button(action: onPlayPause) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .scaleEffect(hoveredButton == "play" ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(currentTrack == nil)
        .opacity(currentTrack == nil ? 0.3 : 1.0)
        .onHover { hoveredButton = $0 ? "play" : nil }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hoveredButton == "play")
    }
    
    // MARK: - Helpers
    
    private var repeatIcon: String {
        switch repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
    
    private var progress: CGFloat {
        let time = isSeekingManually ? manualSeekValue : currentTime
        let total = max(duration, 0.1)
        return CGFloat(min(max(time / total, 0), 1))
    }
    
    private var timeText: String {
        if showRemainingTime {
            let remaining = duration - currentTime
            return "-" + formatTime(remaining)
        } else {
            return formatTime(currentTime)
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, !time.isNaN else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Icon Button Component

struct IconButton: View {
    let icon: String
    let size: CGFloat
    let isHovered: Bool
    let isEnabled: Bool
    var action: () -> Void = {}
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isEnabled ? (isHovered ? .primary : .secondary) : .tertiary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - Compact Volume Slider

struct CompactVolumeSlider: View {
    @Binding var value: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 3)
                
                // 进度
                Capsule()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: geometry.size.width * value, height: 3)
                
                // Thumb (更小的圆点)
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .offset(x: geometry.size.width * value - 4)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newValue = min(max(0, gesture.location.x / geometry.size.width), 1)
                        value = newValue
                    },
            )
        }
        .frame(height: 20)
    }
}
