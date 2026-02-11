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

    /// 专辑收藏滚动到的记录 ID，用于在 Tab 切换时保持位置
    var lastScrollAlbumId: UUID?

    // MARK: - Private Properties

    private let dataService = DataService.shared
    private var delayedLoadTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var albumCount: Int {
        albums.count
    }

    // MARK: - Initialization

    init() {
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

    /// Preload a single album without marking full load completion
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
        // 先查内存缓存
        if let cached = albums.first(where: { $0.id == id }) {
            return cached
        }

        // 从 SwiftData 查找 - 通过遍历所有专辑匹配稳定 UUID
        do {
            let sdAlbums = try dataService.fetchAlbums()
            for sdAlbum in sdAlbums {
                let dto = sdAlbum.toAlbum()
                if dto.id == id {
                    return dto
                }
            }
        } catch {
            logger.warning("Failed to load single album: \(error.localizedDescription)")
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

        let sdAlbum = SDAlbum(
            name: name,
            folderURLString: nil,
            displayOrder: currentMaxOrder
        )
        dataService.insert(sdAlbum)

        // 创建 track entries
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

        try? dataService.save()

        let album = sdAlbum.toAlbum()
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
            // 单文件拖拽 - 扫描父目录
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
        // 检查是否已存在同路径专辑
        if dataService.findAlbum(byFolderURL: url.absoluteString) != nil {
            logger.debug("Album already exists for path: \(url.path)")
            return
        }
        // 也检查内存缓存
        if albums.contains(where: { $0.folderURL?.path == url.path }) {
            logger.debug("Album already exists in memory: \(url.path)")
            return
        }

        let currentMaxOrder = albums.count

        let sdAlbum = SDAlbum(
            name: url.lastPathComponent,
            folderURLString: url.absoluteString,
            displayOrder: currentMaxOrder
        )
        dataService.insert(sdAlbum)

        // 并发加载元数据
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

        try? dataService.save()

        let album = sdAlbum.toAlbum()
        albums.append(album)

        logger.info("📀 Added album: \(album.name) (\(trackDTOs.count) tracks)")
    }

    func removeAlbum(id: UUID) {
        // 从 SwiftData 删除
        do {
            let sdAlbums = try dataService.fetchAlbums()
            for sdAlbum in sdAlbums {
                if sdAlbum.toAlbum().id == id {
                    // 清理孤立 track
                    for entry in sdAlbum.trackEntries {
                        if let track = entry.track, !track.isInPlaylist, track.albumEntries.count <= 1 {
                            dataService.delete(track)
                        }
                    }
                    dataService.delete(sdAlbum)
                    break
                }
            }
            try dataService.save()
        } catch {
            logger.warning("Failed to delete album from SwiftData: \(error.localizedDescription)")
        }

        albums.removeAll { $0.id == id }
        logger.info("Album removed: \(id)")
    }

    func renameAlbum(id: UUID, newName: String) {
        guard let index = albums.firstIndex(where: { $0.id == id }) else { return }

        let oldName = albums[index].name
        albums[index].name = newName

        // 更新 SwiftData
        do {
            let sdAlbums = try dataService.fetchAlbums()
            for sdAlbum in sdAlbums {
                if sdAlbum.toAlbum().id == id {
                    sdAlbum.name = newName
                    break
                }
            }
            try dataService.save()
        } catch {
            logger.warning("Failed to rename album in SwiftData")
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

        // 更新所有 displayOrder
        reindexAlbumOrders()
        try? dataService.save()
    }

    func clearAllAlbums() {
        do {
            let sdAlbums = try dataService.fetchAlbums()
            for sdAlbum in sdAlbums {
                // 清理只属于该专辑的 track
                for entry in sdAlbum.trackEntries {
                    if let track = entry.track, !track.isInPlaylist, track.albumEntries.count <= 1 {
                        dataService.delete(track)
                    }
                }
                dataService.delete(sdAlbum)
            }
            try dataService.save()
        } catch {
            logger.logError(AppError.persistenceFailed("clear collections"), context: "clearAllAlbums")
        }

        let count = albums.count
        albums.removeAll()
        logger.info("Cleared all \(count) albums")
    }

    // MARK: - Private Methods

    private func loadCollections() async {
        do {
            let sdAlbums = try dataService.fetchAlbums()
            self.albums = sdAlbums.map { $0.toAlbum() }
            logger.info("Loaded \(self.albums.count) albums")
        } catch {
            logger.notice("No existing collections to load")
        }
    }

    private func reindexAlbumOrders() {
        do {
            let sdAlbums = try dataService.fetchAlbums()
            // 按当前内存中的顺序匹配更新
            for (newOrder, album) in albums.enumerated() {
                for sdAlbum in sdAlbums {
                    if sdAlbum.toAlbum().id == album.id {
                        sdAlbum.displayOrder = newOrder
                        break
                    }
                }
            }
        } catch {
            logger.warning("Failed to reindex album orders")
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
