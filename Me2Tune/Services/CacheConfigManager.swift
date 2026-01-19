//
//  CacheConfigManager.swift
//  Me2Tune
//
//  缓存配置管理器 - 统一管理缓存路径和数量限制
//

import AppKit
import Combine
import Foundation
import OSLog

private let logger = Logger(subsystem: "me2.Me2Tune", category: "CacheConfig")

@MainActor
final class CacheConfigManager: ObservableObject {
    static let shared = CacheConfigManager()
    
    // MARK: - Constants
    
    /// 缓存文件数量上限（封面和歌词分别限制）
    nonisolated static let maxCacheCount = 9527
    
    private nonisolated static let customPathKey = "CustomCachePath"
    
    // MARK: - Published Properties
    
    @Published private(set) var customCachePath: URL?
    @Published private(set) var isCustomPathWritable: Bool = true
    
    // MARK: - Computed Properties
    
    /// 歌词缓存目录
    var lyricsCacheDirectory: URL {
        currentCacheRoot.appendingPathComponent("Lyrics", isDirectory: true)
    }
    
    /// 封面缓存目录
    var artworkCacheDirectory: URL {
        currentCacheRoot.appendingPathComponent("Artwork", isDirectory: true)
    }
    
    /// 当前使用的缓存根目录
    private var currentCacheRoot: URL {
        if let customPath = customCachePath, isCustomPathWritable {
            return customPath.appendingPathComponent("Me2Tune", isDirectory: true)
        }
        return Self.defaultCacheRoot
    }
    
    // MARK: - Static Helpers (for actor isolation)
    
    /// 默认缓存根目录
    private nonisolated static var defaultCacheRoot: URL {
        FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Me2Tune", isDirectory: true)
    }
    
    /// 获取歌词缓存目录（非隔离静态方法，供 actor 使用）
    nonisolated static func getLyricsCacheDirectory() -> URL {
        if let customPath = loadCustomPath(), validateDirectoryWritability(customPath) {
            return customPath.appendingPathComponent("Me2Tune/Lyrics", isDirectory: true)
        }
        return defaultCacheRoot.appendingPathComponent("Lyrics", isDirectory: true)
    }
    
    /// 获取封面缓存目录（非隔离静态方法，供 actor 使用）
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
        
        logger.info("CacheConfigManager initialized")
        logger.info("Lyrics cache: \(self.lyricsCacheDirectory.path)")
        logger.info("Artwork cache: \(self.artworkCacheDirectory.path)")
    }
    
    // MARK: - Public Methods
    
    /// 设置自定义缓存路径
    func setCustomCachePath(_ url: URL?) {
        if let url {
            // 验证目录可写性
            let writability = Self.validateDirectoryWritability(url)
            isCustomPathWritable = writability
            
            if writability {
                customCachePath = url
                UserDefaults.standard.set(url.path, forKey: Self.customPathKey)
                ensureDirectoriesExist()
                logger.info("✅ Custom cache path set: \(url.path)")
            } else {
                logger.warning("❌ Custom path not writable: \(url.path)")
            }
        } else {
            // 恢复默认路径
            customCachePath = nil
            isCustomPathWritable = true
            UserDefaults.standard.removeObject(forKey: Self.customPathKey)
            ensureDirectoriesExist()
            logger.info("🔄 Reset to default cache path")
        }
    }
    
    /// 验证当前配置的目录可写性
    func validateCurrentPath() -> Bool {
        let path = currentCacheRoot
        let writable = Self.validateDirectoryWritability(path)
        isCustomPathWritable = writable
        return writable
    }
    
    /// 在 Finder 中显示缓存目录
    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([currentCacheRoot])
    }
    
    // MARK: - Private Methods
    
    private func loadCustomPath() {
        if let url = Self.loadCustomPath() {
            let writable = Self.validateDirectoryWritability(url)
            customCachePath = url
            isCustomPathWritable = writable
            
            if writable {
                logger.info("Loaded custom cache path: \(url.path)")
            } else {
                logger.warning("Saved custom path not writable: \(url.path)")
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
                    logger.debug("Created cache directory: \(directory.lastPathComponent)")
                } catch {
                    logger.error("Failed to create directory: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private nonisolated static func validateDirectoryWritability(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        
        // 检查目录是否存在
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        
        if !exists {
            // 尝试创建目录
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
        
        // 检查写权限
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
