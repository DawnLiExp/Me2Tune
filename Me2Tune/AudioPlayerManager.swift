//
//  AudioPlayerManager.swift
//  Me2Tune
//
//  音频播放器管理：使用SFBAudioEngine支持FLAC等格式
//

import Foundation
import SFBAudioEngine
internal import Combine

// MARK: - Audio Track Model

struct AudioTrack: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let title: String
    let duration: TimeInterval
    
    init(url: URL) async {
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
        
        if let audioFile = try? AudioFile(readingPropertiesAndMetadataFrom: url),
           let duration = audioFile.properties.duration
        {
            self.duration = duration
        } else {
            self.duration = 0
        }
    }
}

// MARK: - Audio Player Manager

@MainActor
final class AudioPlayerManager: NSObject, ObservableObject {
    @Published private(set) var playlist: [AudioTrack] = []
    @Published private(set) var currentTrackIndex: Int?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    
    private let player = AudioPlayer()
    private var timer: Timer?
    
    var currentTrack: AudioTrack? {
        guard let index = currentTrackIndex, playlist.indices.contains(index) else {
            return nil
        }
        return playlist[index]
    }
    
    override init() {
        super.init()
        player.delegate = self
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
            }
        }
    }
    
    // MARK: - Playback Control
    
    func play() {
        do {
            try player.play()
            isPlaying = true
            startTimer()
        } catch {
            print("❌ Play failed: \(error.localizedDescription)")
        }
    }
    
    func pause() {
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
        guard player.supportsSeeking else { return }
        
        if player.seek(time: time) {
            currentTime = time
        } else {
            print("❌ Seek failed")
        }
    }
    
    // MARK: - Private Methods
    
    private func loadTrack(at index: Int) {
        guard playlist.indices.contains(index) else { return }
        
        let track = playlist[index]
        currentTrackIndex = index
        
        do {
            try player.play(track.url)
            duration = track.duration
            currentTime = 0
            isPlaying = true
            startTimer()
        } catch {
            print("❌ Failed to load track: \(error.localizedDescription)")
            isPlaying = false
        }
    }
    
    private func loadAndPlay(at index: Int) {
        stopTimer()
        loadTrack(at: index)
    }
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = self.player.currentTime ?? 0
                self.duration = self.player.totalTime ?? 0
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
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
