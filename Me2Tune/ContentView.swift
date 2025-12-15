//
//  ContentView.swift
//  Me2Tune
//
//  主界面：拖拽区域、播放列表、播放控制
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var playerManager = AudioPlayerManager()
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Drop Zone

            dropZone
            
            Divider()
            
            // MARK: - Playlist

            playlistView
            
            Divider()
            
            // MARK: - Player Controls

            playerControls
        }
        .frame(minWidth: 400, minHeight: 300)
    }
    
    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("拖入音频文件")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Text("支持 MP3、AAC、WAV、AIFF、FLAC、APE")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(isDragging ? Color.accentColor.opacity(0.1) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDragging ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8]),
                )
                .padding(12),
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
        }
    }
    
    // MARK: - Playlist View

    private var playlistView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(playerManager.playlist.enumerated()), id: \.element.id) { index, track in
                    HStack {
                        Text(track.title)
                            .lineLimit(1)
                            .foregroundStyle(
                                playerManager.currentTrackIndex == index ? .primary : .secondary,
                            )
                        
                        Spacer()
                        
                        Text(formatTime(track.duration))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        playerManager.currentTrackIndex == index ?
                            Color.accentColor.opacity(0.1) : Color.clear,
                    )
                    
                    if index < playerManager.playlist.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - Player Controls

    private var playerControls: some View {
        VStack(spacing: 12) {
            if let currentTrack = playerManager.currentTrack {
                Text(currentTrack.title)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                
                HStack(spacing: 8) {
                    Text(formatTime(playerManager.currentTime))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    
                    Slider(
                        value: Binding(
                            get: { playerManager.currentTime },
                            set: { playerManager.seek(to: $0) },
                        ),
                        in: 0 ... max(playerManager.duration, 0.1),
                    )
                    
                    Text(formatTime(playerManager.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            
            HStack(spacing: 24) {
                Button(action: { playerManager.previous() }) {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .disabled(playerManager.currentTrackIndex ?? 0 == 0)
                
                Button(action: { playerManager.togglePlayPause() }) {
                    Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                .disabled(playerManager.playlist.isEmpty)
                
                Button(action: { playerManager.next() }) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .disabled(
                    playerManager.currentTrackIndex == nil ||
                        playerManager.currentTrackIndex == playerManager.playlist.count - 1,
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
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
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, !time.isNaN else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    ContentView()
}
