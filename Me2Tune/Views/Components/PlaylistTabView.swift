//
//  PlaylistTabView.swift
//  Me2Tune
//
//  播放列表视图：歌曲列表 + 拖拽排序（macOS onDrag/onDrop）
//

import SwiftUI
import UniformTypeIdentifiers

struct PlaylistTabView: View {
    @Binding var selectedTab: PlaylistTab
    let tracks: [AudioTrack]
    let currentIndex: Int?
    let playingSource: AudioPlayerManager.PlayingSource
    let onTrackSelected: (Int) -> Void
    let onTrackRemoved: (Int) -> Void
    let onTrackMoved: (IndexSet, Int) -> Void
    
    @State private var draggingIndex: Int?
    @State private var dropTargetIndex: Int?
    
    var body: some View {
        Group {
            if tracks.isEmpty {
                emptyStateView
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            VStack(spacing: 0) {
                                if dropTargetIndex == index {
                                    dropIndicator
                                }
                                
                                songRow(track: track, index: index)
                                    .opacity(draggingIndex == index ? 0.5 : 1.0)
                                    .onDrag {
                                        draggingIndex = index
                                        return NSItemProvider(object: "\(index)" as NSString)
                                    }
                                    .onDrop(of: [.text], delegate: TrackDropDelegate(
                                        targetIndex: index,
                                        draggingIndex: $draggingIndex,
                                        dropTargetIndex: $dropTargetIndex,
                                        onDrop: { from, to in
                                            guard from != to else { return }
                                            let fromSet = IndexSet(integer: from)
                                            var destination = to
                                            if from < to {
                                                destination = to - 1
                                            }
                                            onTrackMoved(fromSet, destination)
                                        }
                                    ))
                                    .contextMenu {
                                        Button("show_in_finder") {
                                            NSWorkspace.shared.activateFileViewerSelecting([track.url])
                                        }
                                        
                                        Divider()
                                        
                                        Button("remove") {
                                            onTrackRemoved(index)
                                        }
                                    }
                            }
                        }
                        
                        // 最后一行的 drop 区域
                        if !tracks.isEmpty {
                            VStack(spacing: 0) {
                                if dropTargetIndex == tracks.count {
                                    dropIndicator
                                }
                                
                                Color.clear
                                    .frame(height: 20)
                                    .onDrop(of: [.text], delegate: TrackDropDelegate(
                                        targetIndex: tracks.count,
                                        draggingIndex: $draggingIndex,
                                        dropTargetIndex: $dropTargetIndex,
                                        onDrop: { from, _ in
                                            let fromSet = IndexSet(integer: from)
                                            onTrackMoved(fromSet, tracks.count - 1)
                                        }
                                    ))
                            }
                        }
                    }
                    .padding(.bottom, 48)
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }
    
    // MARK: - Drop Indicator
    
    private var dropIndicator: some View {
        Rectangle()
            .fill(Color(hex: "#00E5FF"))
            .frame(height: 2)
            .padding(.horizontal, 10)
            .shadow(color: Color(hex: "#00E5FF").opacity(0.8), radius: 4)
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
        SongRowView(
            track: track,
            index: index,
            isPlaying: playingSource == .playlist && currentIndex == index,
            onTap: { onTrackSelected(index) }
        )
    }
}

// MARK: - Track Drop Delegate

struct TrackDropDelegate: DropDelegate {
    let targetIndex: Int
    @Binding var draggingIndex: Int?
    @Binding var dropTargetIndex: Int?
    let onDrop: (Int, Int) -> Void
    
    func dropEntered(info: DropInfo) {
        guard draggingIndex != targetIndex else { return }
        dropTargetIndex = targetIndex
    }
    
    func dropExited(info: DropInfo) {
        dropTargetIndex = nil
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard let from = draggingIndex else { return false }
        
        dropTargetIndex = nil
        draggingIndex = nil
        
        guard from != targetIndex else { return false }
        
        onDrop(from, targetIndex)
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// MARK: - Song Row View

struct SongRowView: View {
    let track: AudioTrack
    let index: Int
    let isPlaying: Bool
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
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
                .fill(backgroundColor)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onTap()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var backgroundColor: Color {
        if isPlaying {
            return Color(hex: "#00E5FF").opacity(0.08)
        } else if isHovered {
            return Color.white.opacity(0.05)
        } else {
            return Color.clear
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, !time.isNaN else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Toolbar Button

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
        onTrackRemoved: { _ in },
        onTrackMoved: { _, _ in }
    )
    .padding()
    .background(Color.black)
}
