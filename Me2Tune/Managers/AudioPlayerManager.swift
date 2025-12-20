//
//  AudioPlayerManager.swift
//  Me2Tune
//
//  音频播放器管理 - 添加循环播放和音量控制
//

import AppKit
import Combine
import Foundation
import OSLog
import SFBAudioEngine

private let logger = Logger(subsystem: "me2.Me2Tune", category: "AudioPlayerManager")

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    @Published private(set) var playlist: [AudioTrack] = []
    @Published private(set) var currentTracks: [AudioTrack] = []
    @Published private(set) var currentTrackIndex: Int?
    @Published private(set) var playingSource: PlayingSource = .playlist
    
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentArtwork: NSImage?
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.7
    
    private var player: AudioPlayer?
    private let artworkService = ArtworkService()
    private let persistenceService = PersistenceService()
    private var timer: Timer?
    
    enum PlayingSource: Equatable {
        case playlist
        case album(UUID)
    }
    
    enum RepeatMode {
        case off
        case all
        case one
    }
    
    var currentTrack: AudioTrack? {
        guard let index = currentTrackIndex, currentTracks.indices.contains(index) else {
            return nil
        }
        return currentTracks[index]
    }
    
    override init() {
        super.init()
        
        Task {
            await loadPlaylist()
            currentTracks = playlist
        }
    }
    
    // MARK: - Playback Settings
    
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
            
            await MainActor.run {
                playlist.append(contentsOf: newTracks)
                
                if playingSource == .playlist {
                    currentTracks = playlist
                }
                
                if currentTrackIndex == nil, !currentTracks.isEmpty {
                    currentTrackIndex = 0
                    loadTrack(at: 0)
                }
                
                Task {
                    await savePlaylist()
                }
            }
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
    
    // MARK: - Playback Control
    
    func play() {
        ensurePlayerInitialized()
        
        guard let player else { return }
        
        do {
            try player.play()
            isPlaying = true
            startTimer()
            logger.debug("Playback started")
        } catch {
            logger.error("Play failed: \(error.localizedDescription)")
        }
    }
    
    func pause() {
        guard let player else { return }
        
        player.pause()
        isPlaying = false
        stopTimer()
        logger.debug("Playback paused")
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
        guard let player, player.supportsSeeking else { return }
        
        let wasPlaying = isPlaying
        if wasPlaying {
            player.pause()
        }
        
        if player.seek(time: time) {
            currentTime = time
            logger.debug("Seeked to \(time)s")
        }
        
        if wasPlaying {
            do {
                try player.play()
            } catch {
                logger.error("Resume after seek failed: \(error.localizedDescription)")
                isPlaying = false
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func ensurePlayerInitialized() {
        guard player == nil else { return }
        
        player = AudioPlayer()
        player?.delegate = self
        logger.debug("Audio player initialized")
    }
    
    private func loadTrack(at index: Int) {
        guard currentTracks.indices.contains(index) else { return }
        
        ensurePlayerInitialized()
        guard let player else { return }
        
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        stopTimer()
        
        let track = currentTracks[index]
        currentTrackIndex = index
        
        logger.info("Loading track: \(track.title) by \(track.artist ?? "Unknown")")
        
        do {
            try player.play(track.url)
            player.pause()
            
            duration = track.duration
            currentTime = 0
            isPlaying = false
            
            Task {
                currentArtwork = await artworkService.artwork(for: track.url)
                updateDockIcon()
            }
        } catch {
            logger.error("Failed to load track: \(error.localizedDescription)")
            isPlaying = false
        }
    }
    
    private func loadAndPlay(at index: Int) {
        loadTrack(at: index)
        play()
        
        if playingSource == .playlist {
            Task {
                await savePlaylist()
            }
        }
    }
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime ?? 0
                self.duration = player.totalTime ?? 0
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateDockIcon() {
        guard let artwork = currentArtwork else {
            NSApp.dockTile.contentView = nil
            NSApp.dockTile.display()
            return
        }
        
        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        imageView.image = artwork
        imageView.imageScaling = .scaleProportionallyUpOrDown
        
        NSApp.dockTile.contentView = imageView
        NSApp.dockTile.display()
    }
    
    // MARK: - Persistence
    
    private func savePlaylist() async {
        let state = PlaylistState(
            tracks: playlist,
            currentIndex: playingSource == .playlist ? currentTrackIndex : nil,
        )
        
        do {
            try await persistenceService.save(state)
            logger.debug("Playlist saved with metadata cache")
        } catch {
            logger.error("Failed to save playlist: \(error.localizedDescription)")
        }
    }
    
    private func loadPlaylist() async {
        guard let state = try? await persistenceService.load() else {
            logger.notice("No existing playlist to load")
            return
        }
        
        await MainActor.run {
            playlist = state.tracks
            
            if let savedIndex = state.currentIndex,
               playlist.indices.contains(savedIndex)
            {
                currentTrackIndex = savedIndex
            }
            
            logger.info("Loaded playlist with \(state.tracks.count) tracks from cache")
        }
    }
}

// MARK: - AudioPlayer.Delegate

extension AudioPlayerManager: AudioPlayer.Delegate {
    nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, playbackStateChanged playbackState: AudioPlayer.PlaybackState) {
        Task { @MainActor in
            isPlaying = (playbackState == .playing)
        }
    }
    
    nonisolated func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
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
                   currentIndex < currentTracks.count - 1 {
                    next()
                }
            }
        }
    }
    
    @objc nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) {
        Task { @MainActor in
            logger.error("Player error: \(error.localizedDescription)")
        }
    }
}
