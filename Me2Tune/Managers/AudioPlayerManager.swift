//
//  AudioPlayerManager.swift
//  Me2Tune
//
//  音频播放器管理
//

import AppKit
import Foundation
import SFBAudioEngine
internal import Combine

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    @Published private(set) var playlist: [AudioTrack] = []
    @Published private(set) var currentTrackIndex: Int?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentArtwork: NSImage?
    
    private var player: AudioPlayer?
    private let artworkService = ArtworkService()
    private let persistenceService = PersistenceService()
    private var timer: Timer?
    
    var currentTrack: AudioTrack? {
        guard let index = currentTrackIndex, playlist.indices.contains(index) else {
            return nil
        }
        return playlist[index]
    }
    
    override init() {
        super.init()
        
        Task {
            await loadPlaylist()
        }
    }
    
    // MARK: - Playlist Management
    
    func addTracks(urls: [URL]) {
        let supportedExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ape", "wv", "tta", "mpc"]
        
        let validURLs = urls.filter { url in
            supportedExtensions.contains(url.pathExtension.lowercased())
        }
        
        Task {
            var newTracks: [AudioTrack] = []
            for url in validURLs {
                let track = await AudioTrack(url: url)
                newTracks.append(track)
            }
            
            await MainActor.run {
                playlist.append(contentsOf: newTracks)
                
                if currentTrackIndex == nil, !playlist.isEmpty {
                    currentTrackIndex = 0
                    loadTrack(at: 0)
                }
                
                Task {
                    await savePlaylist()
                }
            }
        }
    }
    
    func playTrack(at index: Int) {
        guard playlist.indices.contains(index) else { return }
        loadAndPlay(at: index)
    }
    
    // 移除 loadAlbum 方法，collections操作不应影响主播放列表 playlist
    
    // MARK: - Playback Control
    
    func play() {
        ensurePlayerInitialized()
        
        guard let player else { return }
        
        do {
            try player.play()
            isPlaying = true
            startTimer()
        } catch {
            print("❌ Play failed: \(error.localizedDescription)")
        }
    }
    
    func pause() {
        guard let player else { return }
        
        player.pause()
        isPlaying = false
        stopTimer()
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
              currentIndex < playlist.count - 1
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
        }
        
        if wasPlaying {
            do {
                try player.play()
            } catch {
                print("❌ Resume after seek failed: \(error.localizedDescription)")
                isPlaying = false
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func ensurePlayerInitialized() {
        guard player == nil else { return }
        
        player = AudioPlayer()
        player?.delegate = self
    }
    
    private func loadTrack(at index: Int) {
        guard playlist.indices.contains(index) else { return }
        
        ensurePlayerInitialized()
        guard let player else { return }
        
        // 停止当前播放
        if isPlaying {
            player.pause()
            isPlaying = false
        }
        stopTimer()
        
        let track = playlist[index]
        currentTrackIndex = index
        
        do {
            // 先加载，不自动播放
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
            print("❌ Failed to load track: \(error.localizedDescription)")
            isPlaying = false
        }
    }
    
    private func loadAndPlay(at index: Int) {
        loadTrack(at: index)
        play()
        
        Task {
            await savePlaylist()
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
            trackURLs: playlist.map(\.url),
            currentIndex: currentTrackIndex,
        )
        
        try? await persistenceService.save(state)
    }
    
    private func loadPlaylist() async {
        guard let state = try? await persistenceService.load() else {
            return
        }
        
        var loadedTracks: [AudioTrack] = []
        for url in state.trackURLs {
            let track = await AudioTrack(url: url)
            loadedTracks.append(track)
        }
        
        await MainActor.run {
            playlist = loadedTracks
            
            if let savedIndex = state.currentIndex,
               playlist.indices.contains(savedIndex)
            {
                currentTrackIndex = savedIndex
            }
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
            next()
        }
    }
    
    @objc nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) {
        print("❌ Player error: \(error.localizedDescription)")
    }
}
