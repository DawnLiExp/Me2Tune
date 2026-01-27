//
//  CollectionManager.swift
//  Me2Tune
//
//  专辑收藏管理 - 延迟加载优化版 + 拖拽排序
//

import Combine
import Foundation
import Observation
import OSLog

private let logger = Logger.collection

@MainActor
@Observable
final class CollectionManager {
    // MARK: - Published States (✅ 移除 @Published，Observation 自动追踪)
    
    private(set) var albums: [Album] = []
    private(set) var isLoaded = false
    private(set) var isLoading = false
    
    // MARK: - Private Properties
    
    private let persistenceService = PersistenceService()
    private var delayedLoadTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init() {
        logger.debug("✅ CollectionManager initialized (@Observable)")
    }
    
    // MARK: - Lazy Loading
    
    func scheduleDelayedLoad(delay: TimeInterval = 2.5) {
        guard !isLoaded, delayedLoadTask == nil else { return }
        
        delayedLoadTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            
            guard !Task.isCancelled else {
                logger.debug("Delayed load cancelled")
                return
            }
            
            logger.info("⏰ Starting delayed collection load")
            await loadCollections()
            
            self.isLoaded = true
            self.delayedLoadTask = nil
        }
    }
    
    func ensureLoaded() async {
        guard !isLoaded else { return }
        
        if let task = delayedLoadTask {
            task.cancel()
            delayedLoadTask = nil
            logger.info("👆 User triggered, loading immediately")
        }
        
        isLoading = true
        await loadCollections()
        isLoaded = true
        isLoading = false
    }
    
    // MARK: - Single Album Loading
    
    func loadSingleAlbum(id: UUID) async -> Album? {
        guard let state = try? persistenceService.loadCollections(),
              let album = state.albums.first(where: { $0.id == id })
        else {
            return nil
        }
        
        let hasOldData = album.tracks.contains { track in
            track.artist == nil && track.title.contains(".")
        }
        
        if hasOldData {
            logger.info("Migrating single album metadata: \(album.name)")
            let audioURLs = scanFolder(album.folderURL)
            let newTracks = await withTaskGroup(of: AudioTrack.self) { group in
                for url in audioURLs {
                    group.addTask {
                        await AudioTrack(url: url)
                    }
                }
                
                var result: [AudioTrack] = []
                for await track in group {
                    result.append(track)
                }
                return result
            }
            
            var migratedAlbum = album
            migratedAlbum.tracks = newTracks
            return migratedAlbum
        }
        
        return album
    }
    
    // MARK: - Album Management
        
    func addAlbumFromPlaylist(name: String, tracks: [AudioTrack]) async -> UUID? {
        await ensureLoaded()
            
        guard !tracks.isEmpty else {
            logger.warning("Cannot create album from empty playlist")
            return nil
        }
            
        let album = Album(name: name, folderURL: URL(fileURLWithPath: "/"), tracks: tracks)
            
        // ✅ Observation 自动追踪，无需手动通知
        self.albums.append(album)
            
        logger.info("Album created from playlist: \(name) with \(tracks.count) tracks")
            
        saveCollections()
            
        return album.id
    }
        
    func addAlbum(from url: URL) async {
        await ensureLoaded()
        
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        
        if isDirectory.boolValue {
            await scanAndAddAlbums(at: url)
        } else {
            let parentURL = url.deletingLastPathComponent()
            let audioFiles = scanFolderOnly(parentURL)
            if !audioFiles.isEmpty {
                await createAlbum(from: parentURL, audioURLs: audioFiles)
            }
        }
    }
    
    private func scanAndAddAlbums(at url: URL) async {
        let fileManager = FileManager.default
        
        let audioFiles = scanFolderOnly(url)
        if !audioFiles.isEmpty {
            await createAlbum(from: url, audioURLs: audioFiles)
        }
        
        let contents = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for item in contents {
            var isSubDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isSubDir), isSubDir.boolValue {
                await scanAndAddAlbums(at: item)
            }
        }
    }
    
    private func createAlbum(from url: URL, audioURLs: [URL]) async {
        if albums.contains(where: { $0.folderURL.path == url.path }) {
            logger.debug("Album already exists for path: \(url.path)")
            return
        }

        let albumName = url.lastPathComponent
        let tracks = await withTaskGroup(of: (Int, AudioTrack).self) { group in
            let sortedURLs = audioURLs.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            
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
            return tracksWithIndex.sorted { $0.0 < $1.0 }.map(\.1)
        }
        
        // ✅ Observation 自动追踪，无需手动通知
        let album = Album(name: albumName, folderURL: url, tracks: tracks)
        self.albums.append(album)
        
        logger.info("Album created: \(albumName) with \(tracks.count) tracks")
        saveCollections()
    }
    
    func removeAlbum(id: UUID) {
        albums.removeAll { $0.id == id }
        logger.info("Album removed: \(id)")
        saveCollections()
    }
    
    func renameAlbum(id: UUID, newName: String) {
        guard let index = albums.firstIndex(where: { $0.id == id }) else { return }
        
        let oldName = albums[index].name
        albums[index].name = newName
        
        logger.info("Album renamed: '\(oldName)' -> '\(newName)'")
        saveCollections()
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
        
        logger.info("Album moved from \(source) to \(destination)")
        saveCollections()
    }
    
    func clearAllAlbums() {
        let count = albums.count
        albums.removeAll()
        logger.info("Cleared all \(count) albums")
        saveCollections()
    }
    
    // MARK: - Private Methods
    
    private func loadCollections() async {
        do {
            let state = try persistenceService.loadCollections()
            
            var migratedAlbums: [Album] = []
            var needsMigration = false
            
            for album in state.albums {
                let hasOldData = album.tracks.contains { track in
                    track.artist == nil && track.title.contains(".")
                }
                
                if hasOldData {
                    logger.info("Migrating album metadata: \(album.name)")
                    needsMigration = true
                    
                    let audioURLs = scanFolder(album.folderURL)
                    let newTracks = await withTaskGroup(of: AudioTrack.self) { group in
                        for url in audioURLs {
                            group.addTask {
                                await AudioTrack(url: url)
                            }
                        }
                        
                        var result: [AudioTrack] = []
                        for await track in group {
                            result.append(track)
                        }
                        return result
                    }
                    
                    var migratedAlbum = album
                    migratedAlbum.tracks = newTracks
                    migratedAlbums.append(migratedAlbum)
                } else {
                    migratedAlbums.append(album)
                }
            }
            
            // ✅ Observation 自动追踪
            self.albums = migratedAlbums
            logger.info("Loaded \(self.albums.count) albums")
            
            if needsMigration {
                logger.info("Saving migrated metadata")
                saveCollections()
            }
        } catch {
            logger.notice("No existing collections to load")
        }
    }
    
    private func saveCollections() {
        do {
            let state = CollectionState(albums: self.albums)
            try persistenceService.save(state)
            logger.debug("Saved \(self.albums.count) albums")
        } catch {
            logger.error("Failed to save collections: \(error.localizedDescription)")
        }
    }
    
    private func scanFolder(_ folderURL: URL) -> [URL] {
        let supportedExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ape", "wv", "tta", "mpc"]
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        
        var urls: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if supportedExtensions.contains(url.pathExtension.lowercased()) {
                urls.append(url)
            }
        }
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    
    private func scanFolderOnly(_ folderURL: URL) -> [URL] {
        let supportedExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ape", "wv", "tta", "mpc"]
        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
        
        return contents.filter { url in
            supportedExtensions.contains(url.pathExtension.lowercased())
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
