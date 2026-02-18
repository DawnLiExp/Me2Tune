//
//  CollectionManager.swift
//  Me2Tune
//
//  专辑收藏管理 - SwiftData 版本 + 延迟加载优化 + 拖拽排序
//

import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI

private let logger = Logger.collection

@MainActor
@Observable
final class CollectionManager {
    // MARK: - Published States

    private(set) var albums: [Album] = []
    private(set) var isLoaded = false
    private(set) var isLoading = false

    var lastScrollAlbumId: UUID?

    // MARK: - Private Properties

    private let dataService: DataServiceProtocol
    private var delayedLoadTask: Task<Void, Never>?

    // In-memory index: UUID → SDAlbum for fast lookup during drag operations
    private var albumIndex: [UUID: SDAlbum] = [:]

    // MARK: - Computed Properties

    var albumCount: Int {
        albums.count
    }

    // MARK: - Initialization

    init(dataService: DataServiceProtocol = DataService.shared) {
        self.dataService = dataService
        logger.debug("✅ CollectionManager initialized (SwiftData)")
    }

    // MARK: - Delayed Loading

    func scheduleDelayedLoad(delay: TimeInterval = 1.5) {
        guard delayedLoadTask == nil else {
            logger.debug("Delayed load already scheduled, skipping")
            return
        }

        delayedLoadTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                logger.debug("Delayed load cancelled")
                return
            }

            logger.info("⏰ Starting delayed collection load after \(delay)s sleep")
            await loadCollections()

            self.isLoaded = true
            self.delayedLoadTask = nil
        }
    }

    func populateWithSingleAlbum(_ album: Album) {
        guard !isLoaded else { return }

        if !albums.contains(where: { $0.id == album.id }) {
            albums.append(album)
        }
    }

    func ensureLoaded() async {
        guard !isLoaded else { return }

        if let task = delayedLoadTask {
            task.cancel()
            delayedLoadTask = nil
        }

        isLoading = true
        await loadCollections()
        isLoaded = true
        isLoading = false
    }

    // MARK: - Single Album Loading

    func loadSingleAlbum(id: UUID) async -> Album? {
        if let cached = albums.first(where: { $0.id == id }) {
            return cached
        }

        if let sdAlbum = albumIndex[id] {
            return sdAlbum.toAlbum()
        }

        // Precise query by stableId, avoid full scan
        if let sdAlbum = dataService.findAlbum(byStableId: id) {
            updateAlbumIndex(sdAlbum)
            return sdAlbum.toAlbum()
        }

        return nil
    }

    // MARK: - Album Management

    func addAlbumFromPlaylist(name: String, tracks: [AudioTrack]) async -> UUID? {
        await ensureLoaded()

        guard !tracks.isEmpty else {
            logger.warning("Cannot create album from empty playlist")
            return nil
        }

        let currentMaxOrder = albums.count
        let albumId = UUID()

        let sdAlbum = SDAlbum(
            name: name,
            folderURLString: nil,
            displayOrder: currentMaxOrder,
            stableId: albumId
        )
        dataService.insert(sdAlbum)

        for (order, dto) in tracks.enumerated() {
            let sdTrack: SDTrack
            if let existing = dataService.findTrack(byURL: dto.url.absoluteString) {
                sdTrack = existing
            } else {
                sdTrack = SDTrack(from: dto)
                dataService.insert(sdTrack)
            }

            let entry = SDAlbumTrackEntry(trackOrder: order, album: sdAlbum, track: sdTrack)
            dataService.insert(entry)
        }

        do {
            try dataService.save()
        } catch {
            logger.logError(error, context: "addAlbumFromPlaylist")
        }

        updateAlbumIndex(sdAlbum)

        // Build Album DTO directly from existing data, avoid re-conversion
        let album = Album(
            id: albumId,
            name: name,
            folderURL: nil,
            tracks: tracks
        )
        albums.append(album)

        logger.info("📀 Created album from playlist: \(name) (\(tracks.count) tracks)")
        return album.id
    }

    func addAlbum(from url: URL) async {
        await ensureLoaded()

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            let parentURL = url.deletingLastPathComponent()
            let audioFiles = scanFolderOnly(parentURL)
            if !audioFiles.isEmpty {
                await createAlbum(from: parentURL, audioURLs: audioFiles)
            }
            return
        }

        await scanAndAddAlbums(at: url)
    }

    private func scanAndAddAlbums(at url: URL) async {
        let fileManager = FileManager.default

        let audioFiles = scanFolderOnly(url)
        if !audioFiles.isEmpty {
            await createAlbum(from: url, audioURLs: audioFiles)
        }

        let contents = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        for item in contents {
            var isSubDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isSubDir), isSubDir.boolValue {
                await scanAndAddAlbums(at: item)
            }
        }
    }

    private func createAlbum(from url: URL, audioURLs: [URL]) async {
        if dataService.findAlbum(byFolderURL: url.absoluteString) != nil {
            logger.debug("Album already exists for path: \(url.path)")
            return
        }

        if albums.contains(where: { $0.folderURL?.path == url.path }) {
            logger.debug("Album already exists in memory: \(url.path)")
            return
        }

        let currentMaxOrder = albums.count
        let albumId = UUID()

        let sdAlbum = SDAlbum(
            name: url.lastPathComponent,
            folderURLString: url.absoluteString,
            displayOrder: currentMaxOrder,
            stableId: albumId
        )
        dataService.insert(sdAlbum)

        let trackDTOs = await loadTracksFromURLs(audioURLs)

        for (order, dto) in trackDTOs.enumerated() {
            let sdTrack: SDTrack
            if let existing = dataService.findTrack(byURL: dto.url.absoluteString) {
                sdTrack = existing
            } else {
                sdTrack = SDTrack(from: dto)
                dataService.insert(sdTrack)
            }

            let entry = SDAlbumTrackEntry(trackOrder: order, album: sdAlbum, track: sdTrack)
            dataService.insert(entry)
        }

        do {
            try dataService.save()
        } catch {
            logger.logError(error, context: "createAlbum")
        }

        updateAlbumIndex(sdAlbum)

        // Build Album DTO directly from existing data
        let album = Album(
            id: albumId,
            name: url.lastPathComponent,
            folderURL: url,
            tracks: trackDTOs
        )
        albums.append(album)

        logger.info("📀 Added album: \(album.name) (\(trackDTOs.count) tracks)")
    }

    func removeAlbum(id: UUID) {
        if let sdAlbum = albumIndex[id] {
            for entry in sdAlbum.trackEntries {
                if let track = entry.track, !track.isInPlaylist, track.albumEntries.count <= 1 {
                    dataService.delete(track)
                }
            }
            dataService.delete(sdAlbum)
            removeAlbumIndex(for: id)
            try? dataService.save()
        }

        albums.removeAll { $0.id == id }
        logger.info("Album removed: \(id)")
    }

    func renameAlbum(id: UUID, newName: String) {
        guard let index = albums.firstIndex(where: { $0.id == id }) else { return }

        let oldName = albums[index].name
        albums[index].name = newName

        if let sdAlbum = albumIndex[id] {
            sdAlbum.name = newName
            try? dataService.save()
        }

        logger.info("Album renamed: \(oldName) → \(newName)")
    }

    func moveAlbum(from source: Int, to destination: Int) {
        guard albums.indices.contains(source),
              albums.indices.contains(destination),
              source != destination
        else {
            return
        }

        let movedAlbum = albums.remove(at: source)
        albums.insert(movedAlbum, at: destination)

        reindexAlbumOrdersOptimized(source: source, destination: destination)

        try? dataService.save()
    }

    func clearAllAlbums() {
        do {
            let sdAlbums = try dataService.fetchAlbums()
            for sdAlbum in sdAlbums {
                for entry in sdAlbum.trackEntries {
                    if let track = entry.track, !track.isInPlaylist, track.albumEntries.count <= 1 {
                        dataService.delete(track)
                    }
                }
                dataService.delete(sdAlbum)
            }
            try dataService.save()
        } catch {
            logger.logError(error, context: "clearAllAlbums")
        }

        let count = albums.count
        albums.removeAll()
        clearAlbumIndex()
        logger.info("Cleared all \(count) albums")
    }

    // MARK: - Index Management

    private func updateAlbumIndex(_ sdAlbum: SDAlbum) {
        albumIndex[sdAlbum.stableId] = sdAlbum
    }

    private func removeAlbumIndex(for id: UUID) {
        albumIndex.removeValue(forKey: id)
    }

    private func rebuildAlbumIndex(from sdAlbums: [SDAlbum]) {
        albumIndex.removeAll(keepingCapacity: true)
        for sdAlbum in sdAlbums {
            albumIndex[sdAlbum.stableId] = sdAlbum
        }
    }

    private func clearAlbumIndex() {
        albumIndex.removeAll()
    }

    // MARK: - Private Methods

    private func loadCollections() async {
        do {
            let sdAlbums = try dataService.fetchAlbums()
            rebuildAlbumIndex(from: sdAlbums)
            self.albums = sdAlbums.map { $0.toAlbum() }
            logger.info("Loaded \(self.albums.count) albums")
        } catch {
            logger.notice("No existing collections to load")
        }
    }

    // Only update affected range during drag, avoid full re-conversion
    private func reindexAlbumOrdersOptimized(source: Int, destination: Int) {
        let start = min(source, destination)
        let end = max(source, destination)

        for i in start ... end {
            let albumId = albums[i].id
            if let sdAlbum = albumIndex[albumId] {
                sdAlbum.displayOrder = i
            }
        }
    }

    // MARK: - File Scanning

    private func scanFolderOnly(_ folderURL: URL) -> [URL] {
        let supportedExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ape", "wv", "tta", "mpc"]
        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)) ?? []

        return contents.filter { url in
            supportedExtensions.contains(url.pathExtension.lowercased())
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
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
