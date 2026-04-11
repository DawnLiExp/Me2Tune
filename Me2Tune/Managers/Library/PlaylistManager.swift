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

// MARK: - Playlist Entry

private struct PlaylistEntry {
    var track: AudioTrack
    let sdTrack: SDTrack
}

// MARK: - Add Tracks Result

struct AddTracksResult {
    /// 实际新增的曲目数量
    let newTracksCount: Int
    /// 第一首新增曲目在 entries 中的索引（nil 表示无新增）
    let firstNewTrackIndex: Int?
    /// 已有曲目的 URL 到 entries 索引的映射
    let existingTrackIndices: [URL: Int]
}

@MainActor
@Observable
final class PlaylistManager {
    // MARK: - Published States

    private var entries: [PlaylistEntry] = []
    private(set) var isLoading = false
    private(set) var loadingCount = 0

    // MARK: - Private Properties

    private let dataService: DataServiceProtocol

    // MARK: - Computed Properties

    var tracks: [AudioTrack] {
        entries.map(\.track)
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    var count: Int {
        entries.count
    }

    // MARK: - Initialization

    init(dataService: DataServiceProtocol = DataService.shared) {
        self.dataService = dataService
        loadPlaylistContent()
        logger.debug("✅ PlaylistManager initialized (SwiftData)")
    }

    // MARK: - Public Methods - Query

    func track(at index: Int) -> AudioTrack? {
        entries.indices.contains(index) ? entries[index].track : nil
    }

    func index(of track: AudioTrack) -> Int? {
        entries.firstIndex(where: { $0.track.id == track.id })
    }

    // MARK: - Public Methods - Add

    @discardableResult
    func addTracks(urls: [URL]) async -> AddTracksResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        isLoading = true

        let allAudioURLs = expandAndFilterAudioURLs(urls)

        guard !allAudioURLs.isEmpty else {
            logger.warning("No valid audio files found")
            isLoading = false
            return AddTracksResult(newTracksCount: 0, firstNewTrackIndex: nil, existingTrackIndices: [:])
        }

        let sortedURLs = sortURLsByDirectory(allAudioURLs)

        // Build URL lookup for deduplication against current entries
        let existingURLMap: [String: Int] = Dictionary(
            entries.enumerated().map { ($1.sdTrack.urlString, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Separate new URLs from existing ones
        var existingTrackIndices: [URL: Int] = [:]
        var newURLs: [URL] = []

        for url in sortedURLs {
            if let existingIndex = existingURLMap[url.absoluteString] {
                existingTrackIndices[url] = existingIndex
            } else {
                newURLs.append(url)
            }
        }

        // Only load metadata for truly new URLs
        loadingCount = newURLs.count

        guard !newURLs.isEmpty else {
            // All files already exist in playlist
            logger.info("All \(sortedURLs.count) tracks already in playlist")
            isLoading = false
            loadingCount = 0
            return AddTracksResult(newTracksCount: 0, firstNewTrackIndex: nil, existingTrackIndices: existingTrackIndices)
        }

        logger.info("Adding \(newURLs.count) new tracks (\(existingTrackIndices.count) already in playlist)")

        let newDTOTracks = await loadTracksFromURLs(newURLs)
        let baseOrder = entries.count
        var newEntries: [PlaylistEntry] = []

        for (offset, dto) in newDTOTracks.enumerated() {
            let sdTrack: SDTrack
            if let existing = dataService.findTrack(byURL: dto.url.absoluteString) {
                sdTrack = existing
            } else {
                sdTrack = SDTrack(from: dto)
                dataService.insert(sdTrack)
            }
            sdTrack.isInPlaylist = true
            sdTrack.playlistOrder = baseOrder + offset
            newEntries.append(PlaylistEntry(track: sdTrack.toAudioTrack(), sdTrack: sdTrack))
        }

        do {
            try dataService.save()
        } catch {
            logger.logError(error, context: "addTracks")
        }

        entries.append(contentsOf: newEntries)

        let firstNewIndex = newEntries.isEmpty ? nil : baseOrder

        isLoading = false
        loadingCount = 0

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger.logPerformance("Add \(newEntries.count) tracks", duration: elapsed)

        return AddTracksResult(
            newTracksCount: newEntries.count,
            firstNewTrackIndex: firstNewIndex,
            existingTrackIndices: existingTrackIndices
        )
    }

    // MARK: - Public Methods - Remove

    func removeTrack(at index: Int) {
        guard entries.indices.contains(index) else { return }

        let entry = entries.remove(at: index)
        let sdTrack = entry.sdTrack
        sdTrack.isInPlaylist = false
        sdTrack.playlistOrder = nil

        if sdTrack.albumEntries.isEmpty {
            dataService.delete(sdTrack)
        }

        for i in index ..< entries.count {
            entries[i].sdTrack.playlistOrder = i
        }

        try? dataService.save()
    }

    func clearAll() {
        for entry in entries {
            let sdTrack = entry.sdTrack
            sdTrack.isInPlaylist = false
            sdTrack.playlistOrder = nil
            if sdTrack.albumEntries.isEmpty {
                dataService.delete(sdTrack)
            }
        }

        do {
            try dataService.save()
        } catch {
            logger.logError(error, context: "clearAll")
        }

        entries.removeAll()
        logger.info("🗑️ Cleared playlist")
    }

    // MARK: - Public Methods - Reorder

    func moveTrack(from source: Int, to destination: Int) {
        guard entries.indices.contains(source),
              entries.indices.contains(destination),
              source != destination
        else {
            return
        }

        let movedEntry = entries.remove(at: source)
        entries.insert(movedEntry, at: destination)

        let start = min(source, destination)
        let end = max(source, destination)
        for i in start ... end {
            entries[i].sdTrack.playlistOrder = i
        }

        try? dataService.save()
        logger.debug("Moved track from \(source) to \(destination)")
    }

    // MARK: - Private Methods - Persistence

    private func loadPlaylistContent() {
        do {
            let sdTracks = try dataService.fetchPlaylistTracks()
            entries = sdTracks.map { PlaylistEntry(track: $0.toAudioTrack(), sdTrack: $0) }
            logger.info("📋 Loaded \(sdTracks.count) playlist tracks")
        } catch {
            logger.notice("No saved playlist content found")
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
