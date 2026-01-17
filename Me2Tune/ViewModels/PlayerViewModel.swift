//
//  PlayerViewModel.swift
//  Me2Tune
//
//  播放器视图模型 - 协调播放控制、播放列表、状态管理
//
//  职责边界：
//  1. 协调 AudioPlayerCore（播放控制）
//  2. 委托 PlaylistManager（播放列表增删改查）
//  3. 委托 PlaybackStateManager（播放源切换、状态持久化）
//  4. 统一对外接口（View 层只与 ViewModel 交互）
//

import AppKit
import Combine
import Foundation
import OSLog

private let logger = Logger.viewModel

@MainActor
final class PlayerViewModel: ObservableObject {
    
    // MARK: - Published States (UI 绑定状态)
    // 这些状态由 ViewModel 管理，直接影响 UI 显示
    
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
    
    // MARK: - Managers (委托的管理器)
    // ViewModel 委托这些 Manager 处理具体业务逻辑
    
    let playlistManager: PlaylistManager            // 播放列表管理
    let playbackStateManager: PlaybackStateManager  // 播放状态管理
    
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
    private var nowPlayingUpdateTimer: Timer?
    private var isWindowVisible = true
    
    // MARK: - Computed Properties (代理到 Manager 的只读属性)
    // 这些属性从 Manager 获取，简化 View 层调用
    
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
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] newValue in
                guard let self else { return }
                Task { @MainActor in
                    self.playerCore.setVolume(newValue)
                    self.saveVolume(newValue)
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
        
        // 4. 监听窗口状态变化（独立于 ContentView）
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
    
    // MARK: - Playback Control (核心播放控制 - 协调 AudioPlayerCore)
    // 这些方法直接操作播放器，是 ViewModel 的核心职责
    
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
    
    // MARK: - Window Visibility (窗口状态管理)
    
    func updateWindowVisibility(_ state: WindowStateMonitor.WindowVisibilityState) {
        playerCore.updateVisibilityState(state)
        
        if playerCore.isPlaying {
            if state == .activeFocused {
                startNowPlayingUpdateTimer()
            } else {
                stopNowPlayingUpdateTimer()
            }
        }
        
        logger.debug("ViewModel visibility: \(state.description)")
    }
    
    // MARK: - Playlist Operations (播放列表操作 - 委托给 PlaylistManager)
    // 这些方法是便利接口，实际操作由 PlaylistManager 执行
    // View 层统一调用 ViewModel，避免直接依赖 Manager
    
    /// 添加曲目到播放列表（异步批量加载）
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
    
    /// 从播放列表移除曲目
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
    
    /// 清空播放列表
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
    
    /// 移动播放列表中的曲目
    func moveTrackInPlaylist(from source: Int, to destination: Int) {
        playlistManager.moveTrack(from: source, to: destination)
        playbackStateManager.handlePlaylistTrackMoved(from: source, to: destination)
        playbackStateManager.saveState()
    }
    
    /// 播放播放列表中的指定曲目
    func playPlaylistTrack(at index: Int) {
        guard playlistManager.tracks.indices.contains(index) else { return }
        
        playbackStateManager.switchToPlaylist()
        loadAndPlay(at: index)
    }
    
    // MARK: - Album Playback (专辑播放 - 协调 PlaybackStateManager)
    // 切换播放源到专辑，由 PlaybackStateManager 管理状态
    
    /// 播放专辑（切换播放源）
    func playAlbum(_ album: Album, startAt index: Int = 0) {
        guard !album.tracks.isEmpty else {
            logger.warning("Cannot play empty album: \(album.name)")
            return
        }
        
        playbackStateManager.switchToAlbum(album)
        loadAndPlay(at: index)
    }
    
    // MARK: - Track Loading (内部方法 - 曲目加载)
    // 这些是私有协调逻辑，View 层不应直接调用
    
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
    
    // MARK: - Now Playing Updates (系统媒体控制中心更新)
    
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
    
    // MARK: - Volume Persistence (音量持久化)
    
    private func saveVolume(_ volume: Double) {
        do {
            var state = (try? persistenceService.loadPlaybackState()) ?? PlaybackState(
                playlistCurrentIndex: nil,
                albumCurrentIndex: nil,
                playingSource: nil,
                volume: volume
            )
            state.volume = volume
            try persistenceService.savePlaybackState(state)
        } catch {
            logger.error("Failed to save volume: \(error)")
        }
    }
    
    // MARK: - Persistence (状态恢复)
 
    private func restorePlaybackState() async {
        // 恢复音量
        if let savedVolume = try? persistenceService.loadPlaybackState().volume {
            volume = savedVolume
            logger.debug("🔊 Restored volume: \(String(format: "%.0f", savedVolume * 100))%")
        }
        
        // 恢复播放状态
        guard let restored = await playbackStateManager.restoreState() else {
            isPlaylistLoaded = true
            return
        }
        
        await loadTrack(restored.track)
        isPlaylistLoaded = true
    }
}

// MARK: - AudioPlayerCore Delegate (播放器核心回调)
// 处理 AudioPlayerCore 的状态变化，更新 UI 和系统媒体控制

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
                    
                    // 🆕 更新 dock 图标
                    self.playerCore.updateDockIcon(artwork)
                    
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
