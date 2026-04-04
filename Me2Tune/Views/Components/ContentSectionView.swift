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

    // IMPORTANT: CollectionsGridView stays permanently mounted so its lazy-load
    // state and artwork cache survive tab switches. Use opacity/offset instead of
    // conditional rendering. PlaylistTabView is conditionally mounted to prevent
    // drag-and-drop interference when hidden.
    @ViewBuilder
    private var contentView: some View {
        @Bindable var viewModel = playerViewModel

        let playlistTracks = viewModel.playlistManager.tracks
        let currentIndex = viewModel.currentTrackIndex
        let playingSource = viewModel.playingSource
        let isLoadingTracks = viewModel.playlistManager.isLoading
        let loadingTracksCount = viewModel.playlistManager.loadingCount
        let collectionsAlbums = collectionManager.albums
        let collectionsLoaded = collectionManager.isLoaded

        // Shared spring — both sides use identical parameters so perceived
        // duration and easing are indistinguishable regardless of direction.
        let tabSpring = Animation.spring(response: 0.28, dampingFraction: 0.78)
        let slideOffset: CGFloat = 60

        ZStack {
            CollectionsGridView(
                selectedTab: $selectedTab,
                isInAlbumDetail: $isInAlbumDetail,
                selectedAlbumId: $selectedAlbumId,
                albums: collectionsAlbums,
                isLoaded: collectionsLoaded,
                isActiveTab: selectedTab == .collections,
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
            .padding(.top, 12)
            .opacity(selectedTab == .collections ? 1 : 0)
            .offset(x: selectedTab == .collections ? 0 : slideOffset)
            .animation(tabSpring, value: selectedTab)
            .allowsHitTesting(selectedTab == .collections)

            if selectedTab == .playlist {
                PlaylistTabView(
                    selectedTab: $selectedTab,
                    tracks: playlistTracks,
                    currentIndex: currentIndex,
                    playingSource: playingSource,
                    isLoadingTracks: isLoadingTracks,
                    loadingTracksCount: loadingTracksCount,
                    onTrackSelected: { index in
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
                .padding(.top, 12)
                // Mirror Collections: slide in from the left, same offset magnitude.
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(x: -slideOffset)),
                        removal: .opacity.combined(with: .offset(x: -slideOffset))
                    )
                )
            }
        }
        .animation(tabSpring, value: selectedTab)
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

    @Namespace private var tabNamespace

    var body: some View {
        HStack(spacing: 0) {
            slidingPillTabs
            Spacer()

            if selectedTab == .playlist {
                playlistToolbar
            } else {
                collectionsToolbar
            }
        }
    }

    // MARK: - Sliding Pill Tabs

    private var slidingPillTabs: some View {
        HStack(spacing: 2) {
            tabPill(title: String(localized: "playlist"), tab: .playlist)
            tabPill(title: String(localized: "collections"), tab: .collections)
        }
        .padding(3)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.05))

                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            }
        }
    }

    private func tabPill(title: String, tab: PlaylistTab) -> some View {
        let isSelected = selectedTab == tab

        return Button(action: {
            // dampingFraction 0.90 — nearly critically damped, minimal overshoot.
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                selectedTab = tab
            }
        }) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(
                    isSelected
                        ? Color.accent.opacity(0.9)
                        : Color.primaryText.opacity(0.38)
                )
                .frame(width: 86, height: 26)
                .contentShape(RoundedRectangle(cornerRadius: 15))
                .background {
                    if isSelected {
                        ZStack {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.accent.opacity(0.20),
                                            Color.accent.opacity(0.06)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            RoundedRectangle(cornerRadius: 15)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.10),
                                            Color.clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )

                            RoundedRectangle(cornerRadius: 15)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.accent.opacity(0.55),
                                            Color.accent.opacity(0.12)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.7
                                )
                        }
                        .shadow(color: Color.accentGlow.opacity(0.40), radius: 7, y: 3)
                        .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
                        .matchedGeometryEffect(id: "tabIndicator", in: tabNamespace)
                    }
                }
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
