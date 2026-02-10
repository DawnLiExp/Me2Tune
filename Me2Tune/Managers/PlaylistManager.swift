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

        // 读取元数据
        let newDTOTracks = await loadTracksFromURLs(sortedURLs)

        // 当前最大 playlistOrder
        let maxOrder = tracks.count

        // 插入/更新 SwiftData
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
        }

        try? dataService.save()

        // 重新加载
        loadPlaylistContent()

        isLoading = false
        loadingCount = 0

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger.logPerformance("Add \(newDTOTracks.count) tracks", duration: elapsed)
    }

    // MARK: - Public Methods - Remove

    func removeTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }

        let track = tracks[index]
        if let sdTrack = dataService.findTrack(byURL: track.url.absoluteString) {
            sdTrack.isInPlaylist = false
            sdTrack.playlistOrder = nil

            // 如果不属于任何专辑，删除 SDTrack
            if sdTrack.albumEntries.isEmpty {
                dataService.delete(sdTrack)
            }
        }

        // 重建 playlistOrder
        reindexPlaylistOrders(removedAt: index)

        try? dataService.save()
        loadPlaylistContent()
    }

    func clearAll() {
        do {
            let sdTracks = try dataService.fetchPlaylistTracks()
            for sdTrack in sdTracks {
                sdTrack.isInPlaylist = false
                sdTrack.playlistOrder = nil
                // 如果不属于任何专辑，删除
                if sdTrack.albumEntries.isEmpty {
                    dataService.delete(sdTrack)
                }
            }
            try dataService.save()
        } catch {
            logger.logError(AppError.persistenceFailed("clear playlist"), context: "clearAll")
        }

        tracks.removeAll()
        logger.info("🗑 Cleared playlist")
    }

    // MARK: - Public Methods - Reorder

    func moveTrack(from source: Int, to destination: Int) {
        guard tracks.indices.contains(source),
              tracks.indices.contains(destination),
              source != destination
        else {
            return
        }

        // 内存中移动
        let movedTrack = tracks.remove(at: source)
        tracks.insert(movedTrack, at: destination)

        // 更新所有 playlistOrder
        reindexAllPlaylistOrders()

        try? dataService.save()
        logger.debug("Moved track from \(source) to \(destination)")
    }

    // MARK: - Private Methods - Persistence

    private func loadPlaylistContent() {
        do {
            let sdTracks = try dataService.fetchPlaylistTracks()
            tracks = sdTracks.map { $0.toAudioTrack() }
            logger.info("📋 Loaded \(sdTracks.count) playlist tracks")
        } catch {
            logger.notice("No saved playlist content found")
        }
    }

    private func reindexPlaylistOrders(removedAt removedIndex: Int) {
        do {
            let sdTracks = try dataService.fetchPlaylistTracks()
            for (newOrder, sdTrack) in sdTracks.enumerated() {
                sdTrack.playlistOrder = newOrder
            }
        } catch {
            logger.warning("Failed to reindex playlist orders")
        }
    }

    private func reindexAllPlaylistOrders() {
        for (newOrder, track) in tracks.enumerated() {
            if let sdTrack = dataService.findTrack(byURL: track.url.absoluteString) {
                sdTrack.playlistOrder = newOrder
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
