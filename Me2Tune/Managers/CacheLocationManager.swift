//
//  CacheLocationManager.swift
//  Me2Tune
//
//  缓存目录管理器 - 统一管理封面和歌词缓存位置
//

import AppKit
import Combine
import Foundation
import OSLog

private nonisolated let logger = Logger(subsystem: "me2.Me2Tune", category: "CacheLocation")

final class CacheLocationManager: ObservableObject, Sendable {
    static let shared = CacheLocationManager()
    
    // MARK: - Published State
    
    @Published private(set) var currentCacheRoot: URL
    
    // MARK: - Constants
    
    private let userDefaultsKey = "CustomCacheLocation"
    private let defaultCachePath = "Me2Tune"
    
    // MARK: - Computed Properties
    
    var artworkCacheDirectory: URL {
        currentCacheRoot.appendingPathComponent("Artwork", isDirectory: true)
    }
    
    var lyricsCacheDirectory: URL {
        currentCacheRoot.appendingPathComponent("Lyrics", isDirectory: true)
    }
    
    // MARK: - Initialization
    
    private init() {
        // 加载用户自定义路径或使用默认路径
        if let customPath = UserDefaults.standard.string(forKey: userDefaultsKey),
           let customURL = URL(string: customPath),
           FileManager.default.fileExists(atPath: customURL.path) {
            self.currentCacheRoot = customURL
            logger.info("使用自定义缓存路径: \(customURL.path)")
        } else {
            // 默认路径：~/Library/Caches/Me2Tune
            let systemCacheDir = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first!
            self.currentCacheRoot = systemCacheDir.appendingPathComponent(defaultCachePath, isDirectory: true)
            logger.info("使用默认缓存路径: \(self.currentCacheRoot.path)")
        }
        
        // 确保目录存在
        createDirectoriesIfNeeded()
    }
    
    // MARK: - Public Methods
    
    /// 设置自定义缓存路径
    func setCustomCacheLocation(_ url: URL) {
        guard url.hasDirectoryPath else {
            logger.error("提供的路径不是目录: \(url.path)")
            return
        }
        
        // 保存到 UserDefaults
        UserDefaults.standard.set(url.absoluteString, forKey: userDefaultsKey)
        
        // 更新当前路径
        currentCacheRoot = url
        
        // 创建子目录
        createDirectoriesIfNeeded()
        
        logger.info("缓存路径已更新: \(url.path)")
    }
    
    /// 重置为默认路径
    func resetToDefaultLocation() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        
        let systemCacheDir = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!
        currentCacheRoot = systemCacheDir.appendingPathComponent(defaultCachePath, isDirectory: true)
        
        createDirectoriesIfNeeded()
        
        logger.info("缓存路径已重置为默认: \(self.currentCacheRoot.path)")
    }
    
    /// 在访达中显示缓存目录
    func revealInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: currentCacheRoot.path)
    }
    
    // MARK: - Private Methods
    
    private func createDirectoriesIfNeeded() {
        let directories = [
            currentCacheRoot,
            artworkCacheDirectory,
            lyricsCacheDirectory
        ]
        
        for directory in directories {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            } catch {
                logger.error("创建目录失败: \(directory.path) - \(error.localizedDescription)")
            }
        }
    }
}
