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
    @Binding var selectedAlbumId: UUID?
    
    let playerViewModel: PlayerViewModel
    let collectionManager: CollectionManager
    
    let onExportPlaylist: () -> Void
    let onClearPlaylist: () -> Void
    let onClearCollections: () -> Void
    let onOpenFilePicker: () -> Void
    let onPlaylistDrop: ([URL]) -> Void
    
    var body: some View {
        NonDraggableView {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    TabSwitcherView(
                        selectedTab: $selectedTab,
                        isInAlbumDetail: isInAlbumDetail,
                        playlistEmpty: playerViewModel.playlistManager.isEmpty,
                        collectionsEmpty: collectionManager.albums.isEmpty,
                        onExportPlaylist: onExportPlaylist,
                        onClearPlaylist: onClearPlaylist,
                        onClearCollections: onClearCollections,
                        onOpenFilePicker: onOpenFilePicker
                    )
                    .padding(.top, 12)
                    .padding(.horizontal, 12)
                    
                    contentView
                        .frame(maxHeight: .infinity)
                }
                .frame(minHeight: 405)
                .background(containerBackground)
                
                CollapseButtonView(isCollapsed: $isPlaylistCollapsed)
                    .offset(y: 8)
            }
            .allowsHitTesting(true)
        }
    }

    // MARK: - Content View
    
    @ViewBuilder
    private var contentView: some View {
        // 一次性提取所有需要的状态,减少对 PlayerViewModel 的访问次数
        @Bindable var viewModel = playerViewModel
        
        // 提前提取状态到局部变量
        // 注意: 这些值在 body 执行期间是不变的,避免重复读取触发 Observation
        let playlistTracks = viewModel.playlistManager.tracks
        let currentIndex = viewModel.currentTrackIndex
        let playingSource = viewModel.playingSource
        let isLoadingTracks = viewModel.playlistManager.isLoading
        let loadingTracksCount = viewModel.playlistManager.loadingCount
        let collectionsAlbums = collectionManager.albums
        let collectionsLoaded = collectionManager.isLoaded
        
        ZStack {
            CollectionsGridView(
                selectedTab: $selectedTab,
                isInAlbumDetail: $isInAlbumDetail,
                selectedAlbumId: $selectedAlbumId,
                albums: collectionsAlbums,
                isLoaded: collectionsLoaded,
                isActiveTab: selectedTab == .collections, // 传递当前是否激活的状态
                currentIndex: currentIndex,
                playingSource: playingSource,
                onAlbumPlayAt: { album, index in
                    viewModel.playAlbum(album, startAt: index)
                },
                onAlbumRemoved: { albumId in
                    collectionManager.removeAlbum(id: albumId)
                },
                onAlbumRenamed: { albumId, newName in
                    collectionManager.renameAlbum(id: albumId, newName: newName)
                },
                onAlbumMoved: { from, to in
                    collectionManager.moveAlbum(from: from, to: to)
                },
                onTrackAddedToPlaylist: { track in
                    viewModel.addTracksToPlaylist(urls: [track.url])
                },
                onEnsureLoaded: {
                    await collectionManager.ensureLoaded()
                }
            )
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .opacity(selectedTab == .collections ? 1 : 0)
            .allowsHitTesting(selectedTab == .collections)
            
            // PlaylistTabView 只有在选中时才挂载，避免影响其他拖拽
            if selectedTab == .playlist {
                PlaylistTabView(
                    selectedTab: $selectedTab,
                    tracks: playlistTracks,
                    currentIndex: currentIndex,
                    playingSource: playingSource,
                    isLoadingTracks: isLoadingTracks,
                    loadingTracksCount: loadingTracksCount,
                    onTrackSelected: { index in
                        // 闭包内部直接调用,减少嵌套
                        viewModel.playPlaylistTrack(at: index)
                    },
                    onTrackRemoved: { index in
                        viewModel.removeTrackFromPlaylist(at: index)
                    },
                    onTrackMoved: { from, to in
                        if let sourceIndex = from.first {
                            viewModel.moveTrackInPlaylist(from: sourceIndex, to: to)
                        }
                    },
                    onFilesDrop: onPlaylistDrop
                )
                .padding(.horizontal, 12)
                .padding(.top, 16)
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
            } else {
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
            ToolbarButtonView(
                icon: "arrow.right.circle",
                tooltip: String(localized: "export_to_collection"),
                isEnabled: !playlistEmpty,
                action: onExportPlaylist
            )
            
            ToolbarButtonView(
                icon: "plus.circle",
                tooltip: String(localized: "add_files"),
                action: onOpenFilePicker
            )
            
            ToolbarButtonView(
                icon: "xmark.circle",
                tooltip: String(localized: "clear_playlist"),
                isEnabled: !playlistEmpty,
                action: onClearPlaylist
            )
        }
    }
    
    private var collectionsToolbar: some View {
        HStack(spacing: 8) {
            ToolbarButtonView(
                icon: "plus.circle",
                tooltip: String(localized: "add_album"),
                action: onOpenFilePicker
            )
            
            ToolbarButtonView(
                icon: "xmark.circle",
                tooltip: String(localized: "clear_collections"),
                isEnabled: !collectionsEmpty,
                action: onClearCollections
            )
        }
    }
}

#Preview {
    ContentSectionView(
        selectedTab: .constant(.playlist),
        isInAlbumDetail: .constant(false),
        isPlaylistCollapsed: .constant(false),
        selectedAlbumId: .constant(nil),
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
