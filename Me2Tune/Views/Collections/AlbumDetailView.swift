//
//  AlbumDetailView.swift
//  Me2Tune
//
//  专辑详情视图 - 头部 + 歌曲列表 + 失败标记
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
    
    @Environment(PlayerViewModel.self) private var playerViewModel
    
    // 冷启动兜底：App 恢复时 artwork 为 nil，异步补全
    @State private var resolvedArtwork: NSImage?
    
    @AppStorage("CleanMode") private var cleanMode = false
    
    // MARK: - Body
    
    var body: some View {
        let isCurrentAlbumPlaying: Bool = {
            if case .album(let id) = playingSource {
                return id == album.id
            }
            return false
        }()

        VStack(spacing: 5) {
            albumHeader
            
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(album.tracks.indices, id: \.self) { index in
                        let track = album.tracks[index]
                        AlbumTrackRowView(
                            track: track,
                            index: index,
                            isPlaying: isCurrentAlbumPlaying && currentIndex == index,
                            isFailed: playerViewModel.isTrackFailed(track.id),
                            cleanMode: cleanMode,
                            onTap: { onTrackTap(index) },
                            onShowInFinder: { onShowInFinder(track) },
                            onAddToPlaylist: { onAddToPlaylist(track) }
                        )
                        .equatable()
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .task(id: album.tracks.first?.metadataRevision) {
            resolvedArtwork = nil
            guard let firstTrack = album.tracks.first else { return }
            let result = await ArtworkCacheService.shared.artwork(for: firstTrack.url)
            guard !Task.isCancelled else { return }
            resolvedArtwork = result
        }
    }
    
    // MARK: - Album Header
    
    private var albumHeader: some View {
        // 优先使用同步传入的 artwork，冷启动时退回到异步加载的 resolvedArtwork
        let displayArtwork = resolvedArtwork ?? artwork
        
        return HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.accent)
            }
            .buttonStyle(.plain)
            
            Group {
                if let displayArtwork {
                    Image(nsImage: displayArtwork)
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
                
                Text(trackCountText)
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

    private var trackCountText: String {
        let format = String(localized: "track_count_format")
        return String(format: format, locale: Locale.current, Int64(album.tracks.count))
    }
}
