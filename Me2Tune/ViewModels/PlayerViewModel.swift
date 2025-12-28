//
//  PlayerViewModel.swift
//  Me2Tune
//
//  播放器视图模型 - 状态管理 + 业务逻辑封装
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
    @Published private(set) var playingSource: AudioPlayerManager.PlayingSource = .playlist
    @Published private(set) var isPlaylistLoaded = false
    @Published var repeatMode: AudioPlayerManager.RepeatMode = .off
    @Published var volume: Double = 0.7
    
    // MARK: - Private Properties
    
    private let playerManager: AudioPlayerManager
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
    var currentTrack: AudioTrack? {
        playerManager.currentTrack
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
        self.playerManager = AudioPlayerManager()
        setupBindings()
        logger.debug("PlayerViewModel initialized")
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // 由于 playerManager 已经是 @MainActor，直接订阅即可
        playerManager.$isPlaying
            .assign(to: &$isPlaying)
        
        playerManager.$currentTime
            .assign(to: &$currentTime)
        
        playerManager.$duration
            .assign(to: &$duration)
        
        playerManager.$currentArtwork
            .assign(to: &$currentArtwork)
        
        playerManager.$playlist
            .assign(to: &$playlist)
        
        playerManager.$currentTracks
            .assign(to: &$currentTracks)
        
        playerManager.$currentTrackIndex
            .assign(to: &$currentTrackIndex)
        
        playerManager.$playingSource
            .assign(to: &$playingSource)
        
        playerManager.$isPlaylistLoaded
            .assign(to: &$isPlaylistLoaded)
        
        playerManager.$repeatMode
            .assign(to: &$repeatMode)
        
        playerManager.$volume
            .assign(to: &$volume)
        
        // 双向绑定：ViewModel -> Manager
        $repeatMode
            .dropFirst()
            .sink { [weak playerManager] newValue in
                playerManager?.repeatMode = newValue
            }
            .store(in: &cancellables)
        
        $volume
            .dropFirst()
            .sink { [weak playerManager] newValue in
                playerManager?.volume = newValue
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Playback Control
    
    func play() {
        playerManager.play()
    }
    
    func pause() {
        playerManager.pause()
    }
    
    func togglePlayPause() {
        playerManager.togglePlayPause()
    }
    
    func previous() {
        playerManager.previous()
    }
    
    func next() {
        playerManager.next()
    }
    
    func seek(to time: TimeInterval) {
        playerManager.seek(to: time)
    }
    
    func toggleRepeatMode() {
        playerManager.toggleRepeatMode()
    }
    
    // MARK: - Playlist Management
    
    func addTracks(urls: [URL]) {
        playerManager.addTracks(urls: urls)
    }
    
    func removeTrack(at index: Int) {
        playerManager.removeTrack(at: index)
    }
    
    func clearPlaylist() {
        playerManager.clearPlaylist()
    }
    
    func moveTrack(from source: Int, to destination: Int) {
        playerManager.moveTrack(from: source, to: destination)
    }
    
    func playTrack(at index: Int) {
        playerManager.playTrack(at: index)
    }
    
    func playAlbum(_ album: Album, startAt index: Int = 0) {
        playerManager.playAlbum(album, startAt: index)
    }
    
    // MARK: - Album Integration
    
    func restoreAlbumPlayback(albums: [Album]) async {
        await playerManager.restoreAlbumPlayback(albums: albums)
    }
}
