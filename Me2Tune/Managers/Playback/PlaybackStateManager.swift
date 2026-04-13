//
//  PlaybackStateManager.swift
//  Me2Tune
//
//  播放状态管理 - 播放源切换 + 会话快照持久化 + 索引派生
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

    private let sessionStore: PlaybackSessionStore
    private weak var playlistManager: PlaylistManager?
    private weak var collectionManager: CollectionManager?
    private var currentAlbumSnapshot: Album?
    private var lastSavedSnapshot: PlaybackSessionSnapshot?

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
        dataService _: DataServiceProtocol = DataService.shared,
        sessionStore: PlaybackSessionStore = PlaybackSessionStore()
    ) {
        self.playlistManager = playlistManager
        self.collectionManager = collectionManager
        self.sessionStore = sessionStore

        logger.debug("✅ PlaybackStateManager initialized")
    }

    // MARK: - Playback Source Switching

    func switchToPlaylist(selecting index: Int? = nil) {
        playingSource = .playlist
        currentAlbumSnapshot = nil
        setCurrentIndex(index)

        logger.debug("Switched to playlist source")
    }

    func switchToAlbum(_ album: Album, selecting index: Int? = nil) {
        playingSource = .album(album.id)
        currentAlbumSnapshot = album
        setCurrentIndex(index)

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

    func saveState(volume: Double) {
        let snapshot = switch playingSource {
        case .playlist:
            PlaybackSessionSnapshot(
                sourceKind: .playlist,
                currentTrackID: currentTrackID,
                albumID: nil,
                volume: volume
            )
        case .album(let albumID):
            PlaybackSessionSnapshot(
                sourceKind: .album,
                currentTrackID: currentTrackID,
                albumID: albumID,
                volume: volume
            )
        }

        guard snapshot != lastSavedSnapshot else { return }
        lastSavedSnapshot = snapshot
        sessionStore.save(snapshot)
    }

    func restoreState() async -> RestoredState? {
        if let snapshot = sessionStore.load() {
            let restored = await restore(from: snapshot)
            if restored != nil {
                lastSavedSnapshot = snapshot
            }
            return restored
        }
        logger.notice("No saved playback state found")
        return nil
    }

    // MARK: - Private Helpers

    private func fallbackToPlaylist() {
        playingSource = .playlist
        currentAlbumSnapshot = nil
        currentTrackID = nil
    }

    private func restore(from snapshot: PlaybackSessionSnapshot) async -> RestoredState? {
        switch snapshot.sourceKind {
        case .playlist:
            guard let playlistManager else { return nil }

            playingSource = .playlist
            currentAlbumSnapshot = nil
            currentTrackID = nil

            if let trackID = snapshot.currentTrackID,
               let restoredTrack = playlistManager.tracks.first(where: { $0.id == trackID }),
               let restoredIndex = playlistManager.tracks.firstIndex(where: { $0.id == trackID })
            {
                currentTrackID = trackID
                logger.info("📋 Restored playlist track: \(restoredTrack.title)")
                return RestoredState(
                    source: .playlist,
                    trackIndex: restoredIndex,
                    track: restoredTrack,
                    volume: snapshot.volume
                )
            }
            return nil

        case .album:
            guard let albumID = snapshot.albumID,
                  let album = await collectionManager?.loadSingleAlbum(id: albumID)
            else {
                fallbackToPlaylist()
                return nil
            }

            playingSource = .album(albumID)
            currentAlbumSnapshot = album
            currentTrackID = nil

            if let trackID = snapshot.currentTrackID,
               let restoredTrack = album.tracks.first(where: { $0.id == trackID }),
               let restoredIndex = album.tracks.firstIndex(where: { $0.id == trackID })
            {
                currentTrackID = trackID
                collectionManager?.populateWithSingleAlbum(album)
                logger.info("💿 Restored album track: \(restoredTrack.title)")
                return RestoredState(
                    source: .album(albumID),
                    trackIndex: restoredIndex,
                    track: restoredTrack,
                    volume: snapshot.volume
                )
            }

            fallbackToPlaylist()
            return nil
        }
    }

    // MARK: - Types

    struct RestoredState {
        let source: PlayingSource
        let trackIndex: Int
        let track: AudioTrack
        let volume: Double?
    }
}
