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
    
    private let maxCacheSize = 1000 // 最多缓存1000首歌词
    private let maxCacheAge: TimeInterval = 90 * 24 * 60 * 60 // 90天
    
    private let cacheDirectory: URL
    private let metadataURL: URL
    
    // MARK: - Types
    
    struct CacheEntry: Codable, Sendable {
        let hash: String
        let fileName: String // 音频文件名（不含扩展名）
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
        let cacheDir = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Me2Tune/Lyrics", isDirectory: true)
        
        try? FileManager.default.createDirectory(
            at: cacheDir,
            withIntermediateDirectories: true
        )
        
        self.cacheDirectory = cacheDir
        self.metadataURL = cacheDir.appendingPathComponent("cache_metadata.json")
        
        logger.info("LyricsCacheService initialized at: \(cacheDir.path)")
        
        Task {
            await cleanupExpiredCache()
        }
    }
    
    // MARK: - Public Methods
    
    /// 获取缓存的歌词
    func getCachedLyrics(audioURL: URL, trackName: String, artistName: String, duration: Int) async -> Lyrics? {
        let hash = cacheKey(trackName: trackName, artistName: artistName, duration: duration)
        
        // 从元数据查找对应的文件名
        let metadata = loadMetadata()
        guard let entry = metadata.entries.first(where: { $0.hash == hash }) else {
            return nil
        }
        
        let fileURL = cacheDirectory.appendingPathComponent("\(entry.fileName).lrc")
        
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.warning("Cache entry exists but file missing: \(entry.fileName)")
            return nil
        }
        
        // 读取LRC内容
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            logger.warning("Failed to read cached lyrics: \(entry.fileName)")
            return nil
        }
        
        // 更新访问时间
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
        
        // 生成文件名（音频文件名）
        let baseFileName = audioURL.deletingPathExtension().lastPathComponent
        let finalFileName = findAvailableFileName(baseFileName: baseFileName, hash: hash)
        let fileURL = cacheDirectory.appendingPathComponent("\(finalFileName).lrc")
        
        do {
            // 写入LRC文件
            try syncedLyrics.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // 获取文件大小
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int ?? 0
            
            // 更新元数据
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
    
    /// 清理过期缓存
    func cleanupExpiredCache() async {
        var metadata = loadMetadata()
        let now = Date()
        var removedCount = 0
        
        let expiredEntries = metadata.entries.filter { entry in
            let age = now.timeIntervalSince(entry.lastAccess)
            return age > maxCacheAge
        }
        
        for entry in expiredEntries {
            let fileURL = cacheDirectory.appendingPathComponent("\(entry.fileName).lrc")
            try? FileManager.default.removeItem(at: fileURL)
            removedCount += 1
        }
        
        metadata.entries.removeAll { entry in
            let age = now.timeIntervalSince(entry.lastAccess)
            return age > maxCacheAge
        }
        
        if removedCount > 0 {
            saveMetadata(metadata)
            logger.info("🧹 Cleaned \(removedCount) expired cache entries")
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
    
    /// 查找可用文件名（处理重名）
    private func findAvailableFileName(baseFileName: String, hash: String) -> String {
        let metadata = loadMetadata()
        
        // 检查是否已有此hash的缓存（更新场景）
        if let existing = metadata.entries.first(where: { $0.hash == hash }) {
            return existing.fileName
        }
        
        // 检查基础文件名是否可用
        let existingFileNames = Set(metadata.entries.map(\.fileName))
        
        if !existingFileNames.contains(baseFileName) {
            return baseFileName
        }
        
        // 重名处理：追加 -1, -2, -3
        var counter = 1
        while true {
            let candidate = "\(baseFileName)-\(counter)"
            if !existingFileNames.contains(candidate) {
                return candidate
            }
            counter += 1
            
            // 安全阈值
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
        
        guard metadata.entries.count > maxCacheSize else {
            return
        }
        
        metadata.entries.sort { $0.lastAccess < $1.lastAccess }
        
        let removeCount = metadata.entries.count - maxCacheSize
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
