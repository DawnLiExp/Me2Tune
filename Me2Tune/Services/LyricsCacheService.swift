//
//  LyricsCacheService.swift
//  Me2Tune
//
//  歌词缓存服务 - 可读文件名 + LRU清理 (修复缓存key逻辑)
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
        let urlHash: String // ✅ 改为基于 URL 的 hash
        let fileName: String
        let trackName: String // 保留用于展示
        let artistName: String // 保留用于展示
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
        self.cacheDirectory = CacheConfigManager.getLyricsCacheDirectory()
        self.metadataURL = cacheDirectory.appendingPathComponent("cache_metadata.json")
        
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        
        logger.info("LyricsCacheService initialized at: \(self.cacheDirectory.path)")
    }
    
    // MARK: - Public Methods
    
    /// 获取缓存的歌词（只需 audioURL）
    func getCachedLyrics(audioURL: URL) async -> Lyrics? {
        let urlHash = cacheKey(audioURL: audioURL)
        
        let metadata = loadMetadata()
        guard let entry = metadata.entries.first(where: { $0.urlHash == urlHash }) else {
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
        
        await updateAccessTime(urlHash: urlHash)
        
        // ✅ 使用缓存的 trackName/artistName 构造返回值
        let lyrics = Lyrics(
            id: 0,
            trackName: entry.trackName,
            artistName: entry.artistName,
            albumName: nil,
            duration: 0, // duration 不重要，歌词不需要
            instrumental: false,
            plainLyrics: nil,
            syncedLyrics: content
        )
        
        logger.info("✅ Cache hit: \(entry.fileName).lrc")
        return lyrics
    }
    
    /// 保存歌词到缓存（使用 audioURL 作为 key）
    func saveLyrics(_ lyrics: Lyrics, audioURL: URL) async {
        guard let syncedLyrics = lyrics.syncedLyrics,
              !syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }
        
        let urlHash = cacheKey(audioURL: audioURL)
        
        let baseFileName = audioURL.deletingPathExtension().lastPathComponent
        let finalFileName = findAvailableFileName(baseFileName: baseFileName, urlHash: urlHash)
        let fileURL = cacheDirectory.appendingPathComponent("\(finalFileName).lrc")
        
        do {
            try syncedLyrics.write(to: fileURL, atomically: true, encoding: .utf8)
            
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int ?? 0
            
            var metadata = loadMetadata()
            metadata.entries.removeAll { $0.urlHash == urlHash }
            
            // ✅ 保存 trackName/artistName 仅用于展示
            let entry = CacheEntry(
                urlHash: urlHash,
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
    
    /// ✅ 新的 cacheKey 方法：基于 audioURL.path
    private func cacheKey(audioURL: URL) -> String {
        let path = audioURL.path
        let data = Data(path.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    private func findAvailableFileName(baseFileName: String, urlHash: String) -> String {
        let metadata = loadMetadata()
        
        if let existing = metadata.entries.first(where: { $0.urlHash == urlHash }) {
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
                return String(urlHash.prefix(8))
            }
        }
    }
    
    private func updateAccessTime(urlHash: String) async {
        var metadata = loadMetadata()
        
        if let index = metadata.entries.firstIndex(where: { $0.urlHash == urlHash }) {
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
