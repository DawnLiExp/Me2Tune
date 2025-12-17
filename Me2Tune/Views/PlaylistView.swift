//
//  PlaylistView.swift
//  Me2Tune
//
//  播放列表视图：标签切换模式 + 专辑详情
//

import SwiftUI

enum PlaylistTab {
    case playlist
    case collections
}

struct PlaylistView: View {
    let tracks: [AudioTrack]
    let currentTracks: [AudioTrack] // 当前播放列表
    let currentIndex: Int?
    let playingSource: AudioPlayerManager.PlayingSource
    let albums: [Album]
    @Binding var selectedTab: PlaylistTab
    let onTrackSelected: (Int) -> Void
    let onAlbumSelected: (Album, Int) -> Void
    
    @State private var selectedAlbumId: UUID? // 当前查看的专辑详情
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Tab Selector
            
            HStack(spacing: 0) {
                // 左侧标签区域
                HStack(spacing: 4) {
                    TabButton(
                        title: LocalizedStringKey("playlist"),
                        isSelected: selectedTab == .playlist,
                        action: {
                            selectedTab = .playlist
                            selectedAlbumId = nil
                        },
                    )
                    .frame(width: 70, alignment: .leading)
                    
                    TabButton(
                        title: LocalizedStringKey("collections"),
                        isSelected: selectedTab == .collections,
                        action: {
                            selectedTab = .collections
                        },
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
                        if selectedAlbumId != nil {
                            // 专辑详情页的返回按钮
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedAlbumId = nil
                                }
                            }) {
                                Image(systemName: "chevron.left.circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Back to albums")
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
                    playlistView
                } else {
                    if let albumId = selectedAlbumId,
                       let album = albums.first(where: { $0.id == albumId })
                    {
                        albumDetailView(album)
                    } else {
                        collectionListView
                    }
                }
            }
        }
    }
    
    // MARK: - Playlist View
    
    private var playlistView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if tracks.isEmpty {
                    Text(LocalizedStringKey("drop_files"))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        TrackRowView(
                            track: track,
                            index: index,
                            isPlaying: playingSource == .playlist && currentIndex == index,
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
    }
    
    // MARK: - Collection List View
    
    private var collectionListView: some View {
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
                        AlbumRowView(
                            album: album,
                            isPlaying: {
                                if case .album(let id) = playingSource {
                                    return id == album.id
                                }
                                return false
                            }(),
                            onSelect: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedAlbumId = album.id
                                }
                            },
                        )
                        
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
        }
    }
    
    // MARK: - Album Detail View
    
    private func albumDetailView(_ album: Album) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // 专辑标题
                HStack {
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    
                    Text(album.name)
                        .font(.system(size: 13, weight: .semibold))
                    
                    Spacer()
                    
                    Text("\(album.tracks.count) tracks")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.03))
                
                Divider()
                
                // 歌曲列表
                ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRowView(
                        track: track,
                        index: index,
                        isPlaying: {
                            if case .album(let id) = playingSource {
                                return id == album.id && currentIndex == index
                            }
                            return false
                        }(),
                        onSelect: { onAlbumSelected(album, index) },
                    )
                    
                    if index < album.tracks.count - 1 {
                        Divider()
                            .padding(.leading, 36)
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
    let isPlaying: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 16))
                .foregroundStyle(isPlaying ? .orange : .secondary)
                .frame(width: 16, alignment: .center)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(album.name)
                    .font(.system(size: 13, weight: isPlaying ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isPlaying ? .primary : .primary)
                
                Text("\(album.tracks.count) tracks")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isPlaying {
                Image(systemName: "waveform")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Group {
                if isPlaying {
                    Color.orange.opacity(0.15)
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
        .onTapGesture {
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
