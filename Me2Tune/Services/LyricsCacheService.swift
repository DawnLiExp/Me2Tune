//
//  LyricsCacheService.swift
//  Me2Tune
//
//  歌词缓存服务 - 可读文件名 + LRU清理
//

import CryptoKit
import Foundation
import OSLog

private nonisolated let logger = Logger(subsystem: "me2.Me2Tune", category: "LyricsCache")

actor LyricsCacheService {
    static let shared = LyricsCacheService()
    
    // MARK: - Configuration
    
    private let cacheDirectory: URL
    private let metadataURL: URL
    
    // MARK: - Types
    
    struct CacheEntry: Codable, Sendable {
        let hash: String
        let fileName: String
        let trackName: String
        let artistName: String
        var lastAccess: Date
        let fileSize: Int
        let createdAt: Date
    }
    
    struct CacheMetadata: Codable, Sendable {
        let version: Int
        var entries: [CacheEntry]
        
        static let current = CacheMetadata(version: 1, entries: [])
    }
    
    // MARK: - Initialization
    
    private init() {
        // ✅ 使用静态方法获取路径
        self.cacheDirectory = CacheConfigManager.getLyricsCacheDirectory()
        self.metadataURL = cacheDirectory.appendingPathComponent("cache_metadata.json")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        
        logger.info("LyricsCacheService initialized at: \(self.cacheDirectory.path)")
    }
    
    // MARK: - Public Methods
    
    /// 获取缓存的歌词
    func getCachedLyrics(audioURL: URL, trackName: String, artistName: String, duration: Int) async -> Lyrics? {
        let hash = cacheKey(trackName: trackName, artistName: artistName, duration: duration)
        
        let metadata = loadMetadata()
        guard let entry = metadata.entries.first(where: { $0.hash == hash }) else {
            return nil
        }
        
        let fileURL = cacheDirectory.appendingPathComponent("\(entry.fileName).lrc")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.warning("Cache entry exists but file missing: \(entry.fileName)")
            return nil
        }
        
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            logger.warning("Failed to read cached lyrics: \(entry.fileName)")
            return nil
        }
        
        await updateAccessTime(hash: hash)
        
        let lyrics = Lyrics(
            id: 0,
            trackName: trackName,
            artistName: artistName,
            albumName: nil,
            duration: duration,
            instrumental: false,
            plainLyrics: nil,
            syncedLyrics: content
        )
        
        logger.info("✅ Cache hit: \(entry.fileName).lrc")
        return lyrics
    }
    
    /// 保存歌词到缓存
    func saveLyrics(_ lyrics: Lyrics, audioURL: URL) async {
        guard let syncedLyrics = lyrics.syncedLyrics,
              !syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }
        
        let hash = cacheKey(
            trackName: lyrics.trackName,
            artistName: lyrics.artistName,
            duration: lyrics.duration
        )
        
        let baseFileName = audioURL.deletingPathExtension().lastPathComponent
        let finalFileName = findAvailableFileName(baseFileName: baseFileName, hash: hash)
        let fileURL = cacheDirectory.appendingPathComponent("\(finalFileName).lrc")
        
        do {
            try syncedLyrics.write(to: fileURL, atomically: true, encoding: .utf8)
            
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int ?? 0
            
            var metadata = loadMetadata()
            metadata.entries.removeAll { $0.hash == hash }
            
            let entry = CacheEntry(
                hash: hash,
                fileName: finalFileName,
                trackName: lyrics.trackName,
                artistName: lyrics.artistName,
                lastAccess: Date(),
                fileSize: fileSize,
                createdAt: Date()
            )
            metadata.entries.append(entry)
            
            saveMetadata(metadata)
            
            logger.info("💾 Cached lyrics: \(finalFileName).lrc (\(fileSize) bytes)")
            
            await cleanupIfNeeded()
            
        } catch {
            logger.error("Failed to save lyrics cache: \(error.localizedDescription)")
        }
    }
    
    /// 获取缓存统计信息
    func getCacheStats() async -> (count: Int, totalSize: Int) {
        let metadata = loadMetadata()
        let totalSize = metadata.entries.reduce(0) { $0 + $1.fileSize }
        return (metadata.entries.count, totalSize)
    }
    
    // MARK: - Private Methods
    
    private func cacheKey(trackName: String, artistName: String, duration: Int) -> String {
        let signature = "\(trackName)|\(artistName)|\(duration)"
        let data = Data(signature.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    private func findAvailableFileName(baseFileName: String, hash: String) -> String {
        let metadata = loadMetadata()
        
        if let existing = metadata.entries.first(where: { $0.hash == hash }) {
            return existing.fileName
        }
        
        let existingFileNames = Set(metadata.entries.map(\.fileName))
        
        if !existingFileNames.contains(baseFileName) {
            return baseFileName
        }
        
        var counter = 1
        while true {
            let candidate = "\(baseFileName)-\(counter)"
            if !existingFileNames.contains(candidate) {
                return candidate
            }
            counter += 1
            
            if counter > 100 {
                logger.warning("Too many duplicates, using hash fallback")
                return String(hash.prefix(8))
            }
        }
    }
    
    private func updateAccessTime(hash: String) async {
        var metadata = loadMetadata()
        
        if let index = metadata.entries.firstIndex(where: { $0.hash == hash }) {
            metadata.entries[index].lastAccess = Date()
            saveMetadata(metadata)
        }
    }
    
    private func cleanupIfNeeded() async {
        var metadata = loadMetadata()
        
        let maxCount = CacheConfigManager.maxCacheCount
        guard metadata.entries.count > maxCount else {
            return
        }
        
        metadata.entries.sort { $0.lastAccess < $1.lastAccess }
        
        let removeCount = metadata.entries.count - maxCount
        let entriesToRemove = metadata.entries.prefix(removeCount)
        
        for entry in entriesToRemove {
            let fileURL = cacheDirectory.appendingPathComponent("\(entry.fileName).lrc")
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        metadata.entries.removeFirst(removeCount)
        saveMetadata(metadata)
        
        logger.info("🧹 LRU cleanup: removed \(removeCount) oldest entries")
    }
    
    private func loadMetadata() -> CacheMetadata {
        guard FileManager.default.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: data)
        else {
            return .current
        }
        
        return metadata
    }
    
    private func saveMetadata(_ metadata: CacheMetadata) {
        guard let data = try? JSONEncoder().encode(metadata) else {
            logger.error("Failed to encode cache metadata")
            return
        }
        
        try? data.write(to: metadataURL, options: .atomic)
    }
}
