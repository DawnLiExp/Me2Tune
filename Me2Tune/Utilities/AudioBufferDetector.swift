//
//  AudioBufferDetector.swift
//  Me2Tune
//
//  音频缓冲检测器 - 文件系统检测和缓冲大小计算
//

import Foundation
import OSLog

private let logger = Logger.audio

enum AudioBufferDetector {
    // MARK: - Constants
    
    private static let maxBufferSize: Int = 100 * 1024 * 1024 // 100MB
    
    // 缓冲时长（秒）
    private static let localBufferDuration: Double = 1  // SSD: 1秒
    private static let networkBufferDuration: Double = 8.0 // NAS: 8秒
    
    // MARK: - Public Methods
    
    /// 检测是否为网络存储
    static func isNetworkStorage(url: URL) -> Bool {
        // 检查是否为本地文件
        guard url.isFileURL else {
            return true
        }
        
        // 检查卷是否为本地
        if let resourceValues = try? url.resourceValues(forKeys: [.volumeIsLocalKey]),
           let isLocal = resourceValues.volumeIsLocal,
           !isLocal {
            return true
        }
        
        // 检查文件系统类型
        var statfsInfo = statfs()
        guard statfs(url.path, &statfsInfo) == 0 else {
            return false
        }
        
        let fsType = withUnsafePointer(to: &statfsInfo.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                String(cString: $0)
            }
        }
        
        // 网络文件系统类型
        let networkFilesystems = [
            "macfuse",
            "osxfuse",
            "fuse",
            "fusefs",
            "smbfs",
            "nfs",
            "afpfs",
            "webdav"
        ]
        
        let fsTypeLower = fsType.lowercased()
        return networkFilesystems.contains { fsTypeLower.contains($0) }
    }
    
    /// 计算应该预缓冲的字节数
    /// - Parameters:
    ///   - track: 音频曲目
    ///   - isNetworkStorage: 是否为网络存储
    /// - Returns: 缓冲字节数，如果返回 nil 表示文件超过限制不应缓冲
    static func calculateBufferSize(track: AudioTrack, isNetworkStorage: Bool) -> Int? {
        // 检查文件大小
        guard let fileSize = try? FileManager.default.attributesOfItem(atPath: track.url.path)[.size] as? UInt64,
              fileSize <= maxBufferSize else {
            logger.info("File too large for buffering: \(track.url.lastPathComponent)")
            return nil
        }
        
        // 根据存储类型选择缓冲时长
        let bufferDuration = isNetworkStorage ? networkBufferDuration : localBufferDuration
        
        // 获取码率（kbps），默认 320
        let bitrate = track.format.bitrate ?? 320
        
        // 计算缓冲字节数: bitrate (kbps) × duration (s) ÷ 8 × 1024
        let bufferBytes = bitrate * Int(bufferDuration) / 8 * 1024
        
        // 确保不超过文件大小和最大限制
        let actualBufferSize = min(bufferBytes, Int(fileSize), maxBufferSize)
        
        logger.debug("Buffer size: \(actualBufferSize) bytes (\(String(format: "%.1f", bufferDuration))s @ \(bitrate)kbps) - \(track.title)")
        
        return actualBufferSize
    }
}
