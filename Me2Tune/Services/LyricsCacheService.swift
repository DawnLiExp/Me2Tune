//
//  LyricsCacheService.swift
//  Me2Tune
//
//  歌词缓存服务 - 可读文件名 + LRU清理
//

import CryptoKit
import Foundation
import OSLog

private nonisolated let logger = Logger.cache

actor LyricsCacheService {
    static let shared = LyricsCacheService()
    
    // MARK: - Configuration
    
    private let cacheDirectory: URL
    private let metadataURL: URL
    
    // MARK: - Types
    
    struct CacheEntry: Codable, Sendable {
        let urlHash: String
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
        self.cacheDirectory = CacheConfigManager.getLyricsCacheDirectory()
        self.metadataURL = cacheDirectory.appendingPathComponent("cache_metadata.json")
        
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        
        logger.info("Lyrics cache initialized: \(self.cacheDirectory.path)")
    }
    
    // MARK: - Public Methods
    
    func getCachedLyrics(audioURL: URL) async -> Lyrics? {
        if Task.isCancelled { return nil }
        
        let urlHash = cacheKey(audioURL: audioURL)
        
        let metadata = loadMetadata()
        guard let entry = metadata.entries.first(where: { $0.urlHash == urlHash }) else {
            return nil
        }
        
        let fileURL = cacheDirectory.appendingPathComponent("\(entry.fileName).lrc")
        
        if Task.isCancelled { return nil }
        
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let content = try? String(contentsOf: fileURL, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            logger.warning("Cache file missing or invalid: \(entry.fileName)")
            return nil
        }
        
        await updateAccessTime(urlHash: urlHash)
        
        // ✅ 智能识别内容类型：检测是否包含 LRC 时间轴格式
        let hasSyncedFormat = detectSyncedLyrics(content)
        
        let lyrics: Lyrics
        if hasSyncedFormat {
            // 带时间轴的歌词
            lyrics = Lyrics(
                id: 0,
                trackName: entry.trackName,
                artistName: entry.artistName,
                albumName: nil,
                duration: 0,
                instrumental: false,
                plainLyrics: nil,
                syncedLyrics: content
            )
            logger.debug("📄 Loaded synced lyrics from cache")
        } else {
            // 纯文本歌词
            lyrics = Lyrics(
                id: 0,
                trackName: entry.trackName,
                artistName: entry.artistName,
                albumName: nil,
                duration: 0,
                instrumental: false,
                plainLyrics: content,
                syncedLyrics: nil
            )
            logger.debug("📄 Loaded plain lyrics from cache")
        }
        
        return lyrics
    }
    
    func saveLyrics(_ lyrics: Lyrics, audioURL: URL) async {
        if Task.isCancelled { return }
        
        // ✅ 优先使用同步歌词，兜底使用纯文本歌词
        let lyricsContent: String
        if let syncedLyrics = lyrics.syncedLyrics,
           !syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            lyricsContent = syncedLyrics
        } else if let plainLyrics = lyrics.plainLyrics,
                  !plainLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            lyricsContent = plainLyrics
            logger.info("ℹ️ Caching plain lyrics (no synced version available)")
        } else {
            logger.debug("⏭️ Skipped caching: no lyrics content")
            return
        }
        
        let urlHash = cacheKey(audioURL: audioURL)
        let baseFileName = audioURL.deletingPathExtension().lastPathComponent
        let finalFileName = findAvailableFileName(baseFileName: baseFileName, urlHash: urlHash)
        let cacheFile = cacheDirectory.appendingPathComponent("\(finalFileName).lrc")
        
        if Task.isCancelled { return }
        
        do {
            try lyricsContent.write(to: cacheFile, atomically: true, encoding: .utf8)
            
            let attributes = try FileManager.default.attributesOfItem(atPath: cacheFile.path)
            let fileSize = attributes[.size] as? Int ?? 0
            
            var metadata = loadMetadata()
            metadata.entries.removeAll { $0.urlHash == urlHash }
            
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
            
            logger.info("💾 Saved: \(finalFileName).lrc (\(fileSize) bytes)")
            
            await cleanupIfNeeded()
            
        } catch {
            logger.error("Failed to save cache: \(error)")
        }
    }
    
    func getCacheStats() async -> (count: Int, totalSize: Int) {
        let metadata = loadMetadata()
        let totalSize = metadata.entries.reduce(0) { $0 + $1.fileSize }
        return (metadata.entries.count, totalSize)
    }
    
    // MARK: - Private Methods
    
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
        while counter <= 100 {
            let candidate = "\(baseFileName)-\(counter)"
            if !existingFileNames.contains(candidate) {
                return candidate
            }
            counter += 1
        }
        
        return String(urlHash.prefix(8))
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
        
        logger.info("🧹 LRU cleanup: removed \(removeCount) entries")
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
            logger.error("Failed to encode metadata")
            return
        }
        
        try? data.write(to: metadataURL, options: .atomic)
    }
    
    // MARK: - Helper: Detect Synced Lyrics Format
    
    private func detectSyncedLyrics(_ content: String) -> Bool {
        // 检测是否包含 LRC 时间戳格式：[mm:ss.xx] 或 [mm:ss]
        let pattern = "\\[\\d{2}:\\d{2}[.:]?\\d*\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        
        let range = NSRange(content.startIndex..., in: content)
        return regex.firstMatch(in: content, range: range) != nil
    }
}
