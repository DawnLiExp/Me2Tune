//
//  AlbumCardView.swift
//  Me2Tune
//
//  专辑卡片组件
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AlbumCardView: View, Equatable {
    nonisolated static func == (lhs: AlbumCardView, rhs: AlbumCardView) -> Bool {
        lhs.album.id == rhs.album.id
            && lhs.album.name == rhs.album.name
            && lhs.album.tracks.count == rhs.album.tracks.count
            && lhs.isDragging == rhs.isDragging
    }
    
    let album: Album
    let isDragging: Bool
    let onTap: (NSImage?) -> Void
    let onRename: () -> Void
    let onRemove: () -> Void
    
    @State private var artwork: NSImage?
    @State private var isHovered = false
    @AppStorage("CleanMode") private var cleanMode = false
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            contentView
            
            if !cleanMode {
                HoverDetectingView(isHovered: $isHovered)
                    .allowsHitTesting(false)
            }
        }
        .onTapGesture {
            onTap(artwork)
        }
        .contextMenu {
            Button("rename") {
                onRename()
            }
            
            Divider()
            
            Button("remove", role: .destructive) {
                onRemove()
            }
        }
        .task(id: album.id) {
            await loadArtwork()
        }
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        VStack(spacing: 8) {
            artworkView
            
            VStack(spacing: 2) {
                Text(album.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                
                Text("\(album.tracks.count) tracks")
                    .font(.system(size: 11))
                    .foregroundColor(.secondaryText)
            }
        }
        .opacity(isDragging ? 0.4 : 1.0)
        .scaleEffect((isHovered && !isDragging && !cleanMode) ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isDragging)
    }
    
    // MARK: - Artwork View
    
    private var artworkView: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        Image(systemName: "opticaldisc")
                            .font(.system(size: 40))
                            .foregroundColor(.emptyStateIcon)
                    )
            }
        }
        .frame(width: 135, height: 135)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    Color.accent.opacity((isHovered && !isDragging && !cleanMode) ? 0.4 : 0),
                    lineWidth: 2
                )
        )
        .shadow(
            color: (isHovered && !isDragging && !cleanMode) ? Color.accent.opacity(0.2) : .clear,
            radius: 8
        )
    }
    
    // MARK: - Artwork Loading
    
    private func loadArtwork() async {
        guard artwork == nil, let firstTrack = album.tracks.first else { return }
        artwork = await ArtworkCacheService.shared.artwork(for: firstTrack.url)
    }
}
