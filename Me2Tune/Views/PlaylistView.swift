//
//  PlaylistView.swift
//  Me2Tune
//
//  播放列表视图：紧凑精致设计
//

import SwiftUI

enum PlaylistTab {
    case playlist
    case collections
}

struct PlaylistView: View {
    let tracks: [AudioTrack]
    let currentTracks: [AudioTrack]
    let currentIndex: Int?
    let playingSource: AudioPlayerManager.PlayingSource
    let albums: [Album]
    @Binding var selectedTab: PlaylistTab
    let onTrackSelected: (Int) -> Void
    let onAlbumSelected: (Album, Int) -> Void
    let onTrackRemoved: (Int) -> Void
    let onPlaylistCleared: () -> Void
    let onAlbumRemoved: (UUID) -> Void
    let onAlbumRenamed: (UUID, String) -> Void
    let onCollectionCleared: () -> Void
    
    @State private var selectedAlbumId: UUID?
    @State private var artworkCache: [UUID: NSImage] = [:]
    @State private var showClearPlaylistAlert = false
    @State private var showClearCollectionAlert = false
    @State private var renamingAlbumId: UUID?
    @State private var renameText = ""
    
    private let artworkService = ArtworkService()
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Tab Selector
            
            HStack(spacing: 0) {
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
                .padding(.leading, 12)
                
                Spacer()
                
                HStack(spacing: 10) {
                    if selectedTab == .playlist {
                        ToolbarButton(icon: "arrow.right.circle", tooltip: "Export playlist", action: {})
                        ToolbarButton(icon: "plus.circle", tooltip: "Add tracks", action: {})
                        ToolbarButton(icon: "xmark.circle", tooltip: "Clear playlist") {
                            showClearPlaylistAlert = true
                        }
                    } else {
                        if selectedAlbumId == nil {
                            ToolbarButton(icon: "arrow.up.arrow.down.circle", tooltip: "Sort", action: {})
                            ToolbarButton(icon: "plus.circle", tooltip: "Add collection", action: {})
                            ToolbarButton(icon: "xmark.circle", tooltip: "Clear all collections") {
                                showClearCollectionAlert = true
                            }
                        }
                    }
                }
                .padding(.trailing, 12)
            }
            .padding(.vertical, 10)
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
                                .padding(.leading, 44)
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
                            .padding(.leading, 42)
                    }
                }
            }
        }
    }
    
    // MARK: - Album Detail View
    
    private func albumDetailView(_ album: Album) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack(spacing: 10) {
                    Group {
                        if let artwork = artworkCache[album.id] {
                            Image(nsImage: artwork)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "opticaldisc")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(album.name)
                            .font(.system(size: 12, weight: .semibold))
                        
                        Text("\(album.tracks.count) tracks")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedAlbumId = nil
                        }
                    }) {
                        Image(systemName: "chevron.left.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Back to albums")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.03))
                .task {
                    await loadArtwork(for: album)
                }
                
                Divider()
                
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
                    }
                    
                    if index < album.tracks.count - 1 {
                        Divider()
                            .padding(.leading, 44)
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
