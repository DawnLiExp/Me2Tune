//
//  ContentView.swift
//  Me2Tune
//
//  主界面：可收拢唱片、播放控制、双栏播放列表、Mini模式 + UI状态记忆
//

import Combine
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "me2.Me2Tune", category: "ContentView")

struct ContentView: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var collectionManager: CollectionManager
    @State private var isDragging = false
    @State private var selectedTab: PlaylistTab = .playlist
    @State private var isArtworkExpanded: Bool
    @State private var isPlaylistVisible: Bool
    @State private var isLoadingUIState = false
    @State private var lastSavedHeight: CGFloat = 0
    @State private var lastSavedX: CGFloat = 0
    @State private var lastSavedY: CGFloat = 0
    @State private var heightBeforeHidingPlaylist: CGFloat?
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool
    
    private let persistenceService = PersistenceService()
    
    init(initialUIState: UIState) {
        _isArtworkExpanded = State(initialValue: initialUIState.isArtworkExpanded)
        _isPlaylistVisible = State(initialValue: initialUIState.isPlaylistVisible)
        _lastSavedHeight = State(initialValue: initialUIState.windowHeight)
        _lastSavedX = State(initialValue: initialUIState.windowX ?? 0)
        _lastSavedY = State(initialValue: initialUIState.windowY ?? 0)
    }
    
    private var minContentHeight: CGFloat {
        var height: CGFloat = 0
        height += isArtworkExpanded ? 350 : 64
        height += 1
        height += 112
        
        if isPlaylistVisible {
            height += 1
            height += 300
        }
        
        return height
    }
    
    var body: some View {
        VStack(spacing: 0) {
            AlbumArtworkView(
                artwork: playerManager.currentArtwork,
                isPlaying: playerManager.isPlaying,
                currentTrack: playerManager.currentTrack,
                isExpanded: $isArtworkExpanded,
            )
            
            Divider()
            
            PlayerControlsView(
                currentTrack: playerManager.currentTrack,
                currentTime: playerManager.currentTime,
                duration: playerManager.duration,
                isPlaying: playerManager.isPlaying,
                canGoPrevious: (playerManager.currentTrackIndex ?? 0) > 0,
                canGoNext: (playerManager.currentTrackIndex ?? 0) < playerManager.currentTracks.count - 1,
                repeatMode: playerManager.repeatMode,
                volume: playerManager.volume,
                onPlayPause: { playerManager.togglePlayPause() },
                onPrevious: { playerManager.previous() },
                onNext: { playerManager.next() },
                onSeek: { playerManager.seek(to: $0) },
                onToggleMiniMode: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isPlaylistVisible.toggle()
                    }
                },
                onToggleRepeat: { playerManager.toggleRepeatMode() },
                onVolumeChange: { playerManager.volume = $0 },
            )
            .background(Color(white: 0.15))
            
            if isPlaylistVisible {
                Divider()
                
                PlaylistView(
                    tracks: playerManager.playlist,
                    currentTracks: playerManager.currentTracks,
                    currentIndex: playerManager.currentTrackIndex,
                    playingSource: playerManager.playingSource,
                    albums: collectionManager.albums,
                    isPlaylistLoaded: playerManager.isPlaylistLoaded,
                    selectedTab: $selectedTab,
                    onTrackSelected: { playerManager.playTrack(at: $0) },
                    onAlbumSelected: { album, index in
                        playerManager.playAlbum(album, startAt: index)
                    },
                    onTrackRemoved: { playerManager.removeTrack(at: $0) },
                    onTrackMoved: { from, to in
                        playerManager.moveTrack(from: from, to: to)
                    },
                    onPlaylistCleared: { playerManager.clearPlaylist() },
                    onAlbumRemoved: { collectionManager.removeAlbum(id: $0) },
                    onAlbumRenamed: { collectionManager.renameAlbum(id: $0, newName: $1) },
                    onCollectionCleared: { collectionManager.clearAllAlbums() },
                    onFilesDropped: { urls in
                        if selectedTab == .playlist {
                            handlePlaylistDrop(urls)
                        } else {
                            handleCollectionsDrop(urls)
                        }
                    },
                )
                .background(Color(white: 0.12))
                .frame(minHeight: 300, maxHeight: .infinity)
            }
        }
        .background(Color(white: 0.1))
        .frame(width: 350)
        .onChange(of: isPlaylistVisible) { _, _ in
            updateWindowSizeForPlaylistToggle()
            if !isLoadingUIState {
                saveTask?.cancel()
                Task { await saveUIState() }
            }
        }
        .onChange(of: isArtworkExpanded) { _, _ in
            updateWindowSizeForArtworkToggle()
            if !isLoadingUIState {
                saveTask?.cancel()
                Task { await saveUIState() }
            }
        }
        .preferredColorScheme(.dark)
        .focusable()
        .focused($isFocused)
        .onAppear {
            isFocused = true
        }
        .onKeyPress(.space) {
            playerManager.togglePlayPause()
            return .handled
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { _ in
            handleWindowChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { _ in
            handleWindowChange()
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            await collectionManager.ensureLoaded()
            await playerManager.restoreAlbumPlayback(albums: collectionManager.albums)
        }
        .onDisappear {
            saveTask?.cancel()
        }
    }
    
    // MARK: - UI State Management
    
    private func handleWindowChange() {
        guard !isLoadingUIState else { return }
        guard let window = NSApp.windows.first else { return }
        
        let currentHeight = window.frame.height
        let currentX = window.frame.origin.x
        let currentY = window.frame.origin.y
        
        let heightChanged = abs(currentHeight - lastSavedHeight) > 5
        let positionChanged = abs(currentX - lastSavedX) > 5 || abs(currentY - lastSavedY) > 5
        
        guard heightChanged || positionChanged else { return }
        
        lastSavedHeight = currentHeight
        lastSavedX = currentX
        lastSavedY = currentY
        
        saveTask?.cancel()
        
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await saveUIState()
        }
    }
    
    private func saveUIState() async {
        guard let window = NSApp.windows.first else { return }
        
        let state = UIState(
            isArtworkExpanded: isArtworkExpanded,
            isPlaylistVisible: isPlaylistVisible,
            windowHeight: window.frame.height,
            windowX: window.frame.origin.x,
            windowY: window.frame.origin.y,
        )
        
        do {
            try await persistenceService.save(state)
        } catch {
            logger.error("Failed to save UI state: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helpers
    
    private func updateWindowSizeForArtworkToggle() {
        guard let window = NSApp.windows.first else { return }
        
        let currentFrame = window.frame
        let heightDelta: CGFloat = isArtworkExpanded ? 286 : -286
        let newHeight = currentFrame.height + heightDelta
        
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y + currentFrame.height - newHeight,
            width: 350,
            height: newHeight,
        )
        window.setFrame(newFrame, display: true, animate: true)
    }
    
    private func updateWindowSizeForPlaylistToggle() {
        guard let window = NSApp.windows.first else { return }
        
        let currentFrame = window.frame
        let newHeight: CGFloat
        
        if isPlaylistVisible {
            if let savedHeight = heightBeforeHidingPlaylist {
                newHeight = savedHeight
                heightBeforeHidingPlaylist = nil
            } else {
                newHeight = minContentHeight
            }
        } else {
            heightBeforeHidingPlaylist = currentFrame.height
            newHeight = minContentHeight
        }
        
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y + currentFrame.height - newHeight,
            width: 350,
            height: newHeight,
        )
        window.setFrame(newFrame, display: true, animate: true)
    }
    
    private func updateWindowSize() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApp.windows.first {
                let currentFrame = window.frame
                let targetHeight = minContentHeight
                let newFrame = NSRect(
                    x: currentFrame.origin.x,
                    y: currentFrame.origin.y + currentFrame.height - targetHeight,
                    width: 350,
                    height: targetHeight,
                )
                window.setFrame(newFrame, display: true, animate: true)
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
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
                    options: [.skipsHiddenFiles],
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
    ContentView(initialUIState: .default)
        .environmentObject(AudioPlayerManager())
        .environmentObject(CollectionManager())
}
