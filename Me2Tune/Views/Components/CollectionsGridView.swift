//
//  CollectionsGridView.swift
//  Me2Tune
//
//  专辑网格视图：专辑卡片展示+详情视图
//

import AppKit
import SwiftUI

struct CollectionsGridView: View {
    @Binding var selectedTab: PlaylistTab
    let albums: [Album]
    let isLoaded: Bool
    let currentIndex: Int?
    let playingSource: AudioPlayerManager.PlayingSource
    let onAlbumPlayAt: (Album, Int) -> Void
    let onEnsureLoaded: () async -> Void
    
    @State private var selectedAlbum: Album?
    @State private var artworkCache: [UUID: NSImage] = [:]
    
    private let artworkService = ArtworkService()
    
    var body: some View {
        Group {
            if let album = selectedAlbum {
                albumDetailView(album: album)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                albumGridView
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .task {
            await onEnsureLoaded()
        }
    }
    
    // MARK: - Album Grid View
    
    private var albumGridView: some View {
        Group {
            if albums.isEmpty {
                if isLoaded {
                    emptyStateView
                } else {
                    ProgressView()
                        .padding(40)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
                ], spacing: 16) {
                    ForEach(albums) { album in
                        albumCard(album: album)
                            .task {
                                await loadArtwork(for: album)
                            }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
    
    // MARK: - Album Detail View
    
    private func albumDetailView(album: Album) -> some View {
        VStack(spacing: 0) {
            albumHeader(album: album)
            
            Divider()
                .padding(.horizontal, 12)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                        albumTrackRow(track: track, index: index, album: album)
                        
                        if index < album.tracks.count - 1 {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
            }
        }
    }
    
    private func albumHeader(album: Album) -> some View {
        HStack(spacing: 16) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedAlbum = nil
                }
            }) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Color(hex: "#00E5FF"))
            }
            .buttonStyle(.plain)
            
            Group {
                if let artwork = artworkCache[album.id] {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Image(systemName: "opticaldisc")
                                .font(.system(size: 24))
                                .foregroundColor(.gray.opacity(0.5))
                        )
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                Text("\(album.tracks.count) tracks")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.03))
    }
    
    private func albumTrackRow(track: AudioTrack, index: Int, album: Album) -> some View {
        let isPlaying: Bool = {
            if case .album(let id) = playingSource {
                return id == album.id && currentIndex == index
            }
            return false
        }()
        
        return HStack(spacing: 12) {
            Group {
                if isPlaying {
                    Image(systemName: "waveform")
                        .foregroundColor(Color(hex: "#00E5FF"))
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 24)
            
            Text(track.title)
                .font(.system(size: 14, weight: isPlaying ? .semibold : .regular))
                .foregroundColor(isPlaying ? .white : .white.opacity(0.8))
                .lineLimit(1)
            
            Spacer()
            
            Text(track.artist ?? "Unknown Artist")
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .trailing)
            
            Text(formatTime(track.duration))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isPlaying ? Color(hex: "#00E5FF").opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onAlbumPlayAt(album, index)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No Collections Yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.gray)
            
            Text("Drag folders here to organize by album")
                .font(.system(size: 12))
                .foregroundColor(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
    
    // MARK: - Album Card
    
    private func albumCard(album: Album) -> some View {
        VStack(spacing: 8) {
            Group {
                if let artwork = artworkCache[album.id] {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Image(systemName: "opticaldisc")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.5))
                        )
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(spacing: 2) {
                Text(album.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("\(album.tracks.count) tracks")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedAlbum = album
            }
        }
    }
    
    // MARK: - Artwork Loading
    
    private func loadArtwork(for album: Album) async {
        guard artworkCache[album.id] == nil,
              let firstTrack = album.tracks.first
        else {
            return
        }
        
        if let artwork = await artworkService.artwork(for: firstTrack.url) {
            await MainActor.run {
                artworkCache[album.id] = artwork
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, !time.isNaN else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    CollectionsGridView(
        selectedTab: .constant(.collections),
        albums: [],
        isLoaded: true,
        currentIndex: nil,
        playingSource: .playlist,
        onAlbumPlayAt: { _, _ in },
        onEnsureLoaded: {}
    )
    .padding()
    .background(Color.black)
}
