//
//  PlaybackStateManager.swift
//  Me2Tune
//
//  播放状态管理 - 播放源切换 + SwiftData 持久化 + 索引计算
//

import Foundation
import Observation
import OSLog

private let logger = Logger.viewModel

@MainActor
@Observable
final class PlaybackStateManager {
    // MARK: - Published States

    private(set) var currentTracks: [AudioTrack] = []
    private(set) var currentTrackIndex: Int?
    private(set) var playingSource: PlayingSource = .playlist

    // MARK: - Types

    enum PlayingSource: Equatable {
        case playlist
        case album(UUID)
    }

    enum RepeatMode {
        case off
        case all
        case one
    }

    // MARK: - Private Properties

    private let dataService = DataService.shared
    private weak var playlistManager: PlaylistManager?
    private weak var collectionManager: CollectionManager?

    private var lastSavedSourceType: String?
    private var lastSavedIndex: Int?
    private var lastSavedVolume: Double?

    // MARK: - Computed Properties

    var currentTrack: AudioTrack? {
        guard let index = currentTrackIndex, currentTracks.indices.contains(index) else {
            return nil
        }
        return currentTracks[index]
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

    init(playlistManager: PlaylistManager, collectionManager: CollectionManager?) {
        self.playlistManager = playlistManager
        self.collectionManager = collectionManager

        logger.debug("✅ PlaybackStateManager initialized (SwiftData)")
    }

    // MARK: - Playback Source Switching

    func switchToPlaylist() {
        guard let playlistManager else { return }

        playingSource = .playlist
        currentTracks = playlistManager.tracks

        logger.debug("Switched to playlist source")
    }

    func switchToAlbum(_ album: Album) {
        playingSource = .album(album.id)
        currentTracks = album.tracks

        logger.info("💿 Switched to album: \(album.name) (\(album.tracks.count) tracks)")
    }

    // MARK: - Index Management

    func setCurrentIndex(_ index: Int?) {
        currentTrackIndex = index
    }

    func moveToNextIndex() -> Int? {
        guard let currentIndex = currentTrackIndex,
              currentIndex < currentTracks.count - 1
        else {
            return nil
        }

        let nextIndex = currentIndex + 1
        currentTrackIndex = nextIndex
        return nextIndex
    }

    func moveToPreviousIndex() -> Int? {
        guard let currentIndex = currentTrackIndex, currentIndex > 0 else {
            return nil
        }

        let previousIndex = currentIndex - 1
        currentTrackIndex = previousIndex
        return previousIndex
    }

    /// Calculate next index without mutating current index.
    func calculateNextIndex(at index: Int, repeatMode: RepeatMode) -> Int? {
        switch repeatMode {
        case .one:
            return index
        case .all:
            if index < currentTracks.count - 1 {
                return index + 1
            } else {
                return 0
            }
        case .off:
            if index < currentTracks.count - 1 {
                return index + 1
            } else {
                return nil
            }
        }
    }

    /// Compatibility method using current index.
    func calculateNextIndex(repeatMode: RepeatMode) -> Int? {
        guard let currentIndex = currentTrackIndex else { return nil }
        return calculateNextIndex(at: currentIndex, repeatMode: repeatMode)
    }

    // MARK: - Playlist Updates Handling

    func handlePlaylistTrackRemoved(at index: Int, wasPlaying: Bool) {
        guard playingSource == .playlist else {
            return
        }

        if let currentIndex = currentTrackIndex {
            if index == currentIndex {
                currentTrackIndex = nil
            } else if index < currentIndex {
                currentTrackIndex = currentIndex - 1
            }
        }

        if let playlistManager {
            currentTracks = playlistManager.tracks
        }
    }

    func handlePlaylistCleared() {
        if playingSource == .playlist {
            currentTrackIndex = nil
            currentTracks = []
        }
    }

    func handlePlaylistTrackMoved(from source: Int, to destination: Int) {
        guard playingSource == .playlist, let currentIndex = currentTrackIndex else {
            return
        }

        if source == currentIndex {
            currentTrackIndex = destination
        } else if source < currentIndex, destination >= currentIndex {
            currentTrackIndex = currentIndex - 1
        } else if source > currentIndex, destination <= currentIndex {
            currentTrackIndex = currentIndex + 1
        }

        if let playlistManager {
            currentTracks = playlistManager.tracks
        }
    }

    func handlePlaylistTracksAdded() {
        guard let playlistManager else { return }

        if playingSource == .playlist {
            currentTracks = playlistManager.tracks
        }

        if currentTrackIndex == nil, !currentTracks.isEmpty {
            currentTrackIndex = 0
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
            let appError = AppError.persistenceFailed("save playback state")
            logger.logError(appError, context: "savePlaybackState")
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
            currentTracks = playlistManager.tracks
            currentTrackIndex = nil

            if let savedIndex = sdState.playlistCurrentIndex,
               playlistManager.tracks.indices.contains(savedIndex)
            {
                currentTrackIndex = savedIndex

                logger.info("📋 Restored playlist: track \(savedIndex + 1)/\(playlistManager.count)")

                return RestoredState(
                    source: .playlist,
                    trackIndex: savedIndex,
                    track: playlistManager.tracks[savedIndex],
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
            currentTracks = album.tracks
            currentTrackIndex = albumIndex

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
        if let playlistManager {
            playingSource = .playlist
            currentTracks = playlistManager.tracks
            currentTrackIndex = nil
        }
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
