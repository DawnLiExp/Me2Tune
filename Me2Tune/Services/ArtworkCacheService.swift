//
//  ArtworkCacheService.swift
//  Me2Tune
//
//  封面缓存服务 - 内存+磁盘双层缓存
//

import AppKit
import Foundation
import OSLog
import SFBAudioEngine

private nonisolated(unsafe) let logger = Logger.artwork

actor ArtworkCacheService {
    // MARK: - Singleton
    
    static let shared = ArtworkCacheService()
    
    // MARK: - Cache Configuration
    
    private let memoryCache = NSCache<NSURL, NSImage>()
    private let diskCacheURL: URL
    private let thumbnailSize: CGSize = CGSize(width: 300, height: 300)
    
    // MARK: - Concurrent Loading Control
    
    private var loadingTasks: [URL: Task<NSImage?, Never>] = [:]
    
    // MARK: - Initialization
    
    private init() {
        let cacheDir = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Me2Tune/Artwork", isDirectory: true)
        
        try? FileManager.default.createDirectory(
            at: cacheDir,
            withIntermediateDirectories: true
        )
        
        diskCacheURL = cacheDir
        
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
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
            if let diskCached = loadFromDiskCache(url: url) {
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
    
    // MARK: - Private Methods
    
    private func cacheInMemory(_ image: NSImage, for url: URL) {
        memoryCache.setObject(image, forKey: url as NSURL)
    }
    
    private func loadFromDiskCache(url: URL) -> NSImage? {
        let cacheKey = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        let cacheFile = diskCacheURL.appendingPathComponent("\(cacheKey).jpg")
        
        guard FileManager.default.fileExists(atPath: cacheFile.path),
              let image = NSImage(contentsOf: cacheFile)
        else {
            return nil
        }
        
        return image
    }
    
    private func cacheToDisk(_ image: NSImage, for url: URL) async {
        let cacheKey = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        let cacheFile = diskCacheURL.appendingPathComponent("\(cacheKey).jpg")
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else {
            return
        }
        
        try? jpegData.write(to: cacheFile, options: .atomic)
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
        
        // 使用 CGImage 和 CGContext 来避免 Metal 的对齐问题
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
}
