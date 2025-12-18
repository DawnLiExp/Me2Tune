//
//  CollectionManager.swift
//  Me2Tune
//
//  专辑收藏管理
//

import Foundation
import Combine
import OSLog

private let logger = Logger(subsystem: "me2.Me2Tune", category: "CollectionManager")

@MainActor
final class CollectionManager: ObservableObject {
    @Published private(set) var albums: [Album] = []
    private let persistenceService = PersistenceService()
    
    init() {
        Task {
            await loadCollections()
        }
    }
    
    func addAlbum(from folderURL: URL) async {
        let albumName = folderURL.lastPathComponent
        
        logger.info("Scanning album: \(albumName)")
        
        let audioURLs = scanFolder(folderURL)
        
        logger.info("Found \(audioURLs.count) tracks")
        
        guard !audioURLs.isEmpty else {
            logger.warning("No audio files in folder: \(albumName)")
            return
        }
        
        var tracks: [AudioTrack] = []
        for url in audioURLs {
            let track = await AudioTrack(url: url)
            tracks.append(track)
        }
        
        let album = Album(name: albumName, folderURL: folderURL, tracks: tracks)
        
        await MainActor.run {
            self.albums.append(album)
            self.objectWillChange.send()
            
            logger.info("Album created: \(albumName) with \(tracks.count) tracks")
            logger.debug("Total albums: \(self.albums.count)")
            
            Task { await saveCollections() }
        }
    }
    
    func removeAlbum(id: UUID) {
        albums.removeAll { $0.id == id }
        logger.info("Album removed: \(id)")
        Task { await saveCollections() }
    }
    
    func renameAlbum(id: UUID, newName: String) {
        guard let index = albums.firstIndex(where: { $0.id == id }) else { return }
        
        let oldName = albums[index].name
        albums[index].name = newName
        
        logger.info("Album renamed: '\(oldName)' -> '\(newName)'")
        Task { await saveCollections() }
    }
    
    func clearAllAlbums() {
        let count = albums.count
        albums.removeAll()
        logger.info("Cleared all \(count) albums")
        Task { await saveCollections() }
    }
    
    // MARK: - Private Methods
    
    private func loadCollections() async {
        do {
            let state = try await persistenceService.loadCollections()
            
            // 检测并迁移旧数据：重新提取元数据
            var migratedAlbums: [Album] = []
            var needsMigration = false
            
            for album in state.albums {
                // 检查是否有缺失元数据的track（title是文件名格式）
                let hasOldData = album.tracks.contains { track in
                    track.artist == nil && track.title.contains(".")
                }
                
                if hasOldData {
                    logger.info("Migrating album metadata: \(album.name)")
                    needsMigration = true
                    
                    // 重新扫描并创建tracks
                    let audioURLs = scanFolder(album.folderURL)
                    var newTracks: [AudioTrack] = []
                    for url in audioURLs {
                        let track = await AudioTrack(url: url)
                        newTracks.append(track)
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
            
            // 如果进行了迁移，保存新数据
            if needsMigration {
                logger.info("Saving migrated metadata")
                await saveCollections()
            }
        } catch {
            logger.notice("No existing collections to load")
        }
    }
    
    private func saveCollections() async {
        do {
            let state = CollectionState(albums: self.albums)
            try await persistenceService.save(state)
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
