//
//  LyricsCacheService.swift
//  Me2Tune
//
//  歌词缓存服务 - LRC文件缓存 + LRU清理
//

import CryptoKit
import Foundation
import OSLog

private nonisolated let logger = Logger(subsystem: "me2.Me2Tune", category: "LyricsCache")

actor LyricsCacheService {
    static let shared = LyricsCacheService()
    
    // MARK: - Configuration
    
    private let maxCacheSize = 1000 // 最多缓存1000首
    private let maxCacheAge: TimeInterval = 90 * 24 * 60 * 60 // 90天
    
    private let cacheDirectory: URL
    private let metadataURL: URL
    
    // MARK: - Types
    
    struct CacheEntry: Codable, Sendable {
        let hash: String
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
        
        // 启动时清理过期缓存
        Task {
            await cleanupExpiredCache()
        }
    }
    
    // MARK: - Public Methods
    
    /// 获取缓存的歌词
    func getCachedLyrics(trackName: String, artistName: String, duration: Int) async -> Lyrics? {
        let hash = cacheKey(trackName: trackName, artistName: artistName, duration: duration)
        let fileURL = cacheDirectory.appendingPathComponent("\(hash).lrc")
        
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        // 读取LRC内容
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            logger.warning("Failed to read cached lyrics: \(hash)")
            return nil
        }
        
        // 更新访问时间
        await updateAccessTime(hash: hash)
        
        // 构建Lyrics对象
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
        
        logger.info("✅ Cache hit: \(trackName) - \(artistName)")
        return lyrics
    }
    
    /// 保存歌词到缓存
    func saveLyrics(_ lyrics: Lyrics) async {
        // 只缓存有同步歌词的内容
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
        let fileURL = cacheDirectory.appendingPathComponent("\(hash).lrc")
        
        do {
            // 写入LRC文件
            try syncedLyrics.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // 获取文件大小
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int ?? 0
            
            // 更新元数据
            var metadata = loadMetadata()
            
            // 移除旧条目（如果存在）
            metadata.entries.removeAll { $0.hash == hash }
            
            // 添加新条目
            let entry = CacheEntry(
                hash: hash,
                trackName: lyrics.trackName,
                artistName: lyrics.artistName,
                lastAccess: Date(),
                fileSize: fileSize,
                createdAt: Date()
            )
            metadata.entries.append(entry)
            
            // 保存元数据
            saveMetadata(metadata)
            
            logger.info("💾 Cached lyrics: \(lyrics.trackName) - \(lyrics.artistName) (\(fileSize) bytes)")
            
            // 检查是否需要清理
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
        
        // 找出过期的条目
        let expiredEntries = metadata.entries.filter { entry in
            let age = now.timeIntervalSince(entry.lastAccess)
            return age > maxCacheAge
        }
        
        // 删除过期文件
        for entry in expiredEntries {
            let fileURL = cacheDirectory.appendingPathComponent("\(entry.hash).lrc")
            try? FileManager.default.removeItem(at: fileURL)
            removedCount += 1
        }
        
        // 更新元数据
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
    
    /// 生成缓存键（MD5 hash）
    private func cacheKey(trackName: String, artistName: String, duration: Int) -> String {
        let signature = "\(trackName)|\(artistName)|\(duration)"
        let data = Data(signature.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    /// 更新访问时间
    private func updateAccessTime(hash: String) async {
        var metadata = loadMetadata()
        
        if let index = metadata.entries.firstIndex(where: { $0.hash == hash }) {
            metadata.entries[index].lastAccess = Date()
            saveMetadata(metadata)
        }
    }
    
    /// 检查并清理（数量超限时）
    private func cleanupIfNeeded() async {
        var metadata = loadMetadata()
        
        guard metadata.entries.count > maxCacheSize else {
            return
        }
        
        // 按最后访问时间排序（最旧的在前）
        metadata.entries.sort { $0.lastAccess < $1.lastAccess }
        
        // 计算需要删除的数量
        let removeCount = metadata.entries.count - maxCacheSize
        let entriesToRemove = metadata.entries.prefix(removeCount)
        
        // 删除文件
        for entry in entriesToRemove {
            let fileURL = cacheDirectory.appendingPathComponent("\(entry.hash).lrc")
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        // 更新元数据
        metadata.entries.removeFirst(removeCount)
        saveMetadata(metadata)
        
        logger.info("🧹 LRU cleanup: removed \(removeCount) oldest entries")
    }
    
    /// 加载元数据
    private func loadMetadata() -> CacheMetadata {
        guard FileManager.default.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: data)
        else {
            return .current
        }
        
        return metadata
    }
    
    /// 保存元数据
    private func saveMetadata(_ metadata: CacheMetadata) {
        guard let data = try? JSONEncoder().encode(metadata) else {
            logger.error("Failed to encode cache metadata")
            return
        }
        
        try? data.write(to: metadataURL, options: .atomic)
    }
}
