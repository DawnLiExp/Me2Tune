//
//  ContentView.swift
//  Me2Tune
//
//  主界面视图 - 支持播放列表拖拽排序
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var collectionManager: CollectionManager
    
    @State private var albumGlowColor = Color(hex: "#FF4466")
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
    
    // 赛博朋克配色预设
    private let glowColors: [Color] = [
        Color(hex: "#FF006E"), // 霓虹粉
        Color(hex: "#9D4EDD"), // 霓虹紫
        Color(hex: "#C77DFF"), // 淡紫
        Color(hex: "#3A86FF"), // 霓虹蓝
        Color(hex: "#FF6D00"), // 霓虹橙
        Color(hex: "#FFBA08"), // 霓虹黄
        Color(hex: "#FF4466"), // 霓虹红
        Color(hex: "#06FFA5"), // 霓虹绿
    ]
    
    private var canGoPrevious: Bool {
        guard let index = playerManager.currentTrackIndex else { return false }
        return index > 0
    }
    
    private var canGoNext: Bool {
        guard let index = playerManager.currentTrackIndex else { return false }
        return index < playerManager.currentTracks.count - 1
    }
    
    var body: some View {
        ZStack {
            backgroundLayers
            
            VStack(spacing: 0) {
                topBar
                    .frame(height: 70)
                    .padding(.horizontal, 12)
                
                Spacer()
                    .frame(height: 18)
                
                VinylCoverView(
                    artwork: playerManager.currentArtwork,
                    isPlaying: playerManager.isPlaying,
                    isRotationEnabled: isRotationEnabled,
                    currentTime: playerManager.currentTime,
                    duration: playerManager.duration
                )
                .frame(height: 160)
                .padding(.horizontal, 12)
                
                PlaybackControlView(
                    currentTrack: playerManager.currentTrack,
                    currentTime: playerManager.currentTime,
                    duration: playerManager.duration,
                    isPlaying: playerManager.isPlaying,
                    canGoPrevious: canGoPrevious,
                    canGoNext: canGoNext,
                    onPlayPause: { playerManager.togglePlayPause() },
                    onPrevious: { playerManager.previous() },
                    onNext: { playerManager.next() },
                    onSeek: { playerManager.seek(to: $0) }
                )
                .fixedSize(horizontal: false, vertical: true)

                contentSection
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
            }
        }
        .frame(width: 495)
        .frame(minHeight: 775, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
        }
        .alert("export_playlist_title", isPresented: $showExportDialog) {
            TextField("album_name", text: $exportAlbumName)
            Button("cancel", role: .cancel) {
                showExportDialog = false
            }
            Button("export") {
                if !exportAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Task {
                        await exportPlaylistToAlbum(name: exportAlbumName)
                    }
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
                playerManager.clearPlaylist()
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
                collectionManager.clearAllAlbums()
                showClearCollectionsConfirm = false
            }
        } message: {
            Text("clear_collections_confirm")
        }
        .onChange(of: playerManager.currentTrack?.id) { _, newID in
            guard let newID, newID != previousTrackID else { return }
            previousTrackID = newID
            
            withAnimation(.easeInOut(duration: 1.2)) {
                albumGlowColor = glowColors.randomElement() ?? Color(hex: "#FF4466")
            }
        }
    }
    
    // MARK: - Background Layers
    
    private var backgroundLayers: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.02), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            vinylGlowLayer
            playlistGlowLayer
        }
    }
    
    private var vinylGlowLayer: some View {
        VStack {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                albumGlowColor.opacity(0.6),
                                albumGlowColor.opacity(0.35),
                                albumGlowColor.opacity(0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 60,
                            endRadius: 280
                        )
                    )
                    .frame(width: 400, height: 400)
                    .blur(radius: 40)
                
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                albumGlowColor.opacity(0.25),
                                albumGlowColor.opacity(0.1),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 460, height: 280)
                    .blur(radius: 35)
                    .offset(y: 80)
            }
            .offset(y: 0)
            
            Spacer()
        }
        .allowsHitTesting(false)
    }
    
    private var playlistGlowLayer: some View {
        VStack {
            Spacer()
            
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "#00E5FF").opacity(0.25),
                            Color(hex: "#00E5FF").opacity(0.12),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 80,
                        endRadius: 320
                    )
                )
                .frame(width: 460, height: 180)
                .blur(radius: 35)
                .padding(.bottom, 40)
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .foregroundColor(.gray)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Me2Tune")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Text("AAC | 264 kbps | 16 bit | 44.1 kHz | Stereo")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.08))
            )
            
            Spacer()
            
            rotationToggleButton
                .offset(y: -18)
                .padding(.trailing, 12)
        }
        .frame(height: 50)
    }
    
    private var rotationToggleButton: some View {
        Button(action: {
            isRotationEnabled.toggle()
        }) {
            Circle()
                .fill(isRotationEnabled ? Color(hex: "#00E5FF").opacity(0.9) : Color.white.opacity(0.15))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "record.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isRotationEnabled ? .black : .gray)
                )
                .shadow(color: isRotationEnabled ? Color(hex: "#00E5FF").opacity(0.6) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Content Section
    
    private var contentSection: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                tabSwitcher
                    .padding(.top, 12)
                    .padding(.horizontal, 12)
                
                if selectedTab == .playlist {
                    playlistContent
                } else {
                    collectionsContent
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(hex: "#00E5FF").opacity(0.3),
                                        Color(hex: "#00E5FF").opacity(0.0)
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                ),
                                lineWidth: 1.5
                            )
                    )
            )
            
            collapseButton
                .offset(y: 8)
        }
        .allowsHitTesting(true)
    }
    
    // MARK: - Playlist Content
    
    private var playlistContent: some View {
        PlaylistTabView(
            selectedTab: $selectedTab,
            tracks: playerManager.playlist,
            currentIndex: playerManager.currentTrackIndex,
            playingSource: playerManager.playingSource,
            onTrackSelected: { playerManager.playTrack(at: $0) },
            onTrackRemoved: { playerManager.removeTrack(at: $0) },
            onTrackMoved: { from, to in
                if let sourceIndex = from.first {
                    playerManager.moveTrack(from: sourceIndex, to: to)
                }
            }
        )
        .padding(.horizontal, 12)
        .padding(.top, 16)
    }
    
    // MARK: - Collections Content
    
    private var collectionsContent: some View {
        ScrollView(showsIndicators: false) {
            CollectionsGridView(
                selectedTab: $selectedTab,
                isInAlbumDetail: $isInAlbumDetail,
                albums: collectionManager.albums,
                isLoaded: collectionManager.isLoaded,
                currentIndex: playerManager.currentTrackIndex,
                playingSource: playerManager.playingSource,
                onAlbumPlayAt: { album, index in
                    playerManager.playAlbum(album, startAt: index)
                },
                onAlbumRemoved: { albumId in
                    collectionManager.removeAlbum(id: albumId)
                },
                onAlbumRenamed: { albumId, newName in
                    collectionManager.renameAlbum(id: albumId, newName: newName)
                },
                onTrackAddedToPlaylist: { track in
                    playerManager.addTracks(urls: [track.url])
                },
                onEnsureLoaded: {
                    await collectionManager.ensureLoaded()
                }
            )
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
    }
    
    // MARK: - Tab Switcher
    
    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            tabButton(title: String(localized: "playlist"), tab: .playlist)
            tabButton(title: String(localized: "collections"), tab: .collections)
            
            Spacer()
            
            if selectedTab == .playlist {
                playlistToolbarButtons
            } else {
                collectionsToolbarButtons
            }
        }
    }
    
    // MARK: - Toolbar Buttons
    
    private var playlistToolbarButtons: some View {
        HStack(spacing: 8) {
            ToolbarIconButton(
                icon: "arrow.right.circle",
                tooltip: String(localized: "export_to_collection"),
                isEnabled: !playerManager.playlist.isEmpty
            ) {
                exportPlaylistDialog()
            }
            
            ToolbarIconButton(
                icon: "plus.circle",
                tooltip: String(localized: "add_files")
            ) {
                openFilePicker()
            }
            
            ToolbarIconButton(
                icon: "xmark.circle",
                tooltip: String(localized: "clear_playlist"),
                isEnabled: !playerManager.playlist.isEmpty
            ) {
                showClearPlaylistConfirm = true
            }
        }
    }
    
    @ViewBuilder
    private var collectionsToolbarButtons: some View {
        if !isInAlbumDetail {
            HStack(spacing: 8) {
                ToolbarIconButton(
                    icon: "plus.circle",
                    tooltip: String(localized: "add_album")
                ) {
                    openFilePicker()
                }
                
                ToolbarIconButton(
                    icon: "xmark.circle",
                    tooltip: String(localized: "clear_collections"),
                    isEnabled: !collectionManager.albums.isEmpty
                ) {
                    showClearCollectionsConfirm = true
                }
            }
        }
    }
    
    private func exportPlaylistDialog() {
        exportAlbumName = generateDefaultAlbumName()
        showExportDialog = true
    }
    
    private func generateDefaultAlbumName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "\(String(localized: "playlist")) \(formatter.string(from: Date()))"
    }
    
    private func tabButton(title: String, tab: PlaylistTab) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedTab = tab
            }
        }) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.5))
                
                if selectedTab == tab {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#00E5FF"),
                                    Color(hex: "#00E5FF").opacity(0.7)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 2)
                        .shadow(color: Color(hex: "#00E5FF").opacity(0.5), radius: 4)
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
    
    private var collapseButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4)) {
                isPlaylistCollapsed.toggle()
            }
        }) {
            ZStack {
                Capsule()
                    .fill(Color(hex: "#00E5FF").opacity(0.2))
                    .frame(width: 64, height: 6)
                    .shadow(color: Color(hex: "#00E5FF").opacity(0.4), radius: 6)
                
                Image(systemName: isPlaylistCollapsed ? "chevron.compact.up" : "chevron.compact.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "#00E5FF"))
                    .offset(y: isPlaylistCollapsed ? -12 : 12)
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Toolbar Actions
    
    private func exportPlaylistToAlbum(name: String) async {
        guard !playerManager.playlist.isEmpty else { return }
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        if let _ = await collectionManager.addAlbumFromPlaylist(
            name: trimmedName,
            tracks: playerManager.playlist
        ) {
            await MainActor.run {
                selectedTab = .collections
            }
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
        var urls: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                continue
            }
            
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                defer { group.leave() }
                if let url {
                    urls.append(url)
                }
            }
        }
        
        group.notify(queue: .main) {
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
        playerManager.addTracks(urls: allURLs)
    }
    
    private func handleCollectionsDrop(_ urls: [URL]) {
        let fileManager = FileManager.default
        
        Task {
            for url in urls {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                    continue
                }
                
                if isDirectory.boolValue {
                    await collectionManager.addAlbum(from: url)
                }
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
                    for case let fileURL as URL in enumerator {
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

#Preview {
    ContentView()
        .environmentObject(AudioPlayerManager())
        .environmentObject(CollectionManager())
}
