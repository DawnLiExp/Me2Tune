//
//  PlayerControlsView.swift
//  Me2Tune
//
//  播放控制面板：紧凑精致设计
//

import SwiftUI

struct PlayerControlsView: View {
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
    
    var body: some View {
        VStack(spacing: 12) {
            // MARK: - Track Info
            
            if let track = currentTrack {
                VStack(spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    
                    Text(track.artist ?? String(localized: "unknown_artist"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            
            // MARK: - Progress Bar
            
            HStack(spacing: 10) {
                Text(formatTime(currentTime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
                
                Slider(
                    value: Binding(
                        get: { currentTime },
                        set: { onSeek($0) },
                    ),
                    in: 0 ... max(duration, 0.1),
                )
                .controlSize(.small)
                
                Text(formatTime(duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)
            }
            
            // MARK: - Control Buttons
            
            HStack(spacing: 28) {
                Button(action: onPrevious) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(canGoPrevious ? .primary : .secondary)
                }
                .disabled(!canGoPrevious)
                .buttonStyle(.plain)
                
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(currentTrack == nil ? .secondary : .primary)
                }
                .disabled(currentTrack == nil)
                .buttonStyle(.plain)
                
                Button(action: onNext) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(canGoNext ? .primary : .secondary)
                }
                .disabled(!canGoNext)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, !time.isNaN else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
