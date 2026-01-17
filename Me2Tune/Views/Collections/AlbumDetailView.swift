//
//  AlbumDetailView.swift
//  Me2Tune
//
//  专辑详情视图 - 头部 + 歌曲列表
//

import AppKit
import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    let artwork: NSImage?
    let playingSource: PlayerViewModel.PlayingSource
    let currentIndex: Int?
    
    let onBack: () -> Void
    let onTrackTap: (Int) -> Void
    let onShowInFinder: (AudioTrack) -> Void
    let onAddToPlaylist: (AudioTrack) -> Void
    
    var body: some View {
        VStack(spacing: 5) {
            albumHeader
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                        AlbumTrackRowView(
                            track: track,
                            index: index,
                            isPlaying: {
                                if case .album(let id) = playingSource {
                                    return id == album.id && currentIndex == index
                                }
                                return false
                            }(),
                            onTap: { onTrackTap(index) },
                            onShowInFinder: { onShowInFinder(track) },
                            onAddToPlaylist: { onAddToPlaylist(track) }
                        )
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }
    
    // MARK: - Album Header
    
    private var albumHeader: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.accent)
            }
            .buttonStyle(.plain)
            
            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Image(systemName: "opticaldisc")
                                .font(.system(size: 24))
                                .foregroundColor(.emptyStateIcon)
                        )
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primaryText)
                    .lineLimit(2)
                
                Text("\(album.tracks.count) tracks")
                    .font(.system(size: 12))
                    .foregroundColor(.secondaryText)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.selectedBackground)
        )
    }
}
