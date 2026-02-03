//
//  AlbumTrackRowView.swift
//  Me2Tune
//
//  专辑歌曲行组件 - 失败标记支持
//

import SwiftUI

struct AlbumTrackRowView: View {
    let track: AudioTrack
    let index: Int
    let isPlaying: Bool
    let isFailed: Bool // ✅ 新增：失败标记
    let onTap: () -> Void
    let onShowInFinder: () -> Void
    let onAddToPlaylist: () -> Void
    
    @State private var isHovered = false
    @AppStorage("CleanMode") private var cleanMode = false
    
    var body: some View {
        ZStack {
            contentView
            
            if !cleanMode {
                HoverDetectingView(isHovered: $isHovered)
                    .allowsHitTesting(false)
            }
        }
        .onTapGesture(count: 2) {
            onTap()
        }
        .contextMenu {
            Button("show_in_finder") {
                onShowInFinder()
            }
            
            Button("add_to_playlist") {
                onAddToPlaylist()
            }
        }
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        HStack(spacing: 12) {
            indexOrIndicator
                .frame(width: 24)
            
            Text(track.title)
                .font(.system(size: 14, weight: isPlaying ? .semibold : .regular))
                .foregroundColor(textColor)
                .lineLimit(1)
            
            Spacer()
            
            Text(track.artist ?? String(localized: "unknown_artist"))
                .font(.system(size: 13))
                .foregroundColor(.secondaryText.opacity(isFailed ? 0.5 : 1.0))
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .trailing)
            
            Text(formatTime(track.duration))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.secondaryText.opacity(isFailed ? 0.5 : 1.0))
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background {
            if isPlaying {
                Color.accentLight
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else if isHovered, !cleanMode {
                Color.hoverBackground
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .contentShape(Rectangle())
        .drawingGroup()
    }
    
    // MARK: - Index or Indicator
    
    @ViewBuilder
    private var indexOrIndicator: some View {
        if isFailed {
            // ✅ 失败标记：警告图标
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange.opacity(0.8))
                .font(.system(size: 12, weight: .semibold))
        } else if isPlaying {
            Image(systemName: "waveform")
                .foregroundColor(.accent)
                .font(.system(size: 13, weight: .semibold))
        } else {
            Text("\(index + 1)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondaryText)
        }
    }
    
    // MARK: - Text Color
    
    private var textColor: Color {
        if isFailed {
            return .primaryText.opacity(0.4)
        } else if isPlaying {
            return .primaryText
        } else {
            return .primaryText.opacity(0.8)
        }
    }
    
    // MARK: - Helper
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, !time.isNaN else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
