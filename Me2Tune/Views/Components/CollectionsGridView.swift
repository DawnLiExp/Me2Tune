//
//  CollectionsGridView.swift
//  Me2Tune
//
//  专辑网格视图：专辑卡片展示
//

import SwiftUI

struct CollectionsGridView: View {
    @Binding var selectedTab: PlaylistTab
    let albums: [Album]
    let isLoaded: Bool
    let onAlbumSelected: (Album) -> Void
    let onEnsureLoaded: () async -> Void
    
    var body: some View {
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
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
        .task {
            await onEnsureLoaded()
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
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
                .frame(height: 140)
                .overlay(
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.5))
                )
            
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
            onAlbumSelected(album)
        }
    }
}

#Preview {
    CollectionsGridView(
        selectedTab: .constant(.collections),
        albums: [],
        isLoaded: true,
        onAlbumSelected: { _ in },
        onEnsureLoaded: {}
    )
    .padding()
    .background(Color.black)
}
