//
//  PlaylistView.swift
//  Me2Tune
//
//  播放列表视图：标签切换模式
//

import SwiftUI

enum PlaylistTab {
    case playlist
    case collections
}

struct PlaylistView: View {
    let tracks: [AudioTrack]
    let currentIndex: Int?
    let albums: [Album]
    @Binding var selectedTab: PlaylistTab
    let onTrackSelected: (Int) -> Void
    // 移除 onAlbumSelected，collections的操作不应影响AudioPlayerManager
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Tab Selector
            
            HStack(spacing: 0) {
                // 左侧标签区域 - 固定宽度防止位移
                HStack(spacing: 4) {
                    TabButton(
                        title: LocalizedStringKey("playlist"),
                        isSelected: selectedTab == .playlist,
                        action: { selectedTab = .playlist },
                    )
                    .frame(width: 70, alignment: .leading)
                    
                    TabButton(
                        title: LocalizedStringKey("collections"),
                        isSelected: selectedTab == .collections,
                        action: { selectedTab = .collections },
                    )
                    .frame(width: 90, alignment: .leading)
                }
                .padding(.leading, 16)
                
                Spacer()
                
                // 右侧功能按钮区域
                HStack(spacing: 12) {
                    if selectedTab == .playlist {
                        Button(action: {}) {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Export playlist")
                        
                        Button(action: {}) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Add tracks")
                        
                        Button(action: {}) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear")
                    } else {
                        Button(action: {}) {
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Sort")
                        
                        Button(action: {}) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Add collection")
                    }
                }
                .padding(.trailing, 16)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(white: 0.15))
            
            Divider()
            
            // MARK: - Content
            
            Group {
                if selectedTab == .playlist {
                    trackListView
                } else {
                    collectionView
                }
            }
        }
    }
    
    // MARK: - Track List
    
    private var trackListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRowView(
                        track: track,
                        index: index,
                        isPlaying: currentIndex == index,
                        onSelect: { onTrackSelected(index) },
                    )
                    
                    if index < tracks.count - 1 {
                        Divider()
                            .padding(.leading, 36)
                    }
                }
            }
        }
    }
    
    // MARK: - Collection View
    
    private var collectionView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if albums.isEmpty {
                    Text(LocalizedStringKey("collection_placeholder"))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(albums) { album in
                        AlbumRowView(album: album) {
                            // 专辑点击事件：未来用于进入专辑详情页，目前仅打印日志
                            print("🎵 专辑点击: \(album.name)")
                        }
                        
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
        }
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                
                Rectangle()
                    .fill(Color.orange)
                    .frame(height: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(isSelected ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - Album Row View

struct AlbumRowView: View {
    let album: Album
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(album.name)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                Text("\(album.tracks.count) tracks")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Group {
                if isHovered {
                    Color.white.opacity(0.05)
                } else {
                    Color.clear
                }
            },
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(count: 2) {
            onSelect()
        }
    }
}

// MARK: - Track Row View

struct TrackRowView: View {
    let track: AudioTrack
    let index: Int
    let isPlaying: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 序号/播放图标
            Group {
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 16, alignment: .trailing)
            
            // 曲目信息
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 13, weight: isPlaying ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isPlaying ? .primary : .primary)
                
                Text(LocalizedStringKey("unknown_artist"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 时长
            Text(formatTime(track.duration))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Group {
                if isPlaying {
                    Color.orange.opacity(0.2)
                } else if isHovered {
                    Color.white.opacity(0.05)
                } else {
                    Color.clear
                }
            },
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(count: 2) {
            onSelect()
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, !time.isNaN else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
