//
//  ContentView.swift
//  Me2Tune
//
//  主界面：拟真唱片动画、播放控制、双栏播放列表
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var playerManager = AudioPlayerManager()
    @State private var isDragging = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Album Artwork
            
            AlbumArtworkView(
                artwork: playerManager.currentArtwork,
                isPlaying: playerManager.isPlaying,
            )
            
            Divider()
            
            // MARK: - Player Controls
            
            PlayerControlsView(
                currentTrack: playerManager.currentTrack,
                currentTime: playerManager.currentTime,
                duration: playerManager.duration,
                isPlaying: playerManager.isPlaying,
                canGoPrevious: (playerManager.currentTrackIndex ?? 0) > 0,
                canGoNext: playerManager.currentTrackIndex ?? 0 < playerManager.playlist.count - 1,
                onPlayPause: { playerManager.togglePlayPause() },
                onPrevious: { playerManager.previous() },
                onNext: { playerManager.next() },
                onSeek: { playerManager.seek(to: $0) },
            )
            .background(Color(white: 0.15))
            
            Divider()
            
            // MARK: - Playlist
            
            ZStack {
                PlaylistView(
                    tracks: playerManager.playlist,
                    currentIndex: playerManager.currentTrackIndex,
                    onTrackSelected: { playerManager.playTrack(at: $0) },
                )
                .background(Color(white: 0.12))
                
                if playerManager.playlist.isEmpty {
                    dropZoneOverlay
                }
            }
            .frame(minHeight: 200)
        }
        .frame(minWidth: 400, minHeight: 600)
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
    
    // MARK: - Drop Zone Overlay
    
    private var dropZoneOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text(LocalizedStringKey("drop_files"))
                .font(.headline)
                .foregroundStyle(.primary)
            
            Text(LocalizedStringKey("supported_formats"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDragging ? Color.orange.opacity(0.15) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDragging ? Color.orange : Color.gray.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [10]),
                )
                .padding(20),
        )
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
            playerManager.addTracks(urls: urls)
        }
        
        return true
    }
}

#Preview {
    ContentView()
}
