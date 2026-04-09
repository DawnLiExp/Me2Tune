//
//  PlaybackStateManager.swift
//  Me2Tune
//
//  播放状态管理 - 播放源切换 + SwiftData 持久化 + 索引状态
//

import Foundation
import Observation
import OSLog

private let logger = Logger.viewModel

@MainActor
@Observable
final class PlaybackStateManager {
    // MARK: - Published States

    private(set) var currentTrackID: UUID?
    private(set) var playingSource: PlayingSource = .playlist

    // MARK: - Types

    enum PlayingSource: Equatable {
        case playlist
        case album(UUID)
    }

    typealias RepeatMode = Me2Tune.RepeatMode

    // MARK: - Private Properties

    private let dataService: DataServiceProtocol
    private weak var playlistManager: PlaylistManager?
    private weak var collectionManager: CollectionManager?
    private var currentAlbumSnapshot: Album?

    private var lastSavedSourceType: String?
    private var lastSavedIndex: Int?
    private var lastSavedVolume: Double?

    // MARK: - Computed Properties

    var currentTracks: [AudioTrack] {
        switch playingSource {
        case .playlist:
            return playlistManager?.tracks ?? []
        case .album:
            return currentAlbumSnapshot?.tracks ?? []
        }
    }

    var currentTrackIndex: Int? {
        guard let id = currentTrackID else { return nil }
        return currentTracks.firstIndex(where: { $0.id == id })
    }

    var currentTrack: AudioTrack? {
        guard let id = currentTrackID else { return nil }
        return currentTracks.first(where: { $0.id == id })
    }

    var canGoPrevious: Bool {
        guard let index = currentTrackIndex else { return false }
        return index > 0
    }

    var canGoNext: Bool {
        guard let index = currentTrackIndex else { return false }
        return index < currentTracks.count - 1
    }

    // MARK: - Initialization

    init(
        playlistManager: PlaylistManager,
        collectionManager: CollectionManager?,
        dataService: DataServiceProtocol = DataService.shared
    ) {
        self.playlistManager = playlistManager
        self.collectionManager = collectionManager
        self.dataService = dataService

        logger.debug("✅ PlaybackStateManager initialized (SwiftData)")
    }

    // MARK: - Playback Source Switching

    func switchToPlaylist() {
        playingSource = .playlist
        currentAlbumSnapshot = nil

        logger.debug("Switched to playlist source")
    }

    func switchToAlbum(_ album: Album) {
        playingSource = .album(album.id)
        currentAlbumSnapshot = album

        logger.info("💿 Switched to album: \(album.name) (\(album.tracks.count) tracks)")
    }

    // MARK: - Index Management

    func setCurrentTrack(id: UUID?) {
        currentTrackID = id
    }

    func setCurrentIndex(_ index: Int?) {
        guard let index else {
            currentTrackID = nil
            return
        }
        currentTrackID = currentTracks[safe: index]?.id
    }

    // MARK: - Playlist Updates Handling

    func handlePlaylistTrackRemoved(removedTrackID: UUID, wasPlaying _: Bool) {
        guard playingSource == .playlist else {
            return
        }

        if currentTrackID == removedTrackID {
            currentTrackID = nil
        }
    }

    func handlePlaylistCleared() {
        if playingSource == .playlist {
            currentTrackID = nil
        }
    }

    func handlePlaylistTrackMoved(from _: Int, to _: Int) {
        guard playingSource == .playlist else {
            return
        }
    }

    func handlePlaylistTracksAdded() {
        guard playingSource == .playlist else { return }
        if currentTrackID == nil, let first = playlistManager?.tracks.first {
            currentTrackID = first.id
        }
    }

    // MARK: - Persistence

    func saveState(volume: Double? = nil) {
        let sourceType: String
        var albumFolderURL: String?

        switch playingSource {
        case .playlist:
            sourceType = SDPlaybackState.sourcePlaylist
        case .album(let albumId):
            sourceType = SDPlaybackState.sourceAlbum
            // Optimization: query specific album to avoid loading all albums
            albumFolderURL = findAlbumIdentifier(for: albumId)
        }

        let currentIdx = currentTrackIndex

        // Deduplicate: skip if no changes
        if sourceType == lastSavedSourceType,
           currentIdx == lastSavedIndex,
           volume == lastSavedVolume
        {
            return
        }

        let sdState = dataService.getOrCreatePlaybackState()
        sdState.playingSourceType = sourceType
        sdState.playingSourceAlbumURLString = albumFolderURL
        sdState.playlistCurrentIndex = playingSource == .playlist ? currentIdx : nil
        sdState.albumCurrentIndex = {
            if case .album = playingSource { return currentIdx }
            return nil
        }()
        sdState.volume = volume

        do {
            try dataService.save()
            lastSavedSourceType = sourceType
            lastSavedIndex = currentIdx
            lastSavedVolume = volume
        } catch {
            logger.logError(error, context: "savePlaybackState")
        }
    }

    func restoreState() async -> RestoredState? {
        let sdState = dataService.getOrCreatePlaybackState()

        guard let sourceType = sdState.playingSourceType else {
            logger.notice("No saved playback state found")
            return nil
        }

        switch sourceType {
        case SDPlaybackState.sourcePlaylist:
            guard let playlistManager else { return nil }

            playingSource = .playlist
            currentAlbumSnapshot = nil
            currentTrackID = nil

            if let savedIndex = sdState.playlistCurrentIndex,
               playlistManager.tracks.indices.contains(savedIndex)
            {
                let restoredTrack = playlistManager.tracks[savedIndex]
                currentTrackID = restoredTrack.id

                logger.info("📋 Restored playlist: track \(savedIndex + 1)/\(playlistManager.count)")

                return RestoredState(
                    source: .playlist,
                    trackIndex: savedIndex,
                    track: restoredTrack,
                    volume: sdState.volume
                )
            }

            return nil

        case SDPlaybackState.sourceAlbum:
            guard let albumIndex = sdState.albumCurrentIndex,
                  let albumIdentifier = sdState.playingSourceAlbumURLString
            else {
                fallbackToPlaylist()
                return nil
            }

            // Find album UUID by identifier
            guard let albumId = findAlbumUUID(byIdentifier: albumIdentifier),
                  let album = await collectionManager?.loadSingleAlbum(id: albumId),
                  album.tracks.indices.contains(albumIndex)
            else {
                fallbackToPlaylist()
                logger.warning("Album or track not found, fallback to playlist")
                return nil
            }

            playingSource = .album(albumId)
            currentAlbumSnapshot = album
            currentTrackID = album.tracks[albumIndex].id

            collectionManager?.populateWithSingleAlbum(album)

            logger.info("💿 Restored album: \(album.name) - track \(albumIndex + 1)")

            return RestoredState(
                source: .album(albumId),
                trackIndex: albumIndex,
                track: album.tracks[albumIndex],
                volume: sdState.volume
            )

        default:
            logger.warning("Unknown source type: \(sourceType)")
            return nil
        }
    }

    // MARK: - Private Helpers

    private func fallbackToPlaylist() {
        playingSource = .playlist
        currentAlbumSnapshot = nil
        currentTrackID = nil
    }

    /// Optimization: find album identifier (folderURL or name) by UUID.
    private func findAlbumIdentifier(for albumId: UUID) -> String? {
        // Query specific album, avoid loading all to prevent lag
        guard let sdAlbum = dataService.findAlbum(byStableId: albumId) else {
            logger.warning("Album not found for identifier lookup: \(albumId)")
            return nil
        }

        // Access properties directly to avoid toAlbum() triggering data loading
        return sdAlbum.folderURLString ?? sdAlbum.name
    }

    /// Optimization: find album UUID by identifier (folderURL or name).
    private func findAlbumUUID(byIdentifier identifier: String) -> UUID? {
        // Try exact match by folderURLString
        if let sdAlbum = dataService.findAlbum(byFolderURL: identifier) {
            return sdAlbum.stableId
        }

        // Fallback: if folderURL fails, iterate (rare case)
        // Load all albums only if necessary
        do {
            let sdAlbums = try dataService.fetchAlbums()
            for sdAlbum in sdAlbums {
                if sdAlbum.name == identifier {
                    return sdAlbum.stableId
                }
            }
        } catch {
            logger.warning("Failed to find album by identifier")
        }

        return nil
    }

    // MARK: - Types

    struct RestoredState {
        let source: PlayingSource
        let trackIndex: Int
        let track: AudioTrack
        let volume: Double?
    }
}
