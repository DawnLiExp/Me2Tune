//
//  ContentView.swift
//  Me2Tune
//
//  主界面视图 - 组件组合器
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    let isMigrationFailed: Bool

    @Environment(PlayerViewModel.self) private var playerViewModel
    @Environment(CollectionManager.self) private var collectionManager
    @Environment(\.playbackProgressState) private var playbackProgressState
    
    // Mini 模式切换时，跳过 Full 窗口内容渲染，断开 SwiftUI 观察链
    @AppStorage("displayMode") private var displayMode = DisplayMode.full.rawValue
    
    @State private var albumGlowColor = Color.defaultAlbumGlow
    @State private var previousTrackID: UUID?
    @State private var isDragging = false
    @State private var selectedTab: PlaylistTab = .playlist
    @State private var isPlaylistCollapsed = false
    @State private var isRotationEnabled = true
    @State private var isInAlbumDetail = false
    @State private var selectedAlbumId: UUID?
    @State private var showSearchOverlay = false
    
    @State private var showExportDialog = false
    @State private var exportAlbumName = ""
    @State private var showClearPlaylistConfirm = false
    @State private var showClearCollectionsConfirm = false
    
    // Full 窗口是否处于激活状态（非 Mini 模式）
    private var isFullModeActive: Bool {
        displayMode == DisplayMode.full.rawValue
    }
    
    var body: some View {
        if isMigrationFailed {
            MigrationFailedView()
        } else {
            mainView
                .frame(minHeight: 800, maxHeight: .infinity)
                .preferredColorScheme(.dark)
                .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                    handleDrop(providers: providers)
                }
                .modifier(AlertsModifier(
                    showExportDialog: $showExportDialog,
                    exportAlbumName: $exportAlbumName,
                    showClearPlaylistConfirm: $showClearPlaylistConfirm,
                    showClearCollectionsConfirm: $showClearCollectionsConfirm,
                    onExport: exportPlaylistToAlbum,
                    onClearPlaylist: playerViewModel.clearPlaylist,
                    onClearCollections: collectionManager.clearAllAlbums
                ))
                .onChange(of: playerViewModel.currentTrack?.id) { _, newID in
                    updateAlbumGlow(newID: newID)
                }
        }
    }
    
    // MARK: - Main View
    
    private var mainView: some View {
        ZStack {
            // Mini 模式时跳过所有内容渲染：
            //    - 断开 playbackProgressState 观察链，消除 Full 窗口隐藏后的空跑 re-render
            //    - 销毁 RotatingVinylLayer CALayer，停止 GPU 旋转动画
            //    - 停止 MeshGradient 呼吸循环（task 随视图销毁取消）
            if isFullModeActive {
                BackgroundLayerView(albumGlowColor: albumGlowColor)
                    .ignoresSafeArea(.all)
                mainContentStack
                    
                if showSearchOverlay {
                    searchOverlay
                        .transition(.opacity)
                        .zIndex(100)
                }
            }
        }
    }
    
    // 提前提取状态到局部变量，减少对 playerViewModel 的直接访问
    private var mainContentStack: some View {
        @Bindable var viewModel = playerViewModel
        
        // 提前提取所有需要的状态，避免在子视图构建时重复触发 Observation
        let currentTrack = viewModel.currentTrack
        let currentArtwork = viewModel.currentArtwork
        let currentFormat = viewModel.currentFormat
        let isPlaying = viewModel.isPlaying
        let duration = viewModel.duration
        let canGoPrevious = viewModel.canGoPrevious
        let canGoNext = viewModel.canGoNext
        let repeatMode = viewModel.repeatMode
        let isRestoring = viewModel.isRestoring
        
        return VStack(spacing: 0) {
            TopBarSectionView(
                isRotationEnabled: $isRotationEnabled,
                audioFormat: currentFormat,
                onSearchTapped: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSearchOverlay = true
                    }
                }
            )
            .frame(height: 70)
            .padding(.horizontal, 12)
            
            Spacer()
                .frame(height: 18)
            
            VinylSectionView(
                artwork: currentArtwork,
                isPlaying: isPlaying,
                isRotationEnabled: isRotationEnabled,
                duration: duration,
                isWindowVisible: isFullModeActive,
                isRestoring: isRestoring
            )
            .frame(height: 160)
            .padding(.horizontal, 12)
            
            ControlSectionView(
                currentTrack: currentTrack,
                duration: duration,
                isPlaying: isPlaying,
                canGoPrevious: canGoPrevious,
                canGoNext: canGoNext,
                repeatMode: repeatMode,
                isRestoring: isRestoring,
                onPlayPause: viewModel.togglePlayPause,
                onPrevious: viewModel.previous,
                onNext: viewModel.next,
                onSeek: viewModel.seek,
                onToggleRepeat: viewModel.toggleRepeatMode,
                volume: $viewModel.volume
            )
            .fixedSize(horizontal: false, vertical: true)

            ContentSectionView(
                selectedTab: $selectedTab,
                isInAlbumDetail: $isInAlbumDetail,
                isPlaylistCollapsed: $isPlaylistCollapsed,
                selectedAlbumId: $selectedAlbumId,
                playerViewModel: playerViewModel,
                collectionManager: collectionManager,
                onExportPlaylist: handleExportPlaylist,
                onClearPlaylist: { showClearPlaylistConfirm = true },
                onClearCollections: { showClearCollectionsConfirm = true },
                onOpenFilePicker: openFilePicker,
                onPlaylistDrop: handlePlaylistDrop
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Search

    private var searchOverlay: some View {
        SearchOverlayView(
            isPresented: $showSearchOverlay,
            searchData: SearchOverlayView.SearchData(
                playlist: playerViewModel.playlistManager.tracks,
                albums: collectionManager.albums
            ),
            onResultSelected: handleSearchResult
        )
    }

    private func handleSearchResult(_ result: SearchOverlayView.SearchResult) {
        switch result.action {
        case .playPlaylistTrack(let index):
            playerViewModel.playPlaylistTrack(at: index)
            
        case .playAlbumTrack(let album, let trackIndex):
            playerViewModel.playAlbum(album, startAt: trackIndex)
            
        case .openAlbum(let album):
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedTab = .collections
            }
            
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                await MainActor.run {
                    selectedAlbumId = album.id
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleExportPlaylist() {
        exportAlbumName = generateDefaultAlbumName()
        showExportDialog = true
    }
    
    private func generateDefaultAlbumName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "\(String(localized: "playlist")) \(formatter.string(from: Date()))"
    }
    
    private func exportPlaylistToAlbum(name: String) {
        guard !playerViewModel.playlistManager.isEmpty else { return }
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        Task {
            if let _ = await collectionManager.addAlbumFromPlaylist(
                name: trimmedName,
                tracks: playerViewModel.playlistManager.tracks
            ) {
                selectedTab = .collections
            }
        }
    }
    
    private func updateAlbumGlow(newID: UUID?) {
        guard let newID, newID != previousTrackID else { return }
        previousTrackID = newID
        
        withAnimation(.easeInOut(duration: 1.2)) {
            albumGlowColor = Color.albumGlowColors.randomElement() ?? .defaultAlbumGlow
        }
    }
    
    private func openFilePicker() {
        let targetTab = selectedTab
        
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio, .folder]
        panel.message = String(localized: "select_files_or_folders")
        
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            
            Task { @MainActor in
                if targetTab == .playlist {
                    handlePlaylistDrop(urls)
                } else {
                    handleCollectionsDrop(urls)
                }
            }
        }
    }
    
    // MARK: - Drag & Drop
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        Task { @MainActor in
            var urls: [URL] = []
            
            for provider in providers {
                guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                    continue
                }
                
                do {
                    let item = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
                    
                    if let url = item as? URL {
                        urls.append(url)
                    } else if let data = item as? Data,
                              let string = String(data: data, encoding: .utf8)
                    {
                        if let url = URL(string: string) {
                            urls.append(url)
                        } else {
                            let url = URL(fileURLWithPath: string)
                            urls.append(url)
                        }
                    } else if let string = item as? String {
                        if let url = URL(string: string) {
                            urls.append(url)
                        } else {
                            let url = URL(fileURLWithPath: string)
                            urls.append(url)
                        }
                    }
                } catch {
                    continue
                }
            }
            
            if selectedTab == .playlist {
                handlePlaylistDrop(urls)
            } else {
                handleCollectionsDrop(urls)
            }
        }
        
        return true
    }
    
    private func handlePlaylistDrop(_ urls: [URL]) {
        let allURLs = expandFolders(urls)
        Task { @MainActor in
            await playerViewModel.addTracksToPlaylist(urls: allURLs)
        }
    }
    
    private func handleCollectionsDrop(_ urls: [URL]) {
        Task {
            for url in urls {
                await collectionManager.addAlbum(from: url)
            }
        }
    }
    
    private func expandFolders(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        let fileManager = FileManager.default
        let supportedExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ape", "wv", "tta", "mpc"]
        
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }
            
            if isDirectory.boolValue {
                if let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                            result.append(fileURL)
                        }
                    }
                }
            } else {
                if supportedExtensions.contains(url.pathExtension.lowercased()) {
                    result.append(url)
                }
            }
        }
        
        return result
    }
}

// MARK: - Migration Failed View

private struct MigrationFailedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("migration_failed_title")
                .font(.title2.bold())

            Text("migration_failed_body")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.callout)

            Button("migration_open_settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 800)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Alerts Modifier

struct AlertsModifier: ViewModifier {
    @Binding var showExportDialog: Bool
    @Binding var exportAlbumName: String
    @Binding var showClearPlaylistConfirm: Bool
    @Binding var showClearCollectionsConfirm: Bool
    
    let onExport: (String) -> Void
    let onClearPlaylist: () -> Void
    let onClearCollections: () -> Void
    
    func body(content: Content) -> some View {
        content
            .alert("export_playlist_title", isPresented: $showExportDialog) {
                TextField("album_name", text: $exportAlbumName)
                Button("cancel", role: .cancel) {
                    showExportDialog = false
                }
                Button("export") {
                    if !exportAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onExport(exportAlbumName)
                    }
                    showExportDialog = false
                }
                .disabled(exportAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("export_playlist_message")
            }
            .alert("clear_playlist", isPresented: $showClearPlaylistConfirm) {
                Button("cancel", role: .cancel) {
                    showClearPlaylistConfirm = false
                }
                Button("clear", role: .destructive) {
                    onClearPlaylist()
                    showClearPlaylistConfirm = false
                }
            } message: {
                Text("clear_playlist_confirm")
            }
            .alert("clear_collections", isPresented: $showClearCollectionsConfirm) {
                Button("cancel", role: .cancel) {
                    showClearCollectionsConfirm = false
                }
                Button("clear", role: .destructive) {
                    onClearCollections()
                    showClearCollectionsConfirm = false
                }
            } message: {
                Text("clear_collections_confirm")
            }
    }
}
