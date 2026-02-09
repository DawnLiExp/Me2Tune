//
//  CacheConfigManager.swift
//  Me2Tune
//
//  缓存配置管理器 - 统一管理缓存路径和数量限制
//

import AppKit
import Foundation
import Observation
import OSLog

private let logger = Logger.cache

@MainActor
@Observable
final class CacheConfigManager {
    static let shared = CacheConfigManager()
    
    // MARK: - Constants
    
    nonisolated static let maxCacheCount = 9527
    
    private nonisolated static let customPathKey = "CustomCachePath"
    
    // MARK: - Properties
    
    private(set) var customCachePath: URL?
    private(set) var isCustomPathWritable: Bool = true
    
    // MARK: - Computed Properties
    
    var lyricsCacheDirectory: URL {
        currentCacheRoot.appendingPathComponent("Lyrics", isDirectory: true)
    }
    
    var artworkCacheDirectory: URL {
        currentCacheRoot.appendingPathComponent("Artwork", isDirectory: true)
    }
    
    private var currentCacheRoot: URL {
        if let customPath = customCachePath, isCustomPathWritable {
            return customPath.appendingPathComponent("Me2Tune", isDirectory: true)
        }
        return Self.defaultCacheRoot
    }
    
    // MARK: - Static Helpers
    
    private nonisolated static var defaultCacheRoot: URL {
        FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Me2Tune", isDirectory: true)
    }
    
    nonisolated static func getLyricsCacheDirectory() -> URL {
        if let customPath = loadCustomPath(), validateDirectoryWritability(customPath) {
            return customPath.appendingPathComponent("Me2Tune/Lyrics", isDirectory: true)
        }
        return defaultCacheRoot.appendingPathComponent("Lyrics", isDirectory: true)
    }
    
    nonisolated static func getArtworkCacheDirectory() -> URL {
        if let customPath = loadCustomPath(), validateDirectoryWritability(customPath) {
            return customPath.appendingPathComponent("Me2Tune/Artwork", isDirectory: true)
        }
        return defaultCacheRoot.appendingPathComponent("Artwork", isDirectory: true)
    }
    
    // MARK: - Initialization
    
    private init() {
        loadCustomPath()
        ensureDirectoriesExist()
        
        logger.info("Cache manager initialized")
        logger.info("Lyrics: \(self.lyricsCacheDirectory.path)")
        logger.info("Artwork: \(self.artworkCacheDirectory.path)")
    }
    
    // MARK: - Public Methods
    
    func setCustomCachePath(_ url: URL?) {
        if let url {
            let writability = Self.validateDirectoryWritability(url)
            isCustomPathWritable = writability
            
            if writability {
                customCachePath = url
                UserDefaults.standard.set(url.path, forKey: Self.customPathKey)
                ensureDirectoriesExist()
                logger.info("✅ Custom path set: \(url.path)")
            } else {
                logger.warning("❌ Path not writable: \(url.path)")
            }
        } else {
            customCachePath = nil
            isCustomPathWritable = true
            UserDefaults.standard.removeObject(forKey: Self.customPathKey)
            ensureDirectoriesExist()
            logger.info("🔄 Reset to default path")
        }
    }
    
    func validateCurrentPath() -> Bool {
        let path = currentCacheRoot
        let writable = Self.validateDirectoryWritability(path)
        isCustomPathWritable = writable
        return writable
    }
    
    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([currentCacheRoot])
    }
    
    // MARK: - Private Methods
    
    private func loadCustomPath() {
        if let url = Self.loadCustomPath() {
            let writable = Self.validateDirectoryWritability(url)
            customCachePath = url
            isCustomPathWritable = writable
            
            if !writable {
                logger.warning("Saved path not writable: \(url.path)")
            }
        }
    }
    
    private nonisolated static func loadCustomPath() -> URL? {
        guard let pathString = UserDefaults.standard.string(forKey: customPathKey) else {
            return nil
        }
        return URL(fileURLWithPath: pathString)
    }
    
    private func ensureDirectoriesExist() {
        let directories = [lyricsCacheDirectory, artworkCacheDirectory]
        
        for directory in directories {
            if !FileManager.default.fileExists(atPath: directory.path) {
                do {
                    try FileManager.default.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )
                } catch {
                    logger.error("Failed to create directory: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private nonisolated static func validateDirectoryWritability(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        
        if !exists {
            do {
                try fileManager.createDirectory(
                    at: url,
                    withIntermediateDirectories: true
                )
            } catch {
                return false
            }
        } else if !isDirectory.boolValue {
            return false
        }
        
        let testFile = url.appendingPathComponent(".me2tune_write_test")
        
        do {
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try fileManager.removeItem(at: testFile)
            return true
        } catch {
            return false
        }
    }
}
