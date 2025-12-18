//
//  ArtworkService.swift
//  Me2Tune
//
//  封面图片提取服务
//

import AppKit
import SFBAudioEngine
import OSLog

actor ArtworkService {
    private var cache: [URL: NSImage] = [:]
    private let logger = Logger(subsystem: "me2.Me2Tune", category: "ArtworkService")
    
    // MARK: - Public Methods
    
    func artwork(for url: URL) async -> NSImage? {
        if let cached = cache[url] {
            return cached
        }
        
        if let embedded = await extractEmbeddedArtwork(from: url) {
            cache[url] = embedded
            logger.debug("Extracted embedded artwork for: \(url.lastPathComponent)")
            return embedded
        }
        
        if let folder = await extractFolderArtwork(from: url) {
            cache[url] = folder
            logger.debug("Found folder artwork for: \(url.lastPathComponent)")
            return folder
        }
        
        logger.info("No artwork found for: \(url.lastPathComponent)")
        return nil
    }
    
    // MARK: - Private Methods
    
    private func extractEmbeddedArtwork(from url: URL) async -> NSImage? {
        guard let audioFile = try? AudioFile(readingPropertiesAndMetadataFrom: url) else {
            return nil
        }
        
        let metadata = audioFile.metadata
        let attachedPictures = metadata.attachedPictures
        
        guard !attachedPictures.isEmpty,
              let firstPicture = attachedPictures.first
        else {
            return nil
        }
        
        let imageData = firstPicture.imageData
        return NSImage(data: imageData)
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
        
        return image
    }
}
