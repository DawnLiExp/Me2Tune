//
//  LegacyPlaybackStateImporter.swift
//  Me2Tune
//
//  旧版 SDPlaybackState 导入 - 一次性转换为会话快照
//

import Foundation
import OSLog

private let logger = Logger.persistence

@MainActor
struct LegacyPlaybackStateImporter {
    private let dataService: DataServiceProtocol

    init(dataService: DataServiceProtocol) {
        self.dataService = dataService
    }

    func importIfNeeded(
        playlistManager: PlaylistManager,
        collectionManager: CollectionManager?
    ) async -> PlaybackSessionSnapshot? {
        guard let sdState = dataService.fetchPlaybackStateIfExists(),
              let sourceType = sdState.playingSourceType
        else {
            return nil
        }

        switch sourceType {
        case SDPlaybackState.sourcePlaylist:
            guard let savedIndex = sdState.playlistCurrentIndex,
                  playlistManager.tracks.indices.contains(savedIndex)
            else {
                return nil
            }

            let trackID = playlistManager.tracks[savedIndex].id
            logger.info("📋 Legacy import: playlist index \(savedIndex) -> trackID \(trackID)")
            return PlaybackSessionSnapshot(
                sourceKind: .playlist,
                currentTrackID: trackID,
                albumID: nil,
                volume: sdState.volume ?? 0.7
            )

        case SDPlaybackState.sourceAlbum:
            guard let albumIndex = sdState.albumCurrentIndex,
                  let albumIdentifier = sdState.playingSourceAlbumURLString,
                  let albumID = findAlbumUUID(byIdentifier: albumIdentifier),
                  let album = await collectionManager?.loadSingleAlbum(id: albumID),
                  album.tracks.indices.contains(albumIndex)
            else {
                return nil
            }

            let trackID = album.tracks[albumIndex].id
            logger.info("💿 Legacy import: album \(album.name) index \(albumIndex) -> trackID \(trackID)")
            return PlaybackSessionSnapshot(
                sourceKind: .album,
                currentTrackID: trackID,
                albumID: albumID,
                volume: sdState.volume ?? 0.7
            )

        default:
            return nil
        }
    }

    private func findAlbumUUID(byIdentifier identifier: String) -> UUID? {
        if let sdAlbum = dataService.findAlbum(byFolderURL: identifier) {
            return sdAlbum.stableId
        }

        if let sdAlbums = try? dataService.fetchAlbums() {
            for sdAlbum in sdAlbums where sdAlbum.name == identifier {
                return sdAlbum.stableId
            }
        }

        return nil
    }
}
