//
//  ContentView.swift
//  Me2Tune
//
//  主界面：可收拢唱片、播放控制、双栏播放列表
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var collectionManager: CollectionManager
    @State private var isDragging = false
    @State private var selectedTab: PlaylistTab = .playlist
    @State private var isArtworkExpanded = true
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Album Artwork
            
            AlbumArtworkView(
                artwork: playerManager.currentArtwork,
                isPlaying: playerManager.isPlaying,
                currentTrack: playerManager.currentTrack,
                isExpanded: $isArtworkExpanded,
            )
            
            Divider()
            
            // MARK: - Player Controls
            
            PlayerControlsView(
                currentTrack: playerManager.currentTrack,
                currentTime: playerManager.currentTime,
                duration: playerManager.duration,
                isPlaying: playerManager.isPlaying,
                canGoPrevious: (playerManager.currentTrackIndex ?? 0) > 0,
                canGoNext: (playerManager.currentTrackIndex ?? 0) < playerManager.currentTracks.count - 1,
                onPlayPause: { playerManager.togglePlayPause() },
                onPrevious: { playerManager.previous() },
                onNext: { playerManager.next() },
                onSeek: { playerManager.seek(to: $0) },
            )
            .background(Color(white: 0.15))
            
            Divider()
            
            // MARK: - Playlist
            
            PlaylistView(
                tracks: playerManager.playlist,
                currentTracks: playerManager.currentTracks,
                currentIndex: playerManager.currentTrackIndex,
                playingSource: playerManager.playingSource,
                albums: collectionManager.albums,
                selectedTab: $selectedTab,
                onTrackSelected: { playerManager.playTrack(at: $0) },
                onAlbumSelected: { album, index in
                    playerManager.playAlbum(album, startAt: index)
                },
                onTrackRemoved: { playerManager.removeTrack(at: $0) },
                onPlaylistCleared: { playerManager.clearPlaylist() },
                onAlbumRemoved: { collectionManager.removeAlbum(id: $0) },
                onAlbumRenamed: { collectionManager.renameAlbum(id: $0, newName: $1) },
                onCollectionCleared: { collectionManager.clearAllAlbums() },
            )
            .background(Color(white: 0.12))
            .frame(maxHeight: .infinity)
        }
        .background(Color(white: 0.1))
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
    }
    
    // MARK: - Helpers
    
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
    ContentView()
        .environmentObject(AudioPlayerManager())
        .environmentObject(CollectionManager())
}
