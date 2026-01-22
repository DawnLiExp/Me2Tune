//
//  PlayerViewModel.swift
//  Me2Tune
//
//  播放器视图模型 - 协调播放控制、播放列表、状态管理
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
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentArtwork: NSImage?
    @Published private(set) var isPlaylistLoaded = false
    @Published var repeatMode: RepeatMode = .off

    // MARK: - Progress State (独立 ObservableObject)

    let playbackProgressState = PlaybackProgressState()
    @Published var volume: Double = 0.7
    
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
    private let persistenceService = PersistenceService()
    
    private var cancellables = Set<AnyCancellable>()
    
    private var nowPlayingTimerCancellable: AnyCancellable?
    private var stateSaveTimer: DispatchSourceTimer?
    private var pendingSaveTask: Task<Void, Never>?
    
    private var isWindowVisible = true
    
    // MARK: - Now Playing Control
    
    private var nowPlayingEnabled: Bool {
        UserDefaults.standard.object(forKey: "nowPlayingEnabled") as? Bool ?? true
    }
    
    // MARK: - Computed Properties
    
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
    
    var currentTime: TimeInterval {
        playbackProgressState.currentTime
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
        
        Task { @MainActor in
            await restorePlaybackState()
        }
        
        setupBindings()
        
        logger.debug("PlayerViewModel initialized")
    }
    
    deinit {
        stateSaveTimer?.cancel()
        stateSaveTimer = nil
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
    }

    private func setupBindings() {
        $repeatMode
            .sink { [weak self] newValue in
                guard let self else { return }
                self.playerCore.repeatMode = AudioPlayerCore.RepeatMode(from: newValue)
            }
            .store(in: &cancellables)
        
        $volume
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] newValue in
                guard let self else { return }
                self.playerCore.setVolume(newValue)
                self.saveVolume(newValue)
            }
            .store(in: &cancellables)
        
        playlistManager.$isLoading
            .receive(on: RunLoop.main)
            .assign(to: &$isLoadingTracks)
        
        playlistManager.$loadingCount
            .receive(on: RunLoop.main)
            .assign(to: &$loadingTracksCount)
        
        Publishers.Merge(
            playlistManager.objectWillChange,
            playbackStateManager.objectWillChange
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .windowVisibilityDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self,
                      let state = notification.object as? WindowStateMonitor.WindowVisibilityState
                else { return }
                self.playerCore.updateVisibilityState(state)
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
        scheduleStateSave()
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
        scheduleStateSave()
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
    
    // MARK: - Real-time Progress Access
    
    func getCurrentPlaybackTime() -> TimeInterval {
        return playerCore.getCurrentPlaybackTime()
    }
    
    // MARK: - Window Visibility

    func updateWindowVisibility(_ state: WindowStateMonitor.WindowVisibilityState) {
        playerCore.updateVisibilityState(state)
        
        isWindowVisible = (state == .activeFocused || state == .inactive)
        
        // ✅ 定时器只在开关开启时根据窗口状态调整
        if playerCore.isPlaying, nowPlayingEnabled {
            if state == .activeFocused {
                startNowPlayingUpdateTimer()
            } else {
                stopNowPlayingUpdateTimer()
            }
        }
        
        logger.debug("ViewModel visibility: \(state.description)")
    }
    
    // MARK: - Playlist Operations
    
    func addTracksToPlaylist(urls: [URL]) {
        Task { @MainActor in
            await playlistManager.addTracks(urls: urls)
            
            if !isPlaylistLoaded {
                isPlaylistLoaded = true
            }
            
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
        
        playlistManager.removeTrack(at: index)
        playbackStateManager.handlePlaylistTrackRemoved(at: index, wasPlaying: wasPlaying)
        
        scheduleStateSave()
        
        if playlistManager.isEmpty, playingSource == .playlist {
            RemoteCommandController.shared.disable()
        }
    }
    
    func clearPlaylist() {
        if playingSource == .playlist {
            pause()
        }
        
        playlistManager.clearAll()
        playbackStateManager.handlePlaylistCleared()
        
        if playingSource == .playlist {
            RemoteCommandController.shared.disable()
        }
        
        scheduleStateSave()
    }
    
    func moveTrackInPlaylist(from source: Int, to destination: Int) {
        playlistManager.moveTrack(from: source, to: destination)
        playbackStateManager.handlePlaylistTrackMoved(from: source, to: destination)
        scheduleStateSave()
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
    
    // MARK: - Track Loading
    
    private func loadTrack(_ track: AudioTrack) async {
        await playerCore.loadTrack(track)
    }
    
    private func loadAndPlay(at index: Int) {
        guard currentTracks.indices.contains(index) else { return }
        
        Task { @MainActor in
            playbackStateManager.setCurrentIndex(index)
            let track = currentTracks[index]
            await loadTrack(track)
            playerCore.play()
            scheduleStateSave()
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
        
        Task { @MainActor in
            await playerCore.enqueueTrack(nextTrack)
        }
    }
    
    // MARK: - Now Playing Updates

    private func updateNowPlayingInfo() {
        // ✅ 始终更新基本信息（确保媒体键工作）
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
        
        // 只在开关开启时启动定时器
        guard nowPlayingEnabled, isWindowVisible else { return }
        
        nowPlayingTimerCancellable = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isPlaying else { return }
                NowPlayingService.shared.updatePlaybackTime(currentTime: self.currentTime)
            }
    }

    private func stopNowPlayingUpdateTimer() {
        nowPlayingTimerCancellable?.cancel()
        nowPlayingTimerCancellable = nil
    }
    
    // MARK: - Persistence
    
    func saveState() {
        playbackStateManager.saveState(volume: volume)
    }
    
    private func scheduleStateSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            saveState()
        }
    }
    
    private func saveVolume(_ volume: Double) {}
    
    private func startStateSaveTimer() {
        stopStateSaveTimer()
        
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 5.0, repeating: 5.0, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self, self.isPlaying else { return }
            self.saveState()
        }
        timer.resume()
        stateSaveTimer = timer
        logger.debug("💾 State save timer started")
    }
    
    private func stopStateSaveTimer() {
        stateSaveTimer?.cancel()
        stateSaveTimer = nil
    }
 
    private func restorePlaybackState() async {
        guard let restored = await playbackStateManager.restoreState() else {
            isPlaylistLoaded = true
            return
        }
        
        if let savedVolume = restored.volume {
            volume = savedVolume
            logger.debug("🔊 Restored volume: \(String(format: "%.0f", savedVolume * 100))%")
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
            if nowPlayingEnabled {
                startNowPlayingUpdateTimer()
            }
            startStateSaveTimer()
        } else {
            stopNowPlayingUpdateTimer()
            stopStateSaveTimer()
        }
    }
    
    func playerCore(_ core: AudioPlayerCore, didUpdateTime currentTime: TimeInterval, duration: TimeInterval) {
        playbackProgressState.currentTime = currentTime
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
            
            Task { @MainActor in
                let track = currentTracks[index]
                let artwork = await ArtworkCacheService.shared.artwork(for: track.url)
                
                self.currentArtwork = artwork
                self.duration = track.duration
                
                self.updateNowPlayingInfo()
                self.playerCore.updateDockIcon(artwork)
                
                if indexChanged {
                    self.scheduleStateSave()
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
