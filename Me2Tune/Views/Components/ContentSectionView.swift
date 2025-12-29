//
//  ContentSectionView.swift
//  Me2Tune
//
//  内容区域 - 播放列表和专辑收藏容器
//

import SwiftUI

struct ContentSectionView: View {
    @Binding var selectedTab: PlaylistTab
    @Binding var isInAlbumDetail: Bool
    @Binding var isPlaylistCollapsed: Bool
    
    let playerViewModel: PlayerViewModel
    let collectionManager: CollectionManager
    
    let onExportPlaylist: () -> Void
    let onClearPlaylist: () -> Void
    let onClearCollections: () -> Void
    let onOpenFilePicker: () -> Void
    let onPlaylistDrop: ([URL]) -> Void
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                TabSwitcherView(
                    selectedTab: $selectedTab,
                    isInAlbumDetail: isInAlbumDetail,
                    playlistEmpty: playerViewModel.playlist.isEmpty,
                    collectionsEmpty: collectionManager.albums.isEmpty,
                    onExportPlaylist: onExportPlaylist,
                    onClearPlaylist: onClearPlaylist,
                    onClearCollections: onClearCollections,
                    onOpenFilePicker: onOpenFilePicker
                )
                .padding(.top, 12)
                .padding(.horizontal, 12)
                
                contentView
            }
            .frame(minHeight: 405)
            .background(containerBackground)
            
            CollapseButtonView(isCollapsed: $isPlaylistCollapsed)
                .offset(y: 8)
        }
        .allowsHitTesting(true)
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private var contentView: some View {
        if selectedTab == .playlist {
            PlaylistTabView(
                selectedTab: $selectedTab,
                tracks: playerViewModel.playlist,
                currentIndex: playerViewModel.currentTrackIndex,
                playingSource: playerViewModel.playingSource,
                onTrackSelected: { playerViewModel.playTrack(at: $0) },
                onTrackRemoved: { playerViewModel.removeTrack(at: $0) },
                onTrackMoved: { from, to in
                    if let sourceIndex = from.first {
                        playerViewModel.moveTrack(from: sourceIndex, to: to)
                    }
                },
                onFilesDrop: onPlaylistDrop
            )
            .padding(.horizontal, 12)
            .padding(.top, 16)
        } else {
            ScrollView(showsIndicators: false) {
                CollectionsGridView(
                    selectedTab: $selectedTab,
                    isInAlbumDetail: $isInAlbumDetail,
                    albums: collectionManager.albums,
                    isLoaded: collectionManager.isLoaded,
                    currentIndex: playerViewModel.currentTrackIndex,
                    playingSource: playerViewModel.playingSource,
                    onAlbumPlayAt: { album, index in
                        playerViewModel.playAlbum(album, startAt: index)
                    },
                    onAlbumRemoved: { albumId in
                        collectionManager.removeAlbum(id: albumId)
                    },
                    onAlbumRenamed: { albumId, newName in
                        collectionManager.renameAlbum(id: albumId, newName: newName)
                    },
                    onTrackAddedToPlaylist: { track in
                        playerViewModel.addTracks(urls: [track.url])
                    },
                    onEnsureLoaded: {
                        await collectionManager.ensureLoaded()
                    }
                )
                .frame(minHeight: 375)
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 48)
            }
        }
    }
    
    // MARK: - Container Background
    
    private var containerBackground: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(Color.containerBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .borderGradientStart,
                                .borderGradientEnd
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        ),
                        lineWidth: 1.5
                    )
            )
    }
}

// MARK: - Tab Switcher View

struct TabSwitcherView: View {
    @Binding var selectedTab: PlaylistTab
    let isInAlbumDetail: Bool
    let playlistEmpty: Bool
    let collectionsEmpty: Bool
    
    let onExportPlaylist: () -> Void
    let onClearPlaylist: () -> Void
    let onClearCollections: () -> Void
    let onOpenFilePicker: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            tabButton(title: String(localized: "playlist"), tab: .playlist)
            tabButton(title: String(localized: "collections"), tab: .collections)
            
            Spacer()
            
            if selectedTab == .playlist {
                playlistToolbar
            } else if !isInAlbumDetail {
                collectionsToolbar
            }
        }
    }
    
    // MARK: - Tab Button
    
    private func tabButton(title: String, tab: PlaylistTab) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedTab = tab
            }
        }) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundColor(selectedTab == tab ? .primaryText : .primaryText.opacity(0.5))
                
                if selectedTab == tab {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .accent,
                                    .accent.opacity(0.7)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 2)
                        .shadow(color: .accentGlow, radius: 4)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 2)
                }
            }
            .frame(width: 90)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Toolbars
    
    private var playlistToolbar: some View {
        HStack(spacing: 8) {
            ToolbarIconButton(
                icon: "arrow.right.circle",
                tooltip: String(localized: "export_to_collection"),
                isEnabled: !playlistEmpty,
                action: onExportPlaylist
            )
            
            ToolbarIconButton(
                icon: "plus.circle",
                tooltip: String(localized: "add_files"),
                action: onOpenFilePicker
            )
            
            ToolbarIconButton(
                icon: "xmark.circle",
                tooltip: String(localized: "clear_playlist"),
                isEnabled: !playlistEmpty,
                action: onClearPlaylist
            )
        }
    }
    
    private var collectionsToolbar: some View {
        HStack(spacing: 8) {
            ToolbarIconButton(
                icon: "plus.circle",
                tooltip: String(localized: "add_album"),
                action: onOpenFilePicker
            )
            
            ToolbarIconButton(
                icon: "xmark.circle",
                tooltip: String(localized: "clear_collections"),
                isEnabled: !collectionsEmpty,
                action: onClearCollections
            )
        }
    }
}

// MARK: - Collapse Button View

struct CollapseButtonView: View {
    @Binding var isCollapsed: Bool
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4)) {
                isCollapsed.toggle()
            }
        }) {
            ZStack {
                Capsule()
                    .fill(Color.accent.opacity(0.2))
                    .frame(width: 64, height: 6)
                    .shadow(color: Color.accent.opacity(0.4), radius: 6)
                
                Image(systemName: isCollapsed ? "chevron.compact.up" : "chevron.compact.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.accent)
                    .offset(y: isCollapsed ? -12 : 12)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentSectionView(
        selectedTab: .constant(.playlist),
        isInAlbumDetail: .constant(false),
        isPlaylistCollapsed: .constant(false),
        playerViewModel: PlayerViewModel(),
        collectionManager: CollectionManager(),
        onExportPlaylist: {},
        onClearPlaylist: {},
        onClearCollections: {},
        onOpenFilePicker: {},
        onPlaylistDrop: { _ in }
    )
    .padding()
    .background(Color.black)
}
