//
//  PlayerViewModel.swift
//  Me2Tune
//
//  播放器视图模型 - 播放控制 + 协调器
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
    @Published private(set) var isPlaylistLoaded = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.7
    
    // 从 PlaylistManager 同步的加载状态
    @Published private(set) var isLoadingTracks = false
    @Published private(set) var loadingTracksCount = 0
    
    // MARK: - Managers
    
    let playlistManager: PlaylistManager
    let playbackStateManager: PlaybackStateManager
    
    // MARK: - Types
    
    typealias PlayingSource = PlaybackStateManager.PlayingSource
    
    enum RepeatMode {
        case off
        case all
        case one
    }
    
    // MARK: - Private Properties
    
    private let playerCore: AudioPlayerCore
    private var cancellables = Set<AnyCancellable>()
    private var nowPlayingUpdateTimer: Timer?
    private var isWindowVisible = true
    
    // MARK: - Computed Properties (代理到 PlaybackStateManager)
    
    var currentFormat: AudioFormat {
        currentTrack?.format ?? .unknown
    }
    
    var currentTrack: AudioTrack? {
        playbackStateManager.currentTrack
    }
    
    var currentTrackIndex: Int? {
        playbackStateManager.currentTrackIndex
    }
    
    var currentTracks: [AudioTrack] {
        playbackStateManager.currentTracks
    }
    
    var playingSource: PlaybackStateManager.PlayingSource {
        playbackStateManager.playingSource
    }
    
    var canGoPrevious: Bool {
        playbackStateManager.canGoPrevious
    }
    
    var canGoNext: Bool {
        playbackStateManager.canGoNext
    }
    
    // MARK: - Initialization
    
    init(collectionManager: CollectionManager? = nil) {
        self.playlistManager = PlaylistManager()
        self.playbackStateManager = PlaybackStateManager(
            playlistManager: playlistManager,
            collectionManager: collectionManager
        )
        self.playerCore = AudioPlayerCore()
        self.playerCore.delegate = self
        
        RemoteCommandController.shared.setup(viewModel: self)
        
        Task {
            await restorePlaybackState()
        }
        
        setupBindings()
        
        logger.debug("PlayerViewModel initialized")
    }
    
    deinit {
        Task { @MainActor in
            RemoteCommandController.shared.disable()
        }
    }
    
    private func setupBindings() {
        // 1. 播放控制状态绑定
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
        
        // 2. 加载状态同步（单向绑定）
        playlistManager.$isLoading
            .receive(on: RunLoop.main)
            .assign(to: &$isLoadingTracks)
        
        playlistManager.$loadingCount
            .receive(on: RunLoop.main)
            .assign(to: &$loadingTracksCount)
        
        // 3. 子 Manager 变化转发（统一刷新入口）
        Publishers.Merge(
            playlistManager.objectWillChange,
            playbackStateManager.objectWillChange
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
    }
    
    // MARK: - Playback Control
    
    func play() {
        if currentTrack == nil, !playlistManager.isEmpty {
            playbackStateManager.switchToPlaylist()
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
        guard let previousIndex = playbackStateManager.moveToPreviousIndex() else {
            return
        }
        
        loadAndPlay(at: previousIndex)
    }
    
    func next() {
        guard let nextIndex = playbackStateManager.moveToNextIndex() else {
            return
        }
        
        loadAndPlay(at: nextIndex)
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
            await playlistManager.addTracks(urls: urls)
            
            if !isPlaylistLoaded {
                isPlaylistLoaded = true
            }
            
            // 显式触发状态同步（仅在添加后）
            playbackStateManager.handlePlaylistTracksAdded()
            
            if currentTrackIndex == nil, let track = currentTrack {
                await loadTrack(track)
            }
        }
    }
    
    func removeTrackFromPlaylist(at index: Int) {
        guard playlistManager.tracks.indices.contains(index) else { return }
        
        let wasPlaying = (playingSource == .playlist && currentTrackIndex == index)
        
        if wasPlaying {
            pause()
        }
        
        // 先修改数据源，再同步状态
        playlistManager.removeTrack(at: index)
        playbackStateManager.handlePlaylistTrackRemoved(at: index, wasPlaying: wasPlaying)
        
        playbackStateManager.saveState()
        
        if playlistManager.isEmpty, playingSource == .playlist {
            RemoteCommandController.shared.disable()
        }
    }
    
    func clearPlaylist() {
        if playingSource == .playlist {
            pause()
        }
        
        // 先修改数据源，再同步状态
        playlistManager.clearAll()
        playbackStateManager.handlePlaylistCleared()
        
        if playingSource == .playlist {
            RemoteCommandController.shared.disable()
        }
        
        playbackStateManager.saveState()
    }
    
    func moveTrackInPlaylist(from source: Int, to destination: Int) {
        playlistManager.moveTrack(from: source, to: destination)
        playbackStateManager.handlePlaylistTrackMoved(from: source, to: destination)
        playbackStateManager.saveState()
    }
    
    func playPlaylistTrack(at index: Int) {
        guard playlistManager.tracks.indices.contains(index) else { return }
        
        playbackStateManager.switchToPlaylist()
        loadAndPlay(at: index)
    }
    
    // MARK: - Album Playback
    
    func playAlbum(_ album: Album, startAt index: Int = 0) {
        guard !album.tracks.isEmpty else {
            logger.warning("Cannot play empty album: \(album.name)")
            return
        }
        
        playbackStateManager.switchToAlbum(album)
        loadAndPlay(at: index)
    }
    
    // MARK: - Track Loading (私有方法)
    
    private func loadTrack(_ track: AudioTrack) async {
        await playerCore.loadTrack(track)
    }
    
    private func loadAndPlay(at index: Int) {
        guard currentTracks.indices.contains(index) else { return }
        
        Task {
            playbackStateManager.setCurrentIndex(index)
            let track = currentTracks[index]
            await loadTrack(track)
            playerCore.play()
            playbackStateManager.saveState()
        }
    }
    
    private func enqueueNextTrack() {
        let stateRepeatMode: PlaybackStateManager.RepeatMode = {
            switch repeatMode {
            case .off: return .off
            case .all: return .all
            case .one: return .one
            }
        }()
        
        guard let nextIndex = playbackStateManager.calculateNextIndex(repeatMode: stateRepeatMode),
              currentTracks.indices.contains(nextIndex)
        else {
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
 
    private func restorePlaybackState() async {
        guard let restored = await playbackStateManager.restoreState() else {
            isPlaylistLoaded = true
            return
        }
        
        await loadTrack(restored.track)
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
                playbackStateManager.setCurrentIndex(index)
            }
            
            Task {
                let track = currentTracks[index]
                let artwork = await ArtworkCacheService.shared.artwork(for: track.url)
                await MainActor.run {
                    self.currentArtwork = artwork
                    self.duration = track.duration
                    
                    self.updateNowPlayingInfo()
                    
                    if indexChanged {
                        self.playbackStateManager.saveState()
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
        if repeatMode == .one, let index = currentTrackIndex {
            loadAndPlay(at: index)
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
