//
//  CollectionsGridView.swift
//  Me2Tune
//
//  专辑收藏视图：专辑卡片展示+详情视图（优化悬浮性能）
//

import AppKit
import SwiftUI

struct CollectionsGridView: View {
    @Binding var selectedTab: PlaylistTab
    @Binding var isInAlbumDetail: Bool
    let albums: [Album]
    let isLoaded: Bool
    let currentIndex: Int?
    let playingSource: PlayerViewModel.PlayingSource
    let onAlbumPlayAt: (Album, Int) -> Void
    let onAlbumRemoved: (UUID) -> Void
    let onAlbumRenamed: (UUID, String) -> Void
    let onTrackAddedToPlaylist: (AudioTrack) -> Void
    let onEnsureLoaded: () async -> Void
    
    @State private var selectedAlbum: Album?
    @State private var artworkCache: [UUID: NSImage] = [:]
    @State private var renamingAlbumId: UUID?
    @State private var renameText = ""
    @State private var albumToDelete: Album?
    @State private var preloadedAlbumIds = Set<UUID>()
    @State private var hoveredAlbumId: UUID? // 共享的 hover 状态
    @State private var hoveredTrackIndex: Int? // 共享的 track hover 状态
    
    var body: some View {
        Group {
            if let album = selectedAlbum {
                albumDetailView(album: album)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                albumGridView
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .task {
            await onEnsureLoaded()
        }
        .onChange(of: selectedAlbum) { _, newValue in
            isInAlbumDetail = (newValue != nil)
        }
        .alert("rename_album", isPresented: Binding(
            get: { renamingAlbumId != nil },
            set: { if !$0 { renamingAlbumId = nil } }
        )) {
            TextField("album_name", text: $renameText)
            Button("cancel", role: .cancel) {
                renamingAlbumId = nil
            }
            Button("rename") {
                if let albumId = renamingAlbumId, !renameText.isEmpty {
                    onAlbumRenamed(albumId, renameText)
                }
                renamingAlbumId = nil
            }
        } message: {
            Text("enter_new_album_name")
        }
        .alert("remove_album", isPresented: Binding(
            get: { albumToDelete != nil },
            set: { if !$0 { albumToDelete = nil } }
        )) {
            Button("cancel", role: .cancel) {
                albumToDelete = nil
            }
            Button("remove", role: .destructive) {
                if let album = albumToDelete {
                    onAlbumRemoved(album.id)
                }
                albumToDelete = nil
            }
        } message: {
            if let album = albumToDelete {
                let format = String(localized: "remove_album_confirm")
                Text(String(format: format, album.name))
            }
        }
    }
    
    // MARK: - Album Grid View
    
    private var albumGridView: some View {
        VStack(spacing: 0) {
            Group {
                if albums.isEmpty {
                    if isLoaded {
                        emptyStateView
                    } else {
                        loadingView
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
                        ], spacing: 16) {
                            ForEach(albums) { album in
                                AlbumCardView(
                                    album: album,
                                    artwork: artworkCache[album.id],
                                    isHovered: hoveredAlbumId == album.id,
                                    onTap: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            selectedAlbum = album
                                        }
                                    },
                                    onHoverChange: { isHovered in
                                        hoveredAlbumId = isHovered ? album.id : nil
                                    },
                                    onRename: {
                                        renamingAlbumId = album.id
                                        renameText = album.name
                                    },
                                    onRemove: {
                                        albumToDelete = album
                                    }
                                )
                                .task {
                                    await loadArtwork(for: album)
                                }
                                .onAppear {
                                    preloadNearbyArtworks(for: album)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
    
    // MARK: - Album Detail View
    
    private func albumDetailView(album: Album) -> some View {
        VStack(spacing: 0) {
            albumHeader(album: album)
            
            Divider()
                .padding(.horizontal, 12)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                        AlbumTrackRowView(
                            track: track,
                            index: index,
                            isPlaying: {
                                if case .album(let id) = playingSource {
                                    return id == album.id && currentIndex == index
                                }
                                return false
                            }(),
                            isHovered: hoveredTrackIndex == index,
                            onTap: {
                                onAlbumPlayAt(album, index)
                            },
                            onHoverChange: { isHovered in
                                hoveredTrackIndex = isHovered ? index : nil
                            },
                            onShowInFinder: {
                                NSWorkspace.shared.activateFileViewerSelecting([track.url])
                            },
                            onAddToPlaylist: {
                                onTrackAddedToPlaylist(track)
                            }
                        )
                    }
                }
            }
        }
    }
    
    private func albumHeader(album: Album) -> some View {
        HStack(spacing: 16) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedAlbum = nil
                }
            }) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.accent)
            }
            .buttonStyle(.plain)
            
            Group {
                if let artwork = artworkCache[album.id] {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Image(systemName: "opticaldisc")
                                .font(.system(size: 24))
                                .foregroundColor(.emptyStateIcon)
                        )
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primaryText)
                    .lineLimit(2)
                
                Text("\(album.tracks.count) tracks")
                    .font(.system(size: 12))
                    .foregroundColor(.secondaryText)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .background(Color.selectedBackground)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.emptyStateIcon)
            
            Text("no_collections_yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondaryText)
            
            Text("drag_folders_here")
                .font(.system(size: 12))
                .foregroundColor(.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading Collections...")
                .font(.system(size: 14))
                .foregroundColor(.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
    
    // MARK: - Artwork Loading
    
    private func loadArtwork(for album: Album) async {
        guard artworkCache[album.id] == nil,
              let firstTrack = album.tracks.first
        else {
            return
        }
        
        if let artwork = await ArtworkCacheService.shared.artwork(for: firstTrack.url) {
            await MainActor.run {
                artworkCache[album.id] = artwork
            }
        }
    }
    
    private func preloadNearbyArtworks(for album: Album) {
        guard !preloadedAlbumIds.contains(album.id) else {
            return
        }
        preloadedAlbumIds.insert(album.id)
        
        guard let index = albums.firstIndex(where: { $0.id == album.id }) else {
            return
        }
        
        let range = max(0, index - 2)...min(albums.count - 1, index + 5)
        let nearbyAlbums = range.compactMap { albums[safe: $0] }
        let urls = nearbyAlbums.compactMap { $0.tracks.first?.url }
        
        Task.detached(priority: .utility) {
            await ArtworkCacheService.shared.preloadArtworks(for: urls, priority: .utility)
        }
    }
}

// MARK: - Album Card View (优化版)

struct AlbumCardView: View {
    let album: Album
    let artwork: NSImage?
    let isHovered: Bool
    let onTap: () -> Void
    let onHoverChange: (Bool) -> Void
    let onRename: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Image(systemName: "opticaldisc")
                                .font(.system(size: 40))
                                .foregroundColor(.emptyStateIcon)
                        )
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        Color.accent.opacity(isHovered ? 0.4 : 0),
                        lineWidth: 2
                    )
            )
            .shadow(
                color: Color.accent.opacity(isHovered ? 0.3 : 0),
                radius: isHovered ? 12 : 0
            )
            
            VStack(spacing: 2) {
                Text(album.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                
                Text("\(album.tracks.count) tracks")
                    .font(.system(size: 11))
                    .foregroundColor(.secondaryText)
            }
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onTapGesture {
            onTap()
        }
        .onHover { hovering in
            onHoverChange(hovering)
        }
        .contextMenu {
            Button("rename") {
                onRename()
            }
            
            Divider()
            
            Button("remove", role: .destructive) {
                onRemove()
            }
        }
    }
}

// MARK: - Album Track Row View (优化版)

struct AlbumTrackRowView: View {
    let track: AudioTrack
    let index: Int
    let isPlaying: Bool
    let isHovered: Bool
    let onTap: () -> Void
    let onHoverChange: (Bool) -> Void
    let onShowInFinder: () -> Void
    let onAddToPlaylist: () -> Void
    
    var body: some View {
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
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(backgroundColor)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onTap()
        }
        .onHover { hovering in
            onHoverChange(hovering)
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
    
    private var backgroundColor: Color {
        if isPlaying {
            return .accentLight
        } else if isHovered {
            return .hoverBackground
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

#Preview {
    CollectionsGridView(
        selectedTab: .constant(.collections),
        isInAlbumDetail: .constant(false),
        albums: [],
        isLoaded: true,
        currentIndex: nil,
        playingSource: .playlist,
        onAlbumPlayAt: { _, _ in },
        onAlbumRemoved: { _ in },
        onAlbumRenamed: { _, _ in },
        onTrackAddedToPlaylist: { _ in },
        onEnsureLoaded: {}
    )
    .padding()
    .background(Color.black)
}
