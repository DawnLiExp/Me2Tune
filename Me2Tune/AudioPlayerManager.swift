//
//  AudioPlayerManager.swift
//  Me2Tune
//
//  音频播放器管理：播放控制、列表管理、进度更新
//

import Foundation
import AVFoundation
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
        
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            self.duration = duration.seconds
        } catch {
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
    
    private var player: AVAudioPlayer?
    private var timer: Timer?
    
    var currentTrack: AudioTrack? {
        guard let index = currentTrackIndex, playlist.indices.contains(index) else {
            return nil
        }
        return playlist[index]
    }
    
    // MARK: - Playlist Management
    
    func addTracks(urls: [URL]) {
        let supportedExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "aif"]
        
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
                
                if currentTrackIndex == nil && !playlist.isEmpty {
                    currentTrackIndex = 0
                    loadTrack(at: 0)
                }
            }
        }
    }
    
    // MARK: - Playback Control
    
    func play() {
        guard let player = player else { return }
        
        player.play()
        isPlaying = true
        startTimer()
    }
    
    func pause() {
        player?.pause()
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
              currentIndex < playlist.count - 1 else {
            return
        }
        
        let newIndex = currentIndex + 1
        loadAndPlay(at: newIndex)
    }
    
    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }
    
    // MARK: - Private Methods
    
    private func loadTrack(at index: Int) {
        guard playlist.indices.contains(index) else { return }
        
        let track = playlist[index]
        currentTrackIndex = index
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                let newPlayer = try AVAudioPlayer(contentsOf: track.url)
                newPlayer.prepareToPlay()
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.player = newPlayer
                    self.player?.delegate = self
                    self.duration = newPlayer.duration
                    self.currentTime = 0
                }
            } catch {
                print("❌ Failed to load track: \(error.localizedDescription)")
            }
        }
    }
    
    private func loadAndPlay(at index: Int) {
        let wasPlaying = isPlaying
        stopTimer()
        
        loadTrack(at: index)
        
        if wasPlaying {
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                play()
            }
        }
    }
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayerManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if flag {
                next()
            }
        }
    }
}
