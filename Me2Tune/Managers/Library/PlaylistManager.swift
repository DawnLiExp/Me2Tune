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
    let urlString: String
}

// MARK: - Add Tracks Result

struct AddTracksResult {
    /// 实际新增的曲目数量
    let newTracksCount: Int
    /// 第一首新增曲目在 entries 中的索引（nil 表示无新增）
    let firstNewTrackIndex: Int?
    /// 已有曲目的 URL 到 entries 索引的映射
    let existingTrackIndices: [URL: Int]
    private(set) var failure: AppError? = nil
}

@MainActor
@Observable
final class PlaylistManager {
    // MARK: - Published States

    private var entries: [PlaylistEntry] = []
    var isLoading: Bool { loadingCount > 0 }
    private(set) var loadingCount = 0

    // MARK: - Private Properties

    private let dataService: DataServiceProtocol
    private let metadataLoader: @Sendable ([URL]) async -> [AudioTrack]

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

    init(
        dataService: DataServiceProtocol = DataService.shared,
        metadataLoader: @escaping @Sendable ([URL]) async -> [AudioTrack] = {
            await AudioTrack.readForPlaylistImport($0)
        }
    ) {
        self.dataService = dataService
        self.metadataLoader = metadataLoader
        loadPlaylistContent()
        logger.debug("✅ PlaylistManager initialized (SwiftData)")
    }

    // MARK: - Public Methods - Query

    func track(at index: Int) -> AudioTrack? {
        entries.indices.contains(index) ? entries[index].track : nil
    }

    func index(of track: AudioTrack) -> Int? {
        index(ofID: track.id)
    }

    func index(ofID id: UUID) -> Int? {
        entries.firstIndex(where: { $0.track.id == id })
    }

    func refreshTrackMetadata(_ track: AudioTrack) {
        for index in entries.indices where entries[index].track.id == track.id {
            entries[index] = PlaylistEntry(track: track, urlString: track.url.absoluteString)
        }
    }

    // MARK: - Public Methods - Add

    @discardableResult
    func addTracks(urls: [URL]) async -> AddTracksResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        let allAudioURLs = expandAndFilterAudioURLs(urls)

        guard !allAudioURLs.isEmpty else {
            logger.warning("No valid audio files found")
            return AddTracksResult(newTracksCount: 0, firstNewTrackIndex: nil, existingTrackIndices: [:])
        }

        var seen: Set<String> = []
        let sortedURLs = sortURLsByDirectory(allAudioURLs.filter { seen.insert($0.absoluteString).inserted })

        // Build URL lookup for deduplication against current entries
        let existingURLMap: [String: Int] = Dictionary(
            entries.enumerated().map { ($1.urlString, $0) },
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

        guard !newURLs.isEmpty else {
            // All files already exist in playlist
            logger.info("All \(sortedURLs.count) tracks already in playlist")
            return AddTracksResult(newTracksCount: 0, firstNewTrackIndex: nil, existingTrackIndices: existingTrackIndices)
        }

        logger.info("Adding \(newURLs.count) new tracks (\(existingTrackIndices.count) already in playlist)")

        let pendingCount = newURLs.count
        loadingCount += pendingCount
        defer { loadingCount -= pendingCount }

        let loadedTracks = await metadataLoader(newURLs)
        let currentURLMap: [String: Int] = Dictionary(
            entries.enumerated().map { ($1.urlString, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        existingTrackIndices = [:]
        for url in sortedURLs {
            if let index = currentURLMap[url.absoluteString] {
                existingTrackIndices[url] = index
            }
        }
        let newDTOTracks = loadedTracks.filter { currentURLMap[$0.url.absoluteString] == nil }
        guard !newDTOTracks.isEmpty else {
            return AddTracksResult(newTracksCount: 0, firstNewTrackIndex: nil, existingTrackIndices: existingTrackIndices)
        }
        let writer = dataService.makeLibraryWriter()
        let baseOrder = entries.count
        var newEntries: [PlaylistEntry] = []
        do {
            var records = try writer.findTracks(byURLs: newDTOTracks.map { $0.url.absoluteString })
            for dto in newDTOTracks {
                let key = dto.url.absoluteString
                let record: SDTrack
                if let existing = records[key] {
                    record = existing
                } else {
                    record = SDTrack(from: dto)
                    writer.insert(record)
                    records[key] = record
                }
                record.isInPlaylist = true
                record.playlistOrder = baseOrder + newEntries.count
                newEntries.append(PlaylistEntry(track: record.toAudioTrack(), urlString: record.urlString))
            }
            try writer.save()
        } catch {
            logger.logError(error, context: "addTracks")
            return AddTracksResult(newTracksCount: 0, firstNewTrackIndex: nil,
                                   existingTrackIndices: existingTrackIndices, failure: error)
        }

        entries.append(contentsOf: newEntries)
        logger.logPerformance("Add \(newEntries.count) tracks", duration: CFAbsoluteTimeGetCurrent() - startTime)
        return AddTracksResult(newTracksCount: newEntries.count, firstNewTrackIndex: baseOrder,
                               existingTrackIndices: existingTrackIndices)
    }

    // MARK: - Public Methods - Remove

    func removeTrack(at index: Int) throws(AppError) {
        guard entries.indices.contains(index) else { return }
        let writer = dataService.makeLibraryWriter()
        let affected = try records(for: entries[index...], using: writer)
        removeFromPlaylist(affected[0], using: writer)
        for (offset, record) in affected.dropFirst().enumerated() {
            record.playlistOrder = index + offset
        }
        try writer.save()
        entries.remove(at: index)
    }

    func clearAll() throws(AppError) {
        guard !entries.isEmpty else { return }
        let writer = dataService.makeLibraryWriter()
        for record in try records(for: entries[...], using: writer) {
            removeFromPlaylist(record, using: writer)
        }
        try writer.save()
        entries.removeAll()
    }

    private func removeFromPlaylist(_ record: SDTrack, using writer: any DataServiceProtocol) {
        record.isInPlaylist = false
        record.playlistOrder = nil
        if record.albumEntries.isEmpty { writer.delete(record) }
    }

    func moveTrack(from source: Int, to destination: Int) throws(AppError) {
        guard entries.indices.contains(source), entries.indices.contains(destination), source != destination else { return }
        let start = min(source, destination)
        let range = start...max(source, destination)
        var reordered = Array(entries[range])
        let moved = reordered.remove(at: source - start)
        reordered.insert(moved, at: destination - start)

        let writer = dataService.makeLibraryWriter()
        for (offset, record) in try records(for: reordered[...], using: writer).enumerated() {
            record.playlistOrder = start + offset
        }
        try writer.save()
        entries.replaceSubrange(range, with: reordered)
    }

    private func records(for entries: ArraySlice<PlaylistEntry>, using writer: any DataServiceProtocol) throws(AppError) -> [SDTrack] {
        let byURL = try writer.findTracks(byURLs: entries.map(\.urlString))
        var result: [SDTrack] = []
        for entry in entries {
            guard let record = byURL[entry.urlString], record.stableId == entry.track.id else {
                throw .persistenceFailed("update playlist")
            }
            result.append(record)
        }
        return result
    }

    // MARK: - Private Methods - Persistence

    private func loadPlaylistContent() {
        do {
            let sdTracks = try dataService.fetchPlaylistTracks()
            entries = sdTracks.map { PlaylistEntry(track: $0.toAudioTrack(), urlString: $0.urlString) }
            logger.info("📋 Loaded \(sdTracks.count) playlist tracks")
        } catch {
            logger.notice("No saved playlist content found")
        }
    }

    // MARK: - Private Methods - URL Processing

    private func expandAndFilterAudioURLs(_ urls: [URL]) -> [URL] {
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
                            if AudioFileSupport.isSupportedAudioFile(fileURL) {
                                allAudioURLs.append(fileURL)
                            }
                        }
                    }
                } else if AudioFileSupport.isSupportedAudioFile(url) {
                    allAudioURLs.append(url)
                }
            }
        }

        return allAudioURLs
    }

    private func sortURLsByDirectory(_ urls: [URL]) -> [URL] {
        let keys = urls.map { url in
            (url: url, directory: url.deletingLastPathComponent().path, filename: url.lastPathComponent)
        }
        return keys.sorted { lhs, rhs in
            if lhs.directory != rhs.directory {
                return lhs.directory < rhs.directory
            }
            return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
        }.map(\.url)
    }
}
