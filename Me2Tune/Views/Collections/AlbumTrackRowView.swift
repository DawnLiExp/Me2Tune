//
//  AlbumTrackRowView.swift
//  Me2Tune
//
//  专辑歌曲行组件
//

import SwiftUI

struct AlbumTrackRowView: View {
    let track: AudioTrack
    let index: Int
    let isPlaying: Bool
    let onTap: () -> Void
    let onShowInFinder: () -> Void
    let onAddToPlaylist: () -> Void
    
    @State private var isHovered = false
    @AppStorage("CleanMode") private var cleanMode = false
    
    var body: some View {
        ZStack {
            contentView
            
            // 简洁模式下跳过 hover 检测
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
            Group {
                if isPlaying {
                    Image(systemName: "waveform")
                        .foregroundColor(.accent)
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondaryText)
                }
            }
            .frame(width: 24)
            
            Text(track.title)
                .font(.system(size: 14, weight: isPlaying ? .semibold : .regular))
                .foregroundColor(isPlaying ? .primaryText : .primaryText.opacity(0.8))
                .lineLimit(1)
            
            Spacer()
            
            Text(track.artist ?? String(localized: "unknown_artist"))
                .font(.system(size: 13))
                .foregroundColor(.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .trailing)
            
            Text(formatTime(track.duration))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.secondaryText)
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
    
    // MARK: - Helper
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, !time.isNaN else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
