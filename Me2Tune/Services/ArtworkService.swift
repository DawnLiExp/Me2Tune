//
//  ArtworkService.swift
//  Me2Tune
//
//  封面图片提取服务
//

import AppKit
import SFBAudioEngine

actor ArtworkService {
    private var cache: [URL: NSImage] = [:]
    
    // MARK: - Public Methods
    
    func artwork(for url: URL) async -> NSImage? {
        if let cached = cache[url] {
            return cached
        }
        
        // 尝试从音频文件内嵌封面提取
        if let embedded = await extractEmbeddedArtwork(from: url) {
            cache[url] = embedded
            return embedded
        }
        
        // 尝试从目录中查找图片
        if let folder = await extractFolderArtwork(from: url) {
            cache[url] = folder
            return folder
        }
        
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
            options: [.skipsHiddenFiles],
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
