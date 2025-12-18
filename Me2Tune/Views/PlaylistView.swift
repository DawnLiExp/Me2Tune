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
    let onTrackRemoved: (Int) -> Void // 删除歌曲回调
    let onPlaylistCleared: () -> Void // 清空播放列表回调
    let onAlbumRemoved: (UUID) -> Void // 删除专辑回调
    let onAlbumRenamed: (UUID, String) -> Void // 重命名专辑回调
    let onCollectionCleared: () -> Void // 清空专辑列表回调
    
    @State private var selectedAlbumId: UUID? // 当前查看的专辑详情
    @State private var artworkCache: [UUID: NSImage] = [:] // 封面缓存
    @State private var showClearPlaylistAlert = false // 清空播放列表确认
    @State private var showClearCollectionAlert = false // 清空专辑列表确认
    @State private var renamingAlbumId: UUID? // 正在重命名的专辑
    @State private var renameText = "" // 重命名输入框文本
    
    private let artworkService = ArtworkService()
    
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
                        
                        Button(action: {
                            showClearPlaylistAlert = true
                        }) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear playlist")
                    } else {
                        if selectedAlbumId == nil {
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
                            
                            Button(action: {
                                showClearCollectionAlert = true
                            }) {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Clear all collections")
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
        .alert("Clear Playlist", isPresented: $showClearPlaylistAlert) {
            Button(LocalizedStringKey("cancel"), role: .cancel) {}
            Button(LocalizedStringKey("clear"), role: .destructive) {
                onPlaylistCleared()
            }
        } message: {
            Text(LocalizedStringKey("clear_playlist_confirm"))
        }
        .alert("Clear All Collections", isPresented: $showClearCollectionAlert) {
            Button(LocalizedStringKey("cancel"), role: .cancel) {}
            Button(LocalizedStringKey("clear"), role: .destructive) {
                onCollectionCleared()
            }
        } message: {
            Text(LocalizedStringKey("clear_collections_confirm"))
        }
        .alert("Rename Album", isPresented: Binding(
            get: { renamingAlbumId != nil },
            set: { if !$0 { renamingAlbumId = nil } },
        )) {
            TextField(LocalizedStringKey("album_name"), text: $renameText)
            Button(LocalizedStringKey("cancel"), role: .cancel) {
                renamingAlbumId = nil
            }
            Button(LocalizedStringKey("rename")) {
                if let albumId = renamingAlbumId, !renameText.isEmpty {
                    onAlbumRenamed(albumId, renameText)
                }
                renamingAlbumId = nil
            }
        } message: {
            Text(LocalizedStringKey("enter_new_album_name"))
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
                        .contextMenu {
                            Button(LocalizedStringKey("show_in_finder")) {
                                NSWorkspace.shared.activateFileViewerSelecting([track.url])
                            }
                            
                            Divider()
                            
                            Button(LocalizedStringKey("remove")) {
                                onTrackRemoved(index)
                            }
                        }
                        
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
                            artwork: artworkCache[album.id],
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
                        .contextMenu {
                            Button(LocalizedStringKey("rename")) {
                                renamingAlbumId = album.id
                                renameText = album.name
                            }
                            
                            Divider()
                            
                            Button(LocalizedStringKey("delete_album")) {
                                onAlbumRemoved(album.id)
                            }
                        }
                        .task {
                            await loadArtwork(for: album)
                        }
                        
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
                HStack(spacing: 12) {
                    // 专辑封面
                    Group {
                        if let artwork = artworkCache[album.id] {
                            Image(nsImage: artwork)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "opticaldisc")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(album.name)
                            .font(.system(size: 13, weight: .semibold))
                        
                        Text("\(album.tracks.count) tracks")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    
                    Spacer()
                    
                    // 返回按钮
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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.03))
                .task {
                    await loadArtwork(for: album)
                }
                
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
                    .contextMenu {
                        Button(LocalizedStringKey("show_in_finder")) {
                            NSWorkspace.shared.activateFileViewerSelecting([track.url])
                        }
                        
                        Divider()
                        
                        Button(LocalizedStringKey("remove")) {
                            // TODO: 从专辑中删除歌曲
                        }
                    }
                    
                    if index < album.tracks.count - 1 {
                        Divider()
                            .padding(.leading, 36)
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func loadArtwork(for album: Album) async {
        guard artworkCache[album.id] == nil,
              let firstTrack = album.tracks.first
        else {
            return
        }
        
        if let artwork = await artworkService.artwork(for: firstTrack.url) {
            await MainActor.run {
                artworkCache[album.id] = artwork
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
    let artwork: NSImage?
    let isPlaying: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 左侧指示器
            Group {
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange)
                } else {
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 16, alignment: .center)
            
            // 专辑封面
            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary),
                        )
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            
            // 专辑信息
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
            
            // 右侧箭头（悬浮显示）
            if isHovered {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
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
