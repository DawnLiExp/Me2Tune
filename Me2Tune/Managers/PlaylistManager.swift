//
//  PlaylistManager.swift
//  Me2Tune
//
//  播放列表管理 - SwiftData 版本，增删改查 + 自动持久化
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

    private let dataService = DataService.shared

    // In-memory index: UUID → SDTrack for fast lookup during drag operations
    private var trackIndex: [UUID: SDTrack] = [:]

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
        logger.debug("✅ PlaylistManager initialized (SwiftData)")
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

        let newDTOTracks = await loadTracksFromURLs(sortedURLs)
        let maxOrder = tracks.count

        for (offset, dto) in newDTOTracks.enumerated() {
            let sdTrack: SDTrack
            if let existing = dataService.findTrack(byURL: dto.url.absoluteString) {
                sdTrack = existing
            } else {
                sdTrack = SDTrack(from: dto)
                dataService.insert(sdTrack)
            }
            sdTrack.isInPlaylist = true
            sdTrack.playlistOrder = maxOrder + offset

            updateTrackIndex(sdTrack)
        }

        try? dataService.save()

        // Directly append to memory, avoid full reload
        tracks.append(contentsOf: newDTOTracks)

        isLoading = false
        loadingCount = 0

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger.logPerformance("Add \(newDTOTracks.count) tracks", duration: elapsed)
    }

    // MARK: - Public Methods - Remove

    func removeTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }

        let track = tracks.remove(at: index)

        if let sdTrack = trackIndex[track.id] ?? dataService.findTrack(byURL: track.url.absoluteString) {
            sdTrack.isInPlaylist = false
            sdTrack.playlistOrder = nil

            if sdTrack.albumEntries.isEmpty {
                dataService.delete(sdTrack)
                removeTrackIndex(for: track.id)
            }
        }

        reindexPlaylistOrdersOptimized(removedAt: index)

        try? dataService.save()
    }

    func clearAll() {
        do {
            let sdTracks = try dataService.fetchPlaylistTracks()
            for sdTrack in sdTracks {
                sdTrack.isInPlaylist = false
                sdTrack.playlistOrder = nil
                if sdTrack.albumEntries.isEmpty {
                    dataService.delete(sdTrack)
                }
            }
            try dataService.save()
        } catch {
            logger.logError(AppError.persistenceFailed("clear playlist"), context: "clearAll")
        }

        tracks.removeAll()
        clearTrackIndex()
        logger.info("🗑️ Cleared playlist")
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

        reindexPlaylistOrdersOptimized(movedFrom: source, to: destination)

        try? dataService.save()
        logger.debug("Moved track from \(source) to \(destination)")
    }

    // MARK: - Index Management

    private func updateTrackIndex(_ sdTrack: SDTrack) {
        trackIndex[sdTrack.stableId] = sdTrack
    }

    private func removeTrackIndex(for id: UUID) {
        trackIndex.removeValue(forKey: id)
    }

    private func rebuildTrackIndex(from sdTracks: [SDTrack]) {
        trackIndex.removeAll(keepingCapacity: true)
        for sdTrack in sdTracks {
            trackIndex[sdTrack.stableId] = sdTrack
        }
    }

    private func clearTrackIndex() {
        trackIndex.removeAll()
    }

    // MARK: - Private Methods - Persistence

    private func loadPlaylistContent() {
        do {
            let sdTracks = try dataService.fetchPlaylistTracks()
            rebuildTrackIndex(from: sdTracks)
            tracks = sdTracks.map { $0.toAudioTrack() }
            logger.info("📋 Loaded \(sdTracks.count) playlist tracks")
        } catch {
            logger.notice("No saved playlist content found")
        }
    }

    // Only update affected range after deletion
    private func reindexPlaylistOrdersOptimized(removedAt removedIndex: Int) {
        for i in removedIndex ..< tracks.count {
            let trackId = tracks[i].id
            if let sdTrack = trackIndex[trackId] {
                sdTrack.playlistOrder = i
            }
        }
    }

    // Only update affected range during drag
    private func reindexPlaylistOrdersOptimized(movedFrom source: Int, to destination: Int) {
        let start = min(source, destination)
        let end = max(source, destination)

        for i in start ... end {
            let trackId = tracks[i].id
            if let sdTrack = trackIndex[trackId] {
                sdTrack.playlistOrder = i
            }
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
