//
//  CollectionManager.swift
//  Me2Tune
//
//  专辑收藏管理 - 延迟加载优化版
//

import Combine
import Foundation
import OSLog

private let logger = Logger.collection

@MainActor
final class CollectionManager: ObservableObject {
    @Published private(set) var albums: [Album] = []
    @Published private(set) var isLoaded = false
    @Published private(set) var isLoading = false
    
    private let persistenceService = PersistenceService()
    private var delayedLoadTask: Task<Void, Never>?
    
    // MARK: - Lazy Loading
    
    func scheduleDelayedLoad(delay: TimeInterval = 2.5) {
        guard !isLoaded, delayedLoadTask == nil else { return }
        
        delayedLoadTask = Task {
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
            await MainActor.run {
                self.isLoaded = true
                self.delayedLoadTask = nil
            }
        }
    }
    
    func ensureLoaded() async {
        guard !isLoaded else { return }
        
        // 如果有延迟任务，取消它并立即加载
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
            
        await MainActor.run {
            self.albums.append(album)
            self.objectWillChange.send()
                
            logger.info("Album created from playlist: \(name) with \(tracks.count) tracks")
                
            saveCollections()
        }
            
        return album.id
    }
        
    func addAlbum(from folderURL: URL) async {
        await ensureLoaded()
        
        let albumName = folderURL.lastPathComponent
        
        logger.info("Scanning album: \(albumName)")
        
        let audioURLs = scanFolder(folderURL)
        
        logger.info("Found \(audioURLs.count) tracks")
        
        guard !audioURLs.isEmpty else {
            logger.warning("No audio files in folder: \(albumName)")
            return
        }
        
        let tracks = await withTaskGroup(of: AudioTrack.self) { group in
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
        
        let album = Album(name: albumName, folderURL: folderURL, tracks: tracks)
        
        await MainActor.run {
            self.albums.append(album)
            self.objectWillChange.send()
            
            logger.info("Album created: \(albumName) with \(tracks.count) tracks")
            logger.debug("Total albums: \(self.albums.count)")
            
            saveCollections()
        }
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
        let fileManager = FileManager.default
        let supportedExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ape", "wv", "tta", "mpc"]
        
        var audioURLs: [URL] = []
        
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            logger.error("Cannot access folder: \(folderURL.path)")
            return []
        }
        
        while let fileURL = enumerator.nextObject() as? URL {
            if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                audioURLs.append(fileURL)
            }
        }
        
        audioURLs.sort { $0.lastPathComponent < $1.lastPathComponent }
        
        return audioURLs
    }
}
