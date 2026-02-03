//
//  CollectionsGridView.swift
//  Me2Tune
//
//  专辑收藏视图: 专辑卡片展示 + 拖拽排序 + 滚动位置保持
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CollectionsGridView: View {
    @Binding var selectedTab: PlaylistTab
    @Binding var isInAlbumDetail: Bool
    @Binding var selectedAlbumId: UUID?
    let albums: [Album]
    let isLoaded: Bool
    let currentIndex: Int?
    let playingSource: PlayerViewModel.PlayingSource
    let onAlbumPlayAt: (Album, Int) -> Void
    let onAlbumRemoved: (UUID) -> Void
    let onAlbumRenamed: (UUID, String) -> Void
    let onAlbumMoved: (Int, Int) -> Void
    let onTrackAddedToPlaylist: (AudioTrack) -> Void
    let onEnsureLoaded: () async -> Void
    
    @State private var selectedAlbum: Album?
    @State private var artworkCache: [UUID: NSImage] = [:]
    @State private var renamingAlbumId: UUID?
    @State private var renameText = ""
    @State private var albumToDelete: Album?
    @State private var preloadedAlbumIds = Set<UUID>()
    @State private var columns: [GridItem] = [
        GridItem(.fixed(135), spacing: 14),
        GridItem(.fixed(135), spacing: 14),
        GridItem(.fixed(135), spacing: 14)
    ]
    
    @State private var draggingAlbumId: UUID?
    @State private var dropTargetIndex: Int?
    @State private var lastViewedAlbumId: UUID?
    
    private let cardSize: CGFloat = 135
    private let spacing: CGFloat = 14
    
    var body: some View {
        Group {
            if let album = selectedAlbum {
                AlbumDetailView(
                    album: album,
                    artwork: artworkCache[album.id],
                    playingSource: playingSource,
                    currentIndex: currentIndex,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedAlbum = nil
                        }
                    },
                    onTrackTap: { index in
                        onAlbumPlayAt(album, index)
                    },
                    onShowInFinder: { track in
                        NSWorkspace.shared.activateFileViewerSelecting([track.url])
                    },
                    onAddToPlaylist: { track in
                        onTrackAddedToPlaylist(track)
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                albumGridView
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .task {
            await onEnsureLoaded()
        }

        // MARK: - State Synchronization and Restoration
        
        .onChange(of: selectedAlbum) { _, newValue in
            isInAlbumDetail = (newValue != nil)
            selectedAlbumId = newValue?.id
        }
        
        // When selectedAlbumId is updated externally (e.g., by search), sync selectedAlbum
        .onChange(of: selectedAlbumId) { _, newId in
            if let newId, selectedAlbum?.id != newId {
                if let album = albums.first(where: { $0.id == newId }) {
                    selectedAlbum = album
                    Task {
                        await loadArtwork(for: album)
                    }
                }
            } else if newId == nil {
                selectedAlbum = nil
            }
        }
        
        // Fallback: Actively restore state when view reconstruction causes inconsistency
        .task(id: selectedAlbumId) {
            if let id = selectedAlbumId,
               selectedAlbum == nil,
               let album = albums.first(where: { $0.id == id })
            {
                selectedAlbum = album
                await loadArtwork(for: album)
            }
        }
        
        // MARK: - Alerts
        
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
                    GeometryReader { geometry in
                        ScrollViewReader { proxy in
                            ScrollView(showsIndicators: false) {
                                LazyVGrid(columns: columns, spacing: spacing) {
                                    ForEach(Array(albums.enumerated()), id: \.element.id) { _, album in
                                        AlbumCardView(
                                            album: album,
                                            artwork: artworkCache[album.id],
                                            isDragging: draggingAlbumId == album.id,
                                            onTap: {
                                                lastViewedAlbumId = album.id
                                                withAnimation(.easeInOut(duration: 0.25)) {
                                                    selectedAlbum = album
                                                }
                                            },
                                            onRename: {
                                                renamingAlbumId = album.id
                                                renameText = album.name
                                            },
                                            onRemove: {
                                                albumToDelete = album
                                            }
                                        )
                                        .id(album.id)
                                        .task {
                                            await loadArtwork(for: album)
                                        }
                                        .onAppear {
                                            preloadNearbyArtworks(for: album)
                                        }
                                        .onDrag {
                                            draggingAlbumId = album.id
                                            return NSItemProvider(object: album.id.uuidString as NSString)
                                        }
                                        .onDrop(of: [.text], delegate: AlbumDropDelegate(
                                            albumId: album.id,
                                            albums: albums,
                                            draggingAlbumId: $draggingAlbumId,
                                            dropTargetIndex: $dropTargetIndex,
                                            onDrop: { sourceIndex, targetIndex in
                                                onAlbumMoved(sourceIndex, targetIndex)
                                            }
                                        ))
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            .onAppear {
                                updateColumns(for: geometry.size.width)
                            }
                            .onChange(of: geometry.size.width) { _, newWidth in
                                updateColumns(for: newWidth)
                            }
                            .task(id: isInAlbumDetail) {
                                if !isInAlbumDetail, let targetId = lastViewedAlbumId {
                                    try? await Task.sleep(for: .milliseconds(200))
                                    await MainActor.run {
                                        proxy.scrollTo(targetId, anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Column Layout Logic
    
    private func updateColumns(for width: CGFloat) {
        let columnCount = max(2, Int((width + spacing) / (cardSize + spacing)))
        
        if columns.count != columnCount {
            columns = Array(repeating: GridItem(.fixed(cardSize), spacing: spacing), count: columnCount)
        }
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
        
        let range = max(0, index - 2) ... min(albums.count - 1, index + 5)
        let nearbyAlbums = range.compactMap { albums[safe: $0] }
        let urls = nearbyAlbums.compactMap { $0.tracks.first?.url }
        
        Task.detached(priority: .utility) {
            await ArtworkCacheService.shared.preloadArtworks(for: urls, priority: .utility)
        }
    }
}

// MARK: - Album Drop Delegate

struct AlbumDropDelegate: DropDelegate {
    let albumId: UUID
    let albums: [Album]
    @Binding var draggingAlbumId: UUID?
    @Binding var dropTargetIndex: Int?
    let onDrop: (Int, Int) -> Void
    
    func dropEntered(info: DropInfo) {
        guard let draggingId = draggingAlbumId,
              draggingId != albumId,
              let targetIndex = albums.firstIndex(where: { $0.id == albumId })
        else {
            return
        }
        
        dropTargetIndex = targetIndex
    }
    
    func dropExited(info: DropInfo) {
        dropTargetIndex = nil
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard let draggingId = draggingAlbumId,
              let sourceIndex = albums.firstIndex(where: { $0.id == draggingId }),
              let targetIndex = albums.firstIndex(where: { $0.id == albumId })
        else {
            draggingAlbumId = nil
            dropTargetIndex = nil
            return false
        }
        
        draggingAlbumId = nil
        dropTargetIndex = nil
        
        guard sourceIndex != targetIndex else { return false }
        
        var adjustedTarget = targetIndex
        if sourceIndex < targetIndex {
            adjustedTarget = targetIndex - 1
        }
        
        onDrop(sourceIndex, adjustedTarget)
        return true
    }
}

#Preview {
    CollectionsGridView(
        selectedTab: .constant(.collections),
        isInAlbumDetail: .constant(false),
        selectedAlbumId: .constant(nil),
        albums: [],
        isLoaded: true,
        currentIndex: nil,
        playingSource: .playlist,
        onAlbumPlayAt: { _, _ in },
        onAlbumRemoved: { _ in },
        onAlbumRenamed: { _, _ in },
        onAlbumMoved: { _, _ in },
        onTrackAddedToPlaylist: { _ in },
        onEnsureLoaded: {}
    )
    .padding()
    .background(Color.black)
}
