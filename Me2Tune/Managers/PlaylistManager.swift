//
//  PlaylistManager.swift
//  Me2Tune
//
//  播放列表管理 - 增删改查 + 持久化
//

import Foundation
import Observation
import OSLog

private let logger = Logger.viewModel

@MainActor
@Observable
final class PlaylistManager {
    // MARK: - Published States
    
    private(set) var tracks: [AudioTrack] = []
    private(set) var isLoading = false
    private(set) var loadingCount = 0
    
    // MARK: - Private Properties
    
    private let persistenceService = PersistenceService.shared
    
    // MARK: - Computed Properties
    
    var isEmpty: Bool {
        tracks.isEmpty
    }
    
    var count: Int {
        tracks.count
    }
    
    // MARK: - Initialization
    
    init() {
        loadPlaylistContent()
        logger.debug("✅ PlaylistManager initialized (@Observable)")
    }
    
    // MARK: - Public Methods - Query
    
    func track(at index: Int) -> AudioTrack? {
        tracks.indices.contains(index) ? tracks[index] : nil
    }
    
    func index(of track: AudioTrack) -> Int? {
        tracks.firstIndex(where: { $0.id == track.id })
    }
    
    // MARK: - Public Methods - Add
    
    func addTracks(urls: [URL]) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        isLoading = true
        
        let allAudioURLs = expandAndFilterAudioURLs(urls)
        
        guard !allAudioURLs.isEmpty else {
            logger.warning("No valid audio files found")
            isLoading = false
            return
        }
        
        let sortedURLs = sortURLsByDirectory(allAudioURLs)
        loadingCount = sortedURLs.count
        
        logger.info("Adding \(sortedURLs.count) tracks")
        
        let newTracks = await loadTracksFromURLs(sortedURLs)
        tracks.append(contentsOf: newTracks)
        
        savePlaylistContent()
        
        isLoading = false
        loadingCount = 0
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger.logPerformance("Add \(newTracks.count) tracks", duration: elapsed)
    }
    
    // MARK: - Public Methods - Remove
    
    func removeTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        
        tracks.remove(at: index)
        savePlaylistContent()
    }
    
    func clearAll() {
        let count = tracks.count
        tracks.removeAll()
        
        logger.info("🗑 Cleared \(count) tracks")
        savePlaylistContent()
    }
    
    // MARK: - Public Methods - Reorder
    
    func moveTrack(from source: Int, to destination: Int) {
        guard tracks.indices.contains(source),
              tracks.indices.contains(destination),
              source != destination
        else {
            return
        }
        
        let movedTrack = tracks.remove(at: source)
        tracks.insert(movedTrack, at: destination)
        
        logger.debug("Moved track from \(source) to \(destination)")
        savePlaylistContent()
    }
    
    // MARK: - Private Methods - Persistence
    
    private func loadPlaylistContent() {
        if let content = try? persistenceService.loadPlaylistContent() {
            tracks = content.tracks
            logger.info("📋 Loaded \(content.tracks.count) tracks")
        } else {
            logger.notice("No saved playlist content found")
        }
    }
    
    private func savePlaylistContent() {
        let content = PlaylistContent(tracks: tracks)
        
        do {
            try persistenceService.savePlaylistContent(content)
        } catch {
            let appError = AppError.persistenceFailed("save playlist content")
            logger.logError(appError, context: "savePlaylistContent")
        }
    }
    
    // MARK: - Private Methods - URL Processing
    
    private func expandAndFilterAudioURLs(_ urls: [URL]) -> [URL] {
        let supportedExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ape", "wv", "tta", "mpc"]
        let fileManager = FileManager.default
        var allAudioURLs: [URL] = []
        
        for url in urls {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    if let enumerator = fileManager.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles]
                    ) {
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
        
        return allAudioURLs
    }
    
    private func sortURLsByDirectory(_ urls: [URL]) -> [URL] {
        urls.sorted { lhs, rhs in
            let lhsDir = lhs.deletingLastPathComponent().path
            let rhsDir = rhs.deletingLastPathComponent().path
            if lhsDir != rhsDir {
                return lhsDir < rhsDir
            }
            return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }
    }
    
    private func loadTracksFromURLs(_ urls: [URL]) async -> [AudioTrack] {
        await withTaskGroup(of: (Int, AudioTrack).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    let track = await AudioTrack(url: url)
                    return (index, track)
                }
            }
            
            var tracksWithIndex: [(Int, AudioTrack)] = []
            for await result in group {
                tracksWithIndex.append(result)
            }
            return tracksWithIndex.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
