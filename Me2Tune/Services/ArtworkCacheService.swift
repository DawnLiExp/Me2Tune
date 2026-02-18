//
//  ArtworkCacheService.swift
//  Me2Tune
//
//  封面缓存服务 - 内存+磁盘双层缓存 + LRU清理
//

import AppKit
import CryptoKit
import Foundation
import OSLog
import SFBAudioEngine

actor ArtworkCacheService {
    // MARK: - Singleton
    
    static let shared = ArtworkCacheService()
    
    // MARK: - Cache Configuration
    
    private let memoryCache = NSCache<NSURL, NSImage>()
    private let thumbnailSize: CGSize = .init(width: 300, height: 300)
    private nonisolated let logger = Logger.artwork
    
    private let diskCacheURL: URL
    private let metadataURL: URL
    
    // MARK: - Concurrent Loading Control
    
    private var loadingTasks: [URL: Task<NSImage?, Never>] = [:]
    
    // MARK: - Types
    
    struct CacheEntry: Codable, Sendable {
        let urlHash: String
        let fileName: String
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
        self.diskCacheURL = CacheConfigManager.getArtworkCacheDirectory()
        self.metadataURL = diskCacheURL.appendingPathComponent("cache_metadata.json")
        
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
        
        // 确保目录存在
        try? FileManager.default.createDirectory(
            at: diskCacheURL,
            withIntermediateDirectories: true
        )
        
        logger.info("ArtworkCacheService initialized at: \(self.diskCacheURL.path)")
    }
    
    // MARK: - Public Methods
    
    func artwork(for url: URL) async -> NSImage? {
        // 1. Check memory cache
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached
        }
        
        // 2. Check if already loading
        if let existingTask = loadingTasks[url] {
            return await existingTask.value
        }
        
        // 3. Create new loading task
        let task = Task<NSImage?, Never> {
            // Check disk cache
            if let diskCached = await loadFromDiskCache(url: url) {
                cacheInMemory(diskCached, for: url)
                return diskCached
            }
            
            // Extract from audio file
            if let extracted = await extractArtwork(from: url) {
                await cacheToDisk(extracted, for: url)
                cacheInMemory(extracted, for: url)
                return extracted
            }
            
            logger.info("No artwork found for: \(url.lastPathComponent)")
            return nil
        }
        
        loadingTasks[url] = task
        let result = await task.value
        loadingTasks[url] = nil
        
        return result
    }
    
    func preloadArtworks(for urls: [URL], priority: TaskPriority = .utility) {
        Task(priority: priority) {
            for url in urls {
                _ = await artwork(for: url)
            }
        }
    }
    
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
        logger.debug("Memory cache cleared")
    }
    
    func getCacheStats() async -> (count: Int, totalSize: Int) {
        let metadata = loadMetadata()
        let totalSize = metadata.entries.reduce(0) { $0 + $1.fileSize }
        return (metadata.entries.count, totalSize)
    }
    
    // MARK: - Private Methods
    
    private func cacheInMemory(_ image: NSImage, for url: URL) {
        memoryCache.setObject(image, forKey: url as NSURL)
    }
    
    private func loadFromDiskCache(url: URL) async -> NSImage? {
        let urlHash = hashURL(url)
        
        var metadata = loadMetadata()
        guard let entryIndex = metadata.entries.firstIndex(where: { $0.urlHash == urlHash }) else {
            return nil
        }
        
        let entry = metadata.entries[entryIndex]
        let cacheFile = diskCacheURL.appendingPathComponent("\(entry.fileName).jpg")
        
        guard FileManager.default.fileExists(atPath: cacheFile.path),
              let image = NSImage(contentsOf: cacheFile)
        else {
            return nil
        }
        
        // 更新访问时间
        metadata.entries[entryIndex].lastAccess = Date()
        saveMetadata(metadata)
        
        return image
    }
    
    private func cacheToDisk(_ image: NSImage, for url: URL) async {
        let urlHash = hashURL(url)
        let fileName = url.deletingPathExtension().lastPathComponent
        let finalFileName = findAvailableFileName(baseFileName: fileName, urlHash: urlHash)
        let cacheFile = diskCacheURL.appendingPathComponent("\(finalFileName).jpg")
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else {
            return
        }
        
        do {
            try jpegData.write(to: cacheFile, options: .atomic)
            
            let fileSize = jpegData.count
            
            var metadata = loadMetadata()
            metadata.entries.removeAll { $0.urlHash == urlHash }
            
            let entry = CacheEntry(
                urlHash: urlHash,
                fileName: finalFileName,
                lastAccess: Date(),
                fileSize: fileSize,
                createdAt: Date()
            )
            metadata.entries.append(entry)
            
            saveMetadata(metadata)
            
            logger.info("💾 Cached artwork: \(finalFileName).jpg (\(fileSize) bytes)")
            
            await cleanupIfNeeded()
            
        } catch {
            logger.error("Failed to cache artwork: \(error)")
        }
    }
    
    private func extractArtwork(from url: URL) async -> NSImage? {
        guard let audioFile = try? SFBAudioEngine.AudioFile(readingPropertiesAndMetadataFrom: url) else {
            return await extractFolderArtwork(from: url)
        }
        
        let attachedPictures = audioFile.metadata.attachedPictures
        guard !attachedPictures.isEmpty,
              let firstPicture = attachedPictures.first,
              let image = NSImage(data: firstPicture.imageData)
        else {
            return await extractFolderArtwork(from: url)
        }
        
        return resizeImage(image, to: thumbnailSize)
    }
    
    private func extractFolderArtwork(from url: URL) async -> NSImage? {
        let directory = url.deletingLastPathComponent()
        let fileManager = FileManager.default
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        
        let imageExtensions = ["jpg", "jpeg", "png", "bmp", "tiff", "tif"]
        let imageFiles = contents
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        guard let firstImage = imageFiles.first,
              let image = NSImage(contentsOf: firstImage)
        else {
            return nil
        }
        
        return resizeImage(image, to: thumbnailSize)
    }
    
    private func resizeImage(_ image: NSImage, to size: CGSize) -> NSImage {
        let newImage = NSImage(size: size)
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage
        else {
            return image
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return image
        }
        
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        
        guard let resizedCGImage = context.makeImage() else {
            return image
        }
        
        let resizedBitmap = NSBitmapImageRep(cgImage: resizedCGImage)
        newImage.addRepresentation(resizedBitmap)
        
        return newImage
    }
    
    // MARK: - Metadata Management
    
    private func hashURL(_ url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
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
            let fileURL = diskCacheURL.appendingPathComponent("\(entry.fileName).jpg")
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        metadata.entries.removeFirst(removeCount)
        saveMetadata(metadata)
        
        logger.info("🧹 LRU cleanup: removed \(removeCount) oldest artworks")
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
            logger.error("Failed to encode artwork metadata")
            return
        }
        
        try? data.write(to: metadataURL, options: .atomic)
    }
}
