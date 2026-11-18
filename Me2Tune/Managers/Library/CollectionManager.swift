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
import SwiftData

private let logger = Logger.collection

struct AlbumImportFailure {
    let folder: URL
    let error: AppError
}

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

    func refreshTrackMetadata(_ track: AudioTrack) {
        for albumIndex in albums.indices {
            for trackIndex in albums[albumIndex].tracks.indices where albums[albumIndex].tracks[trackIndex].id == track.id {
                albums[albumIndex].tracks[trackIndex] = track
            }
        }
    }

    func scheduleDelayedLoad(delay: TimeInterval = 0.5) {
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

        return sdAlbum(for: id)?.toAlbum()
    }

    // MARK: - Album Management

    func addAlbumFromPlaylist(name: String, tracks: [AudioTrack]) async throws(AppError) -> UUID? {
        await ensureLoaded()

        guard !tracks.isEmpty else {
            logger.warning("Cannot create album from empty playlist")
            return nil
        }

        return try createAlbum(name: name, folderURL: nil, tracks: tracks)?.id
    }

    @discardableResult
    func addAlbum(from url: URL) async -> [AlbumImportFailure] {
        await ensureLoaded()
        var failures: [AlbumImportFailure] = []
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            await scanAndAddAlbums(at: url, failures: &failures)
        } else {
            await importAudioFiles(in: url.deletingLastPathComponent(), failures: &failures)
        }
        return failures
    }

    private func scanAndAddAlbums(at url: URL, failures: inout [AlbumImportFailure]) async {
        await importAudioFiles(in: url, failures: &failures)
        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        for item in contents {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory), isDirectory.boolValue {
                await scanAndAddAlbums(at: item, failures: &failures)
            }
        }
    }

    private func importAudioFiles(in folder: URL, failures: inout [AlbumImportFailure]) async {
        guard !albums.contains(where: { $0.folderURL?.path == folder.path }) else { return }
        let urls = scanFolderOnly(folder)
        guard !urls.isEmpty else { return }
        let tracks = await loadTracksFromURLs(urls)
        do {
            _ = try createAlbum(name: folder.lastPathComponent, folderURL: folder, tracks: tracks)
        } catch {
            failures.append(AlbumImportFailure(folder: folder, error: error))
        }
    }

    private func createAlbum(name: String, folderURL: URL?, tracks: [AudioTrack]) throws(AppError) -> Album? {
        let writer = dataService.makeLibraryWriter()
        if let folderURL {
            let key = folderURL.absoluteString
            let descriptor = FetchDescriptor<SDAlbum>(predicate: #Predicate { $0.folderURLString == key })
            // Another import may have committed this folder while metadata was loading.
            if albums.contains(where: { $0.folderURL?.path == folderURL.path }) { return nil }
            if try writer.fetchCount(descriptor) > 0 { return nil }
        }

        var byURL = try writer.findTracks(byURLs: tracks.map { $0.url.absoluteString })
        let stored = SDAlbum(name: name, folderURLString: folderURL?.absoluteString, displayOrder: albums.count)
        writer.insert(stored)
        for (index, track) in tracks.enumerated() {
            let key = track.url.absoluteString
            let record: SDTrack
            if let existing = byURL[key] {
                record = existing
            } else {
                record = SDTrack(from: track)
                writer.insert(record)
                byURL[key] = record
            }
            writer.insert(SDAlbumTrackEntry(trackOrder: index, album: stored, track: record))
        }
        try writer.save()
        let album = stored.toAlbum()
        albums.append(album)
        logger.info("Added album: \(name) (\(tracks.count) tracks)")
        return album
    }

    func removeAlbum(id: UUID) throws(AppError) {
        let writer = dataService.makeLibraryWriter()
        if let stored = try storedAlbum(id, using: writer) {
            try deleteAlbums([stored], using: writer)
        }
        albums.removeAll { $0.id == id }
    }

    func renameAlbum(id: UUID, newName: String) throws(AppError) {
        guard let index = albums.firstIndex(where: { $0.id == id }), albums[index].name != newName else { return }
        let writer = dataService.makeLibraryWriter()
        guard let stored = try storedAlbum(id, using: writer) else { throw .persistenceFailed("rename album") }
        stored.name = newName
        try writer.save()
        albums[index].name = newName
    }

    func moveAlbum(from source: Int, to destination: Int) throws(AppError) {
        guard albums.indices.contains(source), albums.indices.contains(destination), source != destination else { return }
        let start = min(source, destination)
        let range = start...max(source, destination)
        var reordered = Array(albums[range])
        let moved = reordered.remove(at: source - start)
        reordered.insert(moved, at: destination - start)
        let writer = dataService.makeLibraryWriter()
        for (offset, album) in reordered.enumerated() {
            guard let stored = try storedAlbum(album.id, using: writer) else { throw .persistenceFailed("reorder albums") }
            stored.displayOrder = start + offset
        }
        try writer.save()
        albums.replaceSubrange(range, with: reordered)
    }

    func clearAllAlbums() throws(AppError) {
        let writer = dataService.makeLibraryWriter()
        try deleteAlbums(writer.fetchAlbums(), using: writer)
        albums.removeAll()
    }

    private func storedAlbum(_ id: UUID, using writer: any DataServiceProtocol) throws(AppError) -> SDAlbum? {
        var descriptor = FetchDescriptor<SDAlbum>(predicate: #Predicate { $0.stableId == id })
        descriptor.fetchLimit = 1
        return try writer.fetch(descriptor).first
    }

    private func deleteAlbums(_ stored: [SDAlbum], using writer: any DataServiceProtocol) throws(AppError) {
        let removedIDs = Set(stored.map(\.stableId))
        var candidates: [UUID: SDTrack] = [:]
        for album in stored {
            for entry in album.trackEntries {
                if let track = entry.track, !track.isInPlaylist { candidates[track.stableId] = track }
            }
        }
        for track in candidates.values where track.albumEntries.allSatisfy({ entry in
            entry.album.map { removedIDs.contains($0.stableId) } ?? true
        }) {
            writer.delete(track)
        }
        for album in stored { writer.delete(album) }
        try writer.save()
    }

    // MARK: - Private Methods

    private func sdAlbum(for id: UUID) -> SDAlbum? {
        dataService.findAlbum(byStableId: id)
    }

    private func loadCollections() async {
        do {
            let sdAlbums = try dataService.fetchAlbums()
            self.albums = sdAlbums.map { $0.toAlbum() }
            logger.info("Loaded \(self.albums.count) albums")
        } catch {
            logger.notice("No existing collections to load")
        }
    }

    // MARK: - File Scanning

    private func scanFolderOnly(_ folderURL: URL) -> [URL] {
        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)) ?? []

        return contents.filter { url in
            AudioFileSupport.isSupportedAudioFile(url)
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
