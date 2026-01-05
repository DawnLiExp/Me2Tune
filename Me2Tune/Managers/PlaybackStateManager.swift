//
//  PlaybackStateManager.swift
//  Me2Tune
//
//  播放状态管理 - 播放源切换 + 状态持久化
//

import Combine
import Foundation
import OSLog

private let logger = Logger.viewModel

@MainActor
final class PlaybackStateManager: ObservableObject {
    // MARK: - Published States
    
    @Published private(set) var currentTracks: [AudioTrack] = []
    @Published private(set) var currentTrackIndex: Int?
    @Published private(set) var playingSource: PlayingSource = .playlist
    
    // MARK: - Types
    
    enum PlayingSource: Equatable {
        case playlist
        case album(UUID)
    }
    
    // MARK: - Private Properties
    
    private let persistenceService = PersistenceService()
    private weak var playlistManager: PlaylistManager?
    private weak var collectionManager: CollectionManager?
    
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
    
    func calculateNextIndex(repeatMode: RepeatMode) -> Int? {
        guard let currentIndex = currentTrackIndex else { return nil }
        
        switch repeatMode {
        case .one:
            return currentIndex
        case .all:
            if currentIndex < currentTracks.count - 1 {
                return currentIndex + 1
            } else {
                return 0
            }
        case .off:
            if currentIndex < currentTracks.count - 1 {
                return currentIndex + 1
            } else {
                return nil
            }
        }
    }
    
    // MARK: - Playlist Updates Handling
    
    func handlePlaylistTrackRemoved(at index: Int, wasPlaying: Bool) {
        // 仅在播放列表模式下处理
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
        
        // 同步最新的播放列表数据
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
        
        // 如果之前没有曲目,自动设置第一首
        if currentTrackIndex == nil, !currentTracks.isEmpty {
            currentTrackIndex = 0
        }
    }
    
    // MARK: - Persistence
    
    func saveState() {
        let sourceData: PlaybackState.PlayingSourceData? = {
            switch playingSource {
            case .playlist:
                return .playlist
            case .album(let id):
                return .album(id)
            }
        }()
        
        let state = PlaybackState(
            playlistCurrentIndex: playingSource == .playlist ? currentTrackIndex : nil,
            albumCurrentIndex: {
                if case .album = playingSource {
                    return currentTrackIndex
                }
                return nil
            }(),
            playingSource: sourceData
        )
        
        do {
            try persistenceService.savePlaybackState(state)
        } catch {
            let appError = AppError.persistenceFailed("save playback state")
            logger.logError(appError, context: "savePlaybackState")
        }
    }
    
    func restoreState() async -> RestoredState? {
        guard let state = try? persistenceService.loadPlaybackState(),
              let source = state.playingSource
        else {
            logger.notice("No saved playback state found")
            return nil
        }
        
        switch source {
        case .playlist:
            guard let playlistManager else { return nil }
            
            playingSource = .playlist
            currentTracks = playlistManager.tracks
            currentTrackIndex = nil
            
            if let savedIndex = state.playlistCurrentIndex,
               playlistManager.tracks.indices.contains(savedIndex)
            {
                currentTrackIndex = savedIndex
                
                logger.info("📋 Restored playlist: track \(savedIndex + 1)/\(playlistManager.count)")
                
                return RestoredState(
                    source: .playlist,
                    trackIndex: savedIndex,
                    track: playlistManager.tracks[savedIndex]
                )
            }
            
            return nil
            
        case .album(let albumId):
            guard let albumIndex = state.albumCurrentIndex,
                  let album = await collectionManager?.loadSingleAlbum(id: albumId),
                  album.tracks.indices.contains(albumIndex)
            else {
                // 回退到播放列表
                if let playlistManager {
                    playingSource = .playlist
                    currentTracks = playlistManager.tracks
                    currentTrackIndex = nil
                }
                logger.warning("Album or track not found, fallback to playlist")
                return nil
            }
            
            playingSource = .album(albumId)
            currentTracks = album.tracks
            currentTrackIndex = albumIndex
            
            logger.info("💿 Restored album: \(album.name) - track \(albumIndex + 1)")
            
            return RestoredState(
                source: .album(albumId),
                trackIndex: albumIndex,
                track: album.tracks[albumIndex]
            )
        }
    }
    
    // MARK: - Types
    
    enum RepeatMode {
        case off
        case all
        case one
    }
    
    struct RestoredState {
        let source: PlayingSource
        let trackIndex: Int
        let track: AudioTrack
    }
}
