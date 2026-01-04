//
//  CollectionsGridView.swift
//  Me2Tune
//
//  专辑收藏视图:专辑卡片展示+详情视图+拖拽排序
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    let onAlbumMoved: (Int, Int) -> Void
    let onTrackAddedToPlaylist: (AudioTrack) -> Void
    let onEnsureLoaded: () async -> Void
    
    @State private var selectedAlbum: Album?
    @State private var artworkCache: [UUID: NSImage] = [:]
    @State private var renamingAlbumId: UUID?
    @State private var renameText = ""
    @State private var albumToDelete: Album?
    @State private var preloadedAlbumIds = Set<UUID>()
    @State private var hoveredAlbumId: UUID?
    @State private var hoveredTrackIndex: Int?
    @State private var columns: [GridItem] = [
        GridItem(.fixed(135), spacing: 14),
        GridItem(.fixed(135), spacing: 14),
        GridItem(.fixed(135), spacing: 14)
    ]
    
    // 拖拽状态
    @State private var draggingAlbumId: UUID?
    @State private var dropTargetIndex: Int?
    
    private let cardSize: CGFloat = 135
    private let spacing: CGFloat = 14
    
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
                    GeometryReader { geometry in
                        ScrollView(showsIndicators: false) {
                            LazyVGrid(columns: columns, spacing: spacing) {
                                ForEach(Array(albums.enumerated()), id: \.element.id) { _, album in
                                    AlbumCardView(
                                        album: album,
                                        artwork: artworkCache[album.id],
                                        isHovered: hoveredAlbumId == album.id,
                                        isDragging: draggingAlbumId == album.id,
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

// MARK: - Album Card View

struct AlbumCardView: View {
    let album: Album
    let artwork: NSImage?
    let isHovered: Bool
    let isDragging: Bool
    let onTap: () -> Void
    let onHoverChange: (Bool) -> Void
    let onRename: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            artworkView
            
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
        .opacity(isDragging ? 0.4 : 1.0)
        .scaleEffect(isHovered && !isDragging ? 1.02 : 1.0)
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
    
    private var artworkView: some View {
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
        .frame(width: 135, height: 135)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    Color.accent.opacity(isHovered && !isDragging ? 0.4 : 0),
                    lineWidth: 2
                )
        )
        .shadow(
            color: isHovered && !isDragging ? Color.accent.opacity(0.2) : .clear,
            radius: 8
        )
    }
}

// MARK: - Album Track Row View

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
        .background(background)
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
    
    @ViewBuilder
    private var background: some View {
        if isPlaying {
            Color.accentLight
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else if isHovered {
            Color.hoverBackground
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            Color.clear
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
        onAlbumMoved: { _, _ in },
        onTrackAddedToPlaylist: { _ in },
        onEnsureLoaded: {}
    )
    .padding()
    .background(Color.black)
}
