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

private let logger = Logger.viewModel

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
    private weak var collectionManager: CollectionManager?
    private var cancellables = Set<AnyCancellable>()
    
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
        self.playerCore = AudioPlayerCore()
        self.playerCore.delegate = self
        self.collectionManager = collectionManager
        
        loadPlaylist()
        
        setupBindings()
        logger.debug("PlayerViewModel initialized")
    }
    
    // MARK: - Private Methods
    
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
        
        Task {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            // 展开文件夹并收集所有音频文件
            var allAudioURLs: [URL] = []
            let fileManager = FileManager.default
            
            for url in urls {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                            while let fileURL = enumerator.nextObject() as? URL {
                                if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                                    allAudioURLs.append(fileURL)
                                }
                            }
                        }
                    } else if supportedExtensions.contains(url.pathExtension.lowercased()) {
                        allAudioURLs.append(url)
                    }
                }
            }
            
            guard !allAudioURLs.isEmpty else {
                logger.warning("No valid audio files found")
                return
            }
            
            // 排序策略：按父目录路径排序，同目录下按文件名排序
            let sortedURLs = allAudioURLs.sorted { lhs, rhs in
                let lhsDir = lhs.deletingLastPathComponent().path
                let rhsDir = rhs.deletingLastPathComponent().path
                if lhsDir != rhsDir {
                    return lhsDir < rhsDir
                }
                return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
            
            logger.info("Adding \(sortedURLs.count) tracks")
            
            let newTracks = await withTaskGroup(of: (Int, AudioTrack).self) { group in
                for (index, url) in sortedURLs.enumerated() {
                    group.addTask {
                        let track = await AudioTrack(url: url)
                        return (index, track)
                    }
                }
                
                var tracksWithIndex: [(Int, AudioTrack)] = []
                for await result in group {
                    tracksWithIndex.append(result)
                }
                // 恢复原始排序顺序
                return tracksWithIndex.sorted { $0.0 < $1.0 }.map(\.1)
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
            
            savePlaylist()
            
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            logger.logPerformance("Add \(newTracks.count) tracks", duration: elapsed)
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
        
        savePlaylist()
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
        
        logger.info("🗑 Cleared \(count) tracks")
        
        savePlaylist()
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
        
        savePlaylist()
    }
    
    func playTrack(at index: Int) {
        guard playlist.indices.contains(index) else { return }
        
        playingSource = .playlist
        currentTracks = playlist
        
        loadAndPlay(at: index)
    }
    
    func playAlbum(_ album: Album, startAt index: Int = 0) {
        guard !album.tracks.isEmpty else {
            logger.warning("Cannot play empty album: \(album.name)")
            return
        }
        
        playingSource = .album(album.id)
        currentTracks = album.tracks
        
        logger.info("📀 Playing album: \(album.name) (\(album.tracks.count) tracks)")
        
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
            savePlaylist()
        }
    }
    
    // MARK: - Persistence
    
    private func savePlaylist() {
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
            try persistenceService.save(state)
            logger.debug("💾 Playlist saved (\(state.tracks.count) tracks)")
        } catch {
            let appError = AppError.persistenceFailed("save playlist")
            logger.logError(appError, context: "savePlaylist")
        }
    }
 
    private func loadPlaylist() {
        guard let state = try? persistenceService.load() else {
            logger.notice("No saved playlist found")
            return
        }
        
        playlist = state.tracks
        
        if let source = state.playingSource {
            switch source {
            case .playlist:
                playingSource = .playlist
                currentTracks = playlist
                currentTrackIndex = nil
                
                if let savedIndex = state.playlistCurrentIndex,
                   playlist.indices.contains(savedIndex)
                {
                    currentTrackIndex = savedIndex
                    
                    Task {
                        await loadTrack(at: savedIndex)
                    }
                    
                    logger.info("📋 Restored playlist: track \(savedIndex + 1)/\(self.playlist.count)")
                }
                
            case .album(let albumId):
                // 只加载需要的单个专辑，不触发整个 collections 加载
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
                            
                            logger.info("📀 Restored album: \(album.name) - track \(albumIndex + 1)")
                        } else {
                            await MainActor.run {
                                self.playingSource = .playlist
                                self.currentTracks = self.playlist
                                self.currentTrackIndex = nil
                            }
                            logger.warning("Album or track not found, fallback to playlist")
                        }
                    }
                } else {
                    playingSource = .playlist
                    currentTracks = playlist
                    currentTrackIndex = nil
                }
            }
        } else {
            playingSource = .playlist
            currentTracks = playlist
            currentTrackIndex = nil
        }
        
        logger.info("📋 Loaded \(state.tracks.count) tracks")
        isPlaylistLoaded = true
    }
}

// MARK: - AudioPlayerCore Delegate

extension PlayerViewModel: AudioPlayerCoreDelegate {
    func playerCore(_ core: AudioPlayerCore, didUpdatePlaybackState isPlaying: Bool) {
        self.isPlaying = isPlaying
    }
    
    func playerCore(_ core: AudioPlayerCore, didUpdateTime currentTime: TimeInterval, duration: TimeInterval) {
        self.currentTime = currentTime
        self.duration = duration
    }
    
    func playerCore(_ core: AudioPlayerCore, didLoadTrack track: AudioTrack, artwork: NSImage?) {
        self.currentArtwork = artwork
    }
    
    func playerCore(_ core: AudioPlayerCore, didEncounterError error: Error) {
        logger.logError(error, context: "PlayerCore")
    }
    
    func playerCoreDidReachEnd(_ core: AudioPlayerCore) {
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
