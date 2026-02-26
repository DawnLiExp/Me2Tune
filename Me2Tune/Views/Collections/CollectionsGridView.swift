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
    @Environment(CollectionManager.self) private var collectionManager
    @Binding var selectedTab: PlaylistTab
    @Binding var isInAlbumDetail: Bool
    @Binding var selectedAlbumId: UUID?
    let albums: [Album]
    let isLoaded: Bool
    let isActiveTab: Bool
    let currentIndex: Int?
    let playingSource: PlayerViewModel.PlayingSource
    let onAlbumPlayAt: (Album, Int) -> Void
    let onAlbumRemoved: (UUID) -> Void
    let onAlbumRenamed: (UUID, String) -> Void
    let onAlbumMoved: (Int, Int) -> Void
    let onTrackAddedToPlaylist: (AudioTrack) -> Void
    let onEnsureLoaded: () async -> Void
    
    @State private var selectedAlbum: Album?
    @State private var selectedAlbumArtwork: NSImage?
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
    
    private let cardSize: CGFloat = 135
    private let spacing: CGFloat = 14

    // MARK: - Body
    
    var body: some View {
        // ZStack 保持 albumGridView 始终驻留渲染树，避免 LazyVGrid 重建导致 cell 飞入动画
        ZStack {
            albumGridView
                .opacity(selectedAlbum != nil ? 0 : 1)
                .offset(x: selectedAlbum != nil ? -100 : 0)
                .disabled(selectedAlbum != nil)
            
            if let album = selectedAlbum {
                AlbumDetailView(
                    album: album,
                    artwork: selectedAlbumArtwork,
                    playingSource: playingSource,
                    currentIndex: currentIndex,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedAlbum = nil
                            selectedAlbumArtwork = nil
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
                .zIndex(1)
            }
        }
        .task {
            // Prevent background ZStack view from triggering load before user selects this tab
            if selectedTab == .collections {
                await onEnsureLoaded()
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .collections {
                Task { await onEnsureLoaded() }
            }
        }

        // MARK: - State Synchronization and Restoration
        
        .onChange(of: selectedAlbum) { _, newValue in
            isInAlbumDetail = (newValue != nil)
            selectedAlbumId = newValue?.id
        }
        
        // When selectedAlbumId is updated externally (e.g., by search), sync selectedAlbum
        // artwork 为 nil：由 AlbumDetailView.task 冷启动路径异步补全
        .onChange(of: selectedAlbumId) { _, newId in
            if let newId, selectedAlbum?.id != newId {
                if let album = albums.first(where: { $0.id == newId }) {
                    selectedAlbum = album
                }
            } else if newId == nil {
                selectedAlbum = nil
                selectedAlbumArtwork = nil
            }
        }
        
        // Fallback: Actively restore state when view reconstruction causes inconsistency
        .task(id: selectedAlbumId) {
            if let id = selectedAlbumId,
               selectedAlbum == nil,
               let album = albums.first(where: { $0.id == id })
            {
                selectedAlbum = album
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
        Group {
            if albums.isEmpty {
                if isLoaded {
                    emptyStateView
                } else {
                    loadingView
                }
            } else {
                @Bindable var manager = collectionManager
                GeometryReader { geometry in
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: columns, spacing: spacing) {
                            ForEach(Array(albums.enumerated()), id: \.element.id) { _, album in
                                AlbumCardView(
                                    album: album,
                                    isDragging: draggingAlbumId == album.id,
                                    onTap: { artwork in
                                        selectedAlbumArtwork = artwork
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
                                .equatable()
                                .id(album.id)
                                .onAppear {
                                    preloadNearbyArtworks(for: album)
                                }
                                .onDrag {
                                    // 始终挂载，通过 isActiveTab 控制行为而非结构
                                    // 避免 modifier 动态添加/移除导致 cell identity 错乱
                                    guard isActiveTab else { return NSItemProvider() }
                                    draggingAlbumId = album.id
                                    return NSItemProvider(object: album.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: AlbumDropDelegate(
                                    albumId: album.id,
                                    albums: albums,
                                    isActiveTab: isActiveTab,
                                    draggingAlbumId: $draggingAlbumId,
                                    dropTargetIndex: $dropTargetIndex,
                                    onDrop: { sourceIndex, targetIndex in
                                        onAlbumMoved(sourceIndex, targetIndex)
                                    }
                                ))
                            }
                        }
                        .padding(.vertical, 8)
                        .scrollTargetLayout()
                    }
                    .scrollPosition(id: $manager.lastScrollAlbumId)
                    .onAppear {
                        updateColumns(for: geometry.size.width)
                    }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        updateColumns(for: newWidth)
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
    
    // MARK: - Preload
    
    private func preloadNearbyArtworks(for album: Album) {
        guard !preloadedAlbumIds.contains(album.id) else { return }
        preloadedAlbumIds.insert(album.id)
        
        guard let index = albums.firstIndex(where: { $0.id == album.id }) else { return }
        
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
    let isActiveTab: Bool
    @Binding var draggingAlbumId: UUID?
    @Binding var dropTargetIndex: Int?
    let onDrop: (Int, Int) -> Void
    
    func validateDrop(info: DropInfo) -> Bool {
        // 非激活 tab 时拒绝，让 macOS 将拖拽传递给下方的 playlist drop 区域
        guard isActiveTab else { return false }
        // 只接受文字类型（专辑 UUID），不拦截来自 Finder 的文件拖拽
        return info.hasItemsConforming(to: [.text])
    }
    
    func dropEntered(info: DropInfo) {
        guard isActiveTab else { return }
        guard let draggingId = draggingAlbumId,
              draggingId != albumId,
              let targetIndex = albums.firstIndex(where: { $0.id == albumId })
        else { return }
        
        dropTargetIndex = targetIndex
    }
    
    func dropExited(info: DropInfo) {
        guard isActiveTab else { return }
        dropTargetIndex = nil
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard isActiveTab else { return false }
        
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
        isActiveTab: true,
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
