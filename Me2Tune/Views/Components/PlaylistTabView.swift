//
//  PlaylistTabView.swift
//  Me2Tune
//
//  播放列表视图：歌曲列表
//

import SwiftUI

struct PlaylistTabView: View {
    @Binding var selectedTab: PlaylistTab
    let tracks: [AudioTrack]
    let currentIndex: Int?
    let playingSource: AudioPlayerManager.PlayingSource
    let onTrackSelected: (Int) -> Void
    let onTrackRemoved: (Int) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            if tracks.isEmpty {
                emptyStateView
            } else {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    songRow(track: track, index: index)
                        .contextMenu {
                            Button("show_in_finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([track.url])
                            }
                            
                            Divider()
                            
                            Button("remove") {
                                onTrackRemoved(index)
                            }
                        }
                    
                    if index < tracks.count - 1 {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("drop_files")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.gray)
            
            Text("supported_formats")
                .font(.system(size: 12))
                .foregroundColor(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
    
    // MARK: - Song Row
    
    private func songRow(track: AudioTrack, index: Int) -> some View {
        let isPlaying = playingSource == .playlist && currentIndex == index
        
        return HStack(spacing: 12) {
            Group {
                if isPlaying {
                    Image(systemName: "waveform")
                        .foregroundColor(Color(hex: "#00E5FF"))
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 24)
            
            Text(track.title)
                .font(.system(size: 14, weight: isPlaying ? .semibold : .regular))
                .foregroundColor(isPlaying ? .white : .white.opacity(0.8))
                .lineLimit(1)
            
            Spacer()
            
            Text(track.artist ?? String(localized: "unknown_artist"))
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .trailing)
            
            Text(formatTime(track.duration))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isPlaying ? Color(hex: "#00E5FF").opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onTrackSelected(index)
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, !time.isNaN else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Toolbar Button Component

struct ToolbarIconButton: View {
    let icon: String
    let tooltip: String
    var isEnabled: Bool = true
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isEnabled ? (isHovered ? .primary : .secondary) : .tertiary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(tooltip)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Tab Enum

enum PlaylistTab {
    case playlist
    case collections
}

#Preview {
    PlaylistTabView(
        selectedTab: .constant(.playlist),
        tracks: [],
        currentIndex: nil,
        playingSource: .playlist,
        onTrackSelected: { _ in },
        onTrackRemoved: { _ in }
    )
    .padding()
    .background(Color.black)
}
