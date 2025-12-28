//
//  PlayerViewModel.swift
//  Me2Tune
//
//  播放器视图模型 - 状态管理 + 业务逻辑
//

import AppKit
import Combine
import Foundation
import OSLog

private let logger = Logger(subsystem: "me2.Me2Tune", category: "PlayerViewModel")

@MainActor
final class PlayerViewModel: ObservableObject {
    // MARK: - Published States
    
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentArtwork: NSImage?
    @Published private(set) var playlist: [AudioTrack] = []
    @Published private(set) var currentTracks: [AudioTrack] = []
    @Published private(set) var currentTrackIndex: Int?
    @Published private(set) var playingSource: PlayingSource = .playlist
    @Published private(set) var isPlaylistLoaded = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.7
    
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
    
    private let playerCore: AudioPlayerCore
    private let persistenceService = PersistenceService()
    private var cancellables = Set<AnyCancellable>()
    
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
    
    init() {
        self.playerCore = AudioPlayerCore()
        self.playerCore.delegate = self
        
        Task {
            await loadPlaylist()
        }
        
        setupBindings()
        logger.debug("PlayerViewModel initialized")
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        $repeatMode
            .sink { [weak playerCore] newValue in
                playerCore?.repeatMode = AudioPlayerCore.RepeatMode(from: newValue)
            }
            .store(in: &cancellables)
        
        $volume
            .sink { [weak playerCore] newValue in
                playerCore?.volume = newValue
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Playback Control
    
    func play() {
        if currentTrack == nil, !playlist.isEmpty {
            playingSource = .playlist
            currentTracks = playlist
            loadAndPlay(at: 0)
            return
        }
        
        guard currentTrack != nil else {
            logger.warning("No track loaded, cannot play")
            return
        }
        
        playerCore.play()
    }
    
    func pause() {
        playerCore.pause()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func previous() {
        guard let currentIndex = currentTrackIndex, currentIndex > 0 else {
            return
        }
        
        let newIndex = currentIndex - 1
        loadAndPlay(at: newIndex)
    }
    
    func next() {
        guard let currentIndex = currentTrackIndex,
              currentIndex < currentTracks.count - 1
        else {
            return
        }
        
        let newIndex = currentIndex + 1
        loadAndPlay(at: newIndex)
    }
    
    func seek(to time: TimeInterval) {
        playerCore.seek(to: time)
    }
    
    func toggleRepeatMode() {
        switch repeatMode {
        case .off:
            repeatMode = .all
        case .all:
            repeatMode = .one
        case .one:
            repeatMode = .off
        }
        logger.debug("Repeat mode: \(String(describing: self.repeatMode))")
    }
    
    // MARK: - Playlist Management
    
    func addTracks(urls: [URL]) {
        let supportedExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ape", "wv", "tta", "mpc"]
        
        let validURLs = urls.filter { url in
            supportedExtensions.contains(url.pathExtension.lowercased())
        }
        
        logger.info("Adding \(validURLs.count) tracks to playlist")
        
        Task {
            let newTracks = await withTaskGroup(of: AudioTrack.self) { group in
                for url in validURLs {
                    group.addTask {
                        await AudioTrack(url: url)
                    }
                }
                
                var tracks: [AudioTrack] = []
                for await track in group {
                    tracks.append(track)
                }
                return tracks
            }
            
            playlist.append(contentsOf: newTracks)
            
            if !isPlaylistLoaded {
                isPlaylistLoaded = true
            }
                
            if playingSource == .playlist {
                currentTracks = playlist
            }
            
            if currentTrackIndex == nil, !currentTracks.isEmpty {
                currentTrackIndex = 0
                await loadTrack(at: 0)
            }
            
            await savePlaylist()
        }
    }
    
    func removeTrack(at index: Int) {
        guard playlist.indices.contains(index) else { return }
        
        if playingSource == .playlist, let currentIndex = currentTrackIndex {
            if index == currentIndex {
                pause()
                currentTrackIndex = nil
                logger.info("Removed currently playing track")
            } else if index < currentIndex {
                currentTrackIndex = currentIndex - 1
            }
        }
        
        playlist.remove(at: index)
        
        if playingSource == .playlist {
            currentTracks = playlist
        }
        
        Task {
            await savePlaylist()
        }
    }
    
    func clearPlaylist() {
        if playingSource == .playlist {
            pause()
            currentTrackIndex = nil
        }
        
        let count = playlist.count
        playlist.removeAll()
        
        if playingSource == .playlist {
            currentTracks = []
        }
        
        logger.info("Cleared playlist with \(count) tracks")
        
        Task {
            await savePlaylist()
        }
    }
    
    func moveTrack(from source: Int, to destination: Int) {
        guard playlist.indices.contains(source),
              playlist.indices.contains(destination),
              source != destination
        else {
            return
        }
        
        let movedTrack = playlist.remove(at: source)
        playlist.insert(movedTrack, at: destination)
        
        if playingSource == .playlist, let currentIndex = currentTrackIndex {
            if source == currentIndex {
                currentTrackIndex = destination
            } else if source < currentIndex, destination >= currentIndex {
                currentTrackIndex = currentIndex - 1
            } else if source > currentIndex, destination <= currentIndex {
                currentTrackIndex = currentIndex + 1
            }
        }
        
        if playingSource == .playlist {
            currentTracks = playlist
        }
        
        logger.debug("Moved track from \(source) to \(destination)")
        
        Task {
            await savePlaylist()
        }
    }
    
    func playTrack(at index: Int) {
        guard playlist.indices.contains(index) else { return }
        
        playingSource = .playlist
        currentTracks = playlist
        
        loadAndPlay(at: index)
    }
    
    func playAlbum(_ album: Album, startAt index: Int = 0) {
        guard !album.tracks.isEmpty else { return }
        
        playingSource = .album(album.id)
        currentTracks = album.tracks
        
        logger.info("Playing album: \(album.name)")
        
        loadAndPlay(at: index)
    }
    
    // MARK: - Track Loading
    
    private func loadTrack(at index: Int) async {
        guard currentTracks.indices.contains(index) else { return }
        
        let track = currentTracks[index]
        currentTrackIndex = index
        
        await playerCore.loadTrack(track)
    }
    
    private func loadAndPlay(at index: Int) {
        Task {
            await loadTrack(at: index)
            playerCore.play()
            await savePlaylist()
        }
    }
    
    // MARK: - Persistence
    
    private func savePlaylist() async {
        let sourceData: PlaylistState.PlayingSourceData? = {
            switch playingSource {
            case .playlist:
                return .playlist
            case .album(let id):
                return .album(id)
            }
        }()
        
        let state = PlaylistState(
            tracks: playlist,
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
            try await persistenceService.save(state)
            logger.debug("Playlist saved with playing source: \(String(describing: sourceData))")
        } catch {
            logger.error("Failed to save playlist: \(error.localizedDescription)")
        }
    }
    
    func restoreAlbumPlayback(albums: [Album]) async {
        guard let state = try? await persistenceService.load() else { return }
        
        if let source = state.playingSource,
           case .album(let albumId) = source,
           let albumIndex = state.albumCurrentIndex
        {
            if let album = albums.first(where: { $0.id == albumId }),
               album.tracks.indices.contains(albumIndex)
            {
                playingSource = .album(albumId)
                currentTracks = album.tracks
                currentTrackIndex = albumIndex
                await loadTrack(at: albumIndex)
                logger.info("Restored album playback: \(album.name), track \(albumIndex)")
            } else {
                logger.warning("Album or track not found, resetting to playlist")
            }
        }
    }
    
    private func loadPlaylist() async {
        guard let state = try? await persistenceService.load() else {
            logger.notice("No existing playlist to load")
            return
        }
        
        playlist = state.tracks
        
        if let source = state.playingSource {
            switch source {
            case .playlist:
                playingSource = .playlist
                currentTracks = playlist
                
                if let savedIndex = state.playlistCurrentIndex,
                   playlist.indices.contains(savedIndex)
                {
                    currentTrackIndex = savedIndex
                    await loadTrack(at: savedIndex)
                    logger.info("Restored playlist at track \(savedIndex)")
                }
                
            case .album:
                playingSource = .playlist
                currentTracks = playlist
                currentTrackIndex = nil
                logger.info("Waiting for albums to restore album playback")
            }
        } else {
            playingSource = .playlist
            currentTracks = playlist
            currentTrackIndex = nil
        }
        
        logger.info("Loaded playlist with \(state.tracks.count) tracks")
        isPlaylistLoaded = true
    }
}

// MARK: - AudioPlayerCore Delegate

extension PlayerViewModel: AudioPlayerCoreDelegate {
    nonisolated func playerCore(_ core: AudioPlayerCore, didUpdatePlaybackState isPlaying: Bool) {
        Task { @MainActor in
            self.isPlaying = isPlaying
        }
    }
    
    nonisolated func playerCore(_ core: AudioPlayerCore, didUpdateTime currentTime: TimeInterval, duration: TimeInterval) {
        Task { @MainActor in
            self.currentTime = currentTime
            self.duration = duration
        }
    }
    
    nonisolated func playerCore(_ core: AudioPlayerCore, didLoadTrack track: AudioTrack, artwork: NSImage?) {
        Task { @MainActor in
            self.currentArtwork = artwork
        }
    }
    
    nonisolated func playerCore(_ core: AudioPlayerCore, didEncounterError error: Error) {
        Task { @MainActor in
            logger.error("Player core error: \(error.localizedDescription)")
        }
    }
    
    nonisolated func playerCoreDidReachEnd(_ core: AudioPlayerCore) {
        Task { @MainActor in
            switch repeatMode {
            case .one:
                if let index = currentTrackIndex {
                    loadAndPlay(at: index)
                }
            case .all:
                if let currentIndex = currentTrackIndex {
                    if currentIndex < currentTracks.count - 1 {
                        next()
                    } else {
                        loadAndPlay(at: 0)
                    }
                }
            case .off:
                if let currentIndex = currentTrackIndex,
                   currentIndex < currentTracks.count - 1
                {
                    next()
                }
            }
        }
    }
}

// MARK: - RepeatMode Conversion

private extension AudioPlayerCore.RepeatMode {
    init(from viewModelMode: PlayerViewModel.RepeatMode) {
        switch viewModelMode {
        case .off:
            self = .off
        case .all:
            self = .all
        case .one:
            self = .one
        }
    }
}
