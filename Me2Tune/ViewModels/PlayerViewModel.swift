//
//  PlayerViewModel.swift
//  Me2Tune
//
//  播放器视图模型 - 播放控制 + 状态管理
//

import AppKit
import Combine
import Foundation
import OSLog

private let logger = Logger.viewModel

@MainActor
final class PlayerViewModel: ObservableObject {
    // MARK: - Published States (UI 绑定状态)
    
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentArtwork: NSImage?
    @Published private(set) var currentTracks: [AudioTrack] = []
    @Published private(set) var currentTrackIndex: Int?
    @Published private(set) var playingSource: PlayingSource = .playlist
    @Published private(set) var isPlaylistLoaded = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.7
    
    // MARK: - Managers
    
    let playlistManager: PlaylistManager
    
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
    
    private let playerCore: AudioPlayerCore
    private let persistenceService = PersistenceService()
    private weak var collectionManager: CollectionManager?
    private var cancellables = Set<AnyCancellable>()
    private var nowPlayingUpdateTimer: Timer?
    private var isWindowVisible = true
    
    // MARK: - Computed Properties
    
    var currentFormat: AudioFormat {
        currentTrack?.format ?? .unknown
    }
    
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
    
    init(collectionManager: CollectionManager? = nil) {
        self.playlistManager = PlaylistManager()
        self.playerCore = AudioPlayerCore()
        self.playerCore.delegate = self
        self.collectionManager = collectionManager
        
        RemoteCommandController.shared.setup(viewModel: self)
        
        restorePlaybackState()
        setupBindings()
        
        logger.debug("PlayerViewModel initialized")
    }
    
    deinit {
        Task { @MainActor in
            RemoteCommandController.shared.disable()
        }
    }
    
    private func setupBindings() {
        $repeatMode
            .sink { [weak self] newValue in
                guard let self else { return }
                Task { @MainActor in
                    self.playerCore.repeatMode = AudioPlayerCore.RepeatMode(from: newValue)
                }
            }
            .store(in: &cancellables)
        
        $volume
            .sink { [weak self] newValue in
                guard let self else { return }
                Task { @MainActor in
                    self.playerCore.volume = newValue
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Playback Control
    
    func play() {
        if currentTrack == nil, !playlistManager.isEmpty {
            playingSource = .playlist
            currentTracks = playlistManager.tracks
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
    
    // MARK: - Window Visibility
    
    func updateWindowVisibility(_ isVisible: Bool) {
        guard isWindowVisible != isVisible else { return }
        
        isWindowVisible = isVisible
        playerCore.updateWindowVisibility(isVisible)
        
        if isPlaying {
            if isVisible {
                startNowPlayingUpdateTimer()
            } else {
                stopNowPlayingUpdateTimer()
            }
        }
        
        logger.debug("ViewModel window visibility: \(isVisible ? "visible" : "hidden")")
    }
    
    // MARK: - Playlist Playback
    
    func addTracksToPlaylist(urls: [URL]) {
        Task {
            let wasEmpty = playlistManager.isEmpty
            let previousCount = playlistManager.count
            
            await playlistManager.addTracks(urls: urls)
            
            if !isPlaylistLoaded {
                isPlaylistLoaded = true
            }
            
            if playingSource == .playlist {
                currentTracks = playlistManager.tracks
            }
            
            if wasEmpty, !playlistManager.isEmpty {
                currentTrackIndex = 0
                await loadTrack(at: 0)
            } else if playingSource == .playlist, currentTrackIndex == nil {
                currentTrackIndex = previousCount
                await loadTrack(at: previousCount)
            }
        }
    }
    
    func removeTrackFromPlaylist(at index: Int) {
        guard playlistManager.tracks.indices.contains(index) else { return }
        
        var indexChanged = false
        
        if playingSource == .playlist, let currentIndex = currentTrackIndex {
            if index == currentIndex {
                pause()
                currentTrackIndex = nil
                indexChanged = true
            } else if index < currentIndex {
                currentTrackIndex = currentIndex - 1
                indexChanged = true
            }
        }
        
        playlistManager.removeTrack(at: index)
        
        if playingSource == .playlist {
            currentTracks = playlistManager.tracks
        }
        
        if indexChanged {
            savePlaybackState()
        }
        
        if playlistManager.isEmpty, playingSource == .playlist {
            RemoteCommandController.shared.disable()
        }
    }
    
    func clearPlaylist() {
        if playingSource == .playlist {
            pause()
            currentTrackIndex = nil
        }
        
        playlistManager.clearAll()
        
        if playingSource == .playlist {
            currentTracks = []
            RemoteCommandController.shared.disable()
        }
        
        savePlaybackState()
    }
    
    func moveTrackInPlaylist(from source: Int, to destination: Int) {
        playlistManager.moveTrack(from: source, to: destination)
        
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
            currentTracks = playlistManager.tracks
        }
        
        savePlaybackState()
    }
    
    func playPlaylistTrack(at index: Int) {
        guard playlistManager.tracks.indices.contains(index) else { return }
        
        playingSource = .playlist
        currentTracks = playlistManager.tracks
        
        loadAndPlay(at: index)
    }
    
    // MARK: - Album Playback
    
    func playAlbum(_ album: Album, startAt index: Int = 0) {
        guard !album.tracks.isEmpty else {
            logger.warning("Cannot play empty album: \(album.name)")
            return
        }
        
        playingSource = .album(album.id)
        currentTracks = album.tracks
        
        logger.info("💿 Playing album: \(album.name) (\(album.tracks.count) tracks)")
        
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
            savePlaybackState()
        }
    }
    
    private func enqueueNextTrack() {
        guard let currentIndex = currentTrackIndex else { return }
        
        let nextIndex: Int?
        
        switch repeatMode {
        case .one:
            return
        case .all:
            if currentIndex < currentTracks.count - 1 {
                nextIndex = currentIndex + 1
            } else {
                nextIndex = 0
            }
        case .off:
            if currentIndex < currentTracks.count - 1 {
                nextIndex = currentIndex + 1
            } else {
                nextIndex = nil
            }
        }
        
        guard let nextIndex, currentTracks.indices.contains(nextIndex) else {
            logger.debug("No next track to enqueue")
            return
        }
        
        let nextTrack = currentTracks[nextIndex]
        
        Task {
            await playerCore.enqueueTrack(nextTrack)
        }
    }
    
    // MARK: - Now Playing Updates
    
    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            return
        }
        
        NowPlayingService.shared.updateNowPlayingInfo(
            track: track,
            artwork: currentArtwork,
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying
        )
    }
    
    private func startNowPlayingUpdateTimer() {
        stopNowPlayingUpdateTimer()
        
        guard isWindowVisible else { return }
        
        nowPlayingUpdateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                NowPlayingService.shared.updatePlaybackTime(currentTime: self.currentTime)
            }
        }
    }
    
    private func stopNowPlayingUpdateTimer() {
        nowPlayingUpdateTimer?.invalidate()
        nowPlayingUpdateTimer = nil
    }
    
    // MARK: - Persistence
    
    private func savePlaybackState() {
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
 
    private func restorePlaybackState() {
        guard let state = try? persistenceService.loadPlaybackState() else {
            logger.notice("No saved playback state found")
            isPlaylistLoaded = true
            return
        }
        
        if let source = state.playingSource {
            switch source {
            case .playlist:
                playingSource = .playlist
                currentTracks = playlistManager.tracks
                currentTrackIndex = nil
                
                if let savedIndex = state.playlistCurrentIndex,
                   playlistManager.tracks.indices.contains(savedIndex)
                {
                    currentTrackIndex = savedIndex
                    
                    Task {
                        await loadTrack(at: savedIndex)
                    }
                    
                    logger.info("📋 Restored playlist: track \(savedIndex + 1)/\(self.playlistManager.count)")
                }
                
            case .album(let albumId):
                if let albumIndex = state.albumCurrentIndex {
                    Task {
                        if let album = await collectionManager?.loadSingleAlbum(id: albumId),
                           album.tracks.indices.contains(albumIndex)
                        {
                            await MainActor.run {
                                self.playingSource = .album(albumId)
                                self.currentTracks = album.tracks
                                self.currentTrackIndex = albumIndex
                            }
                            
                            await loadTrack(at: albumIndex)
                            
                            logger.info("💿 Restored album: \(album.name) - track \(albumIndex + 1)")
                        } else {
                            await MainActor.run {
                                self.playingSource = .playlist
                                self.currentTracks = self.playlistManager.tracks
                                self.currentTrackIndex = nil
                            }
                            logger.warning("Album or track not found, fallback to playlist")
                        }
                    }
                } else {
                    playingSource = .playlist
                    currentTracks = playlistManager.tracks
                    currentTrackIndex = nil
                }
            }
        } else {
            playingSource = .playlist
            currentTracks = playlistManager.tracks
            currentTrackIndex = nil
        }
        
        isPlaylistLoaded = true
    }
}

// MARK: - AudioPlayerCore Delegate

extension PlayerViewModel: AudioPlayerCoreDelegate {
    func playerCore(_ core: AudioPlayerCore, didUpdatePlaybackState isPlaying: Bool) {
        self.isPlaying = isPlaying
        
        NowPlayingService.shared.updatePlaybackState(isPlaying: isPlaying)
        
        if isPlaying {
            startNowPlayingUpdateTimer()
        } else {
            stopNowPlayingUpdateTimer()
        }
    }
    
    func playerCore(_ core: AudioPlayerCore, didUpdateTime currentTime: TimeInterval, duration: TimeInterval) {
        self.currentTime = currentTime
        self.duration = duration
    }
    
    func playerCore(_ core: AudioPlayerCore, didLoadTrack track: AudioTrack, artwork: NSImage?) {
        self.currentArtwork = artwork
        
        RemoteCommandController.shared.enable()
        updateNowPlayingInfo()
    }
    
    func playerCore(_ core: AudioPlayerCore, didEncounterError error: Error) {
        logger.logError(error, context: "PlayerCore")
    }
    
    func playerCore(_ core: AudioPlayerCore, nowPlayingChangedTo url: URL?) {
        guard let url else {
            logger.debug("Now playing changed to nil")
            return
        }
        
        if let index = currentTracks.firstIndex(where: { $0.url == url }) {
            let indexChanged = (currentTrackIndex != index)
            
            if indexChanged {
                logger.info("🔄 Auto switched to track \(index + 1): \(self.currentTracks[index].title)")
                currentTrackIndex = index
            }
            
            Task {
                let track = currentTracks[index]
                let artwork = await ArtworkCacheService.shared.artwork(for: track.url)
                await MainActor.run {
                    self.currentArtwork = artwork
                    self.duration = track.duration
                    
                    self.updateNowPlayingInfo()
                    
                    if indexChanged {
                        self.savePlaybackState()
                    }
                }
            }
        } else {
            logger.warning("Track not found in current tracks: \(url.lastPathComponent)")
        }
    }
    
    func playerCore(_ core: AudioPlayerCore, decodingCompleteFor track: AudioTrack) {
        logger.debug("🔄 Decoding complete, enqueuing next track")
        enqueueNextTrack()
    }
    
    func playerCoreDidReachEnd(_ core: AudioPlayerCore) {
        if repeatMode == .one {
            if let index = currentTrackIndex {
                loadAndPlay(at: index)
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
