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
    @EnvironmentObject private var playerViewModel: PlayerViewModel
    @EnvironmentObject private var collectionManager: CollectionManager
    @EnvironmentObject private var windowStateMonitor: WindowStateMonitor
    
    @State private var albumGlowColor = Color.defaultAlbumGlow
    @State private var previousTrackID: UUID?
    @State private var isDragging = false
    @State private var selectedTab: PlaylistTab = .playlist
    @State private var isPlaylistCollapsed = false
    @State private var isRotationEnabled = true
    @State private var isInAlbumDetail = false
    
    @State private var showExportDialog = false
    @State private var exportAlbumName = ""
    @State private var showClearPlaylistConfirm = false
    @State private var showClearCollectionsConfirm = false
    
    var body: some View {
        mainView
            .frame(width: 495)
            .frame(minHeight: 800, maxHeight: .infinity)
            .preferredColorScheme(.dark)
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                handleDrop(providers: providers)
            }
            .onChange(of: windowStateMonitor.isWindowVisible) { _, isVisible in
                playerViewModel.updateWindowVisibility(isVisible)
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
    
    // MARK: - Main View
    
    private var mainView: some View {
        ZStack {
            BackgroundLayerView(albumGlowColor: albumGlowColor)
            
            mainContentStack
        }
    }
    
    private var mainContentStack: some View {
        VStack(spacing: 0) {
            TopBarSectionView(
                isRotationEnabled: $isRotationEnabled,
                audioFormat: playerViewModel.currentFormat
            )
            .frame(height: 70)
            .padding(.horizontal, 12)
            
            Spacer()
                .frame(height: 18)
            
            VinylSectionView(
                artwork: playerViewModel.currentArtwork,
                isPlaying: playerViewModel.isPlaying,
                isRotationEnabled: isRotationEnabled,
                currentTime: playerViewModel.currentTime,
                duration: playerViewModel.duration,
                isWindowVisible: windowStateMonitor.isWindowVisible
            )
            .frame(height: 160)
            .padding(.horizontal, 12)
            
            ControlSectionView(
                currentTrack: playerViewModel.currentTrack,
                currentTime: playerViewModel.currentTime,
                duration: playerViewModel.duration,
                isPlaying: playerViewModel.isPlaying,
                canGoPrevious: playerViewModel.canGoPrevious,
                canGoNext: playerViewModel.canGoNext,
                onPlayPause: playerViewModel.togglePlayPause,
                onPrevious: playerViewModel.previous,
                onNext: playerViewModel.next,
                onSeek: playerViewModel.seek
            )
            .fixedSize(horizontal: false, vertical: true)

            ContentSectionView(
                selectedTab: $selectedTab,
                isInAlbumDetail: $isInAlbumDetail,
                isPlaylistCollapsed: $isPlaylistCollapsed,
                playerViewModel: playerViewModel,
                collectionManager: collectionManager,
                onExportPlaylist: handleExportPlaylist,
                onClearPlaylist: { showClearPlaylistConfirm = true },
                onClearCollections: { showClearCollectionsConfirm = true },
                onOpenFilePicker: openFilePicker,
                onPlaylistDrop: handlePlaylistDrop
            )
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 20)
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
        guard !playerViewModel.playlist.isEmpty else { return }
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        Task {
            if let _ = await collectionManager.addAlbumFromPlaylist(
                name: trimmedName,
                tracks: playerViewModel.playlist
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
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio, .folder]
        panel.message = String(localized: "select_files_or_folders")
        
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            
            DispatchQueue.main.async {
                if selectedTab == .playlist {
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
        playerViewModel.addTracks(urls: allURLs)
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

#Preview {
    ContentView()
        .environmentObject(PlayerViewModel())
        .environmentObject(CollectionManager())
}
