//
//  NowPlayingService.swift
//  Me2Tune
//
//  Now Playing 信息管理 - 更新系统媒体控制中心 + 定时器管理
//

import AppKit

import Foundation
import MediaPlayer
import OSLog

private let logger = Logger.nowPlaying

@MainActor
final class NowPlayingService {
    static let shared = NowPlayingService()
    
    // MARK: - Private Properties
    
    private var updateTimerTask: Task<Void, Never>?
    private var currentTimeProvider: (() -> TimeInterval)?
    
    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "nowPlayingEnabled") as? Bool ?? true
    }
    
    private init() {}
    
    // MARK: - Public Methods
    
    func updateNowPlayingInfo(
        track: AudioTrack,
        artwork: NSImage?,
        currentTime: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool
    ) {
        logger.debug("📻 Updating Now Playing Info")
        var nowPlayingInfo: [String: Any] = [:]
        
        // 基本信息
        nowPlayingInfo[MPMediaItemPropertyTitle] = track.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = track.artist ?? String(localized: "unknown_artist")
        if let albumTitle = track.albumTitle {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = albumTitle
        }
        
        // 封面图片
        if let artwork,
           let artworkData = artwork.tiffRepresentation
        {
            let size = artwork.size
            let mediaArtwork = MPMediaItemArtwork(boundsSize: size) { @Sendable _ in
                // 在闭包内从数据重新创建图片，确保线程安全
                NSImage(data: artworkData) ?? NSImage()
            }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = mediaArtwork
        }
        
        // 时长和进度
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        
        // 播放速率（0.0 = 暂停，1.0 = 播放）
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        
        logger.debug("🎵 Updated Now Playing: \(track.title)")
    }
    
    func updatePlaybackState(isPlaying: Bool) {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            return
        }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    func updatePlaybackTime(currentTime: TimeInterval) {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            return
        }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
   
        logger.debug("🧹 Cleared Now Playing info")
    }
    
    // MARK: - Timer Management
    
    /// 处理播放状态变化，自动管理定时器
    func handlePlaybackStateChange(
        isPlaying: Bool,
        isWindowVisible: Bool,
        currentTimeProvider: @escaping () -> TimeInterval
    ) {
        self.currentTimeProvider = currentTimeProvider
        
        if isPlaying, isWindowVisible, isEnabled {
            startUpdateTimer()
        } else {
            stopUpdateTimer()
        }
    }
    
    /// 窗口可见性变化时调用
    func handleWindowVisibilityChange(isVisible: Bool, isPlaying: Bool) {
        guard isEnabled else { return }
        
        if isPlaying, isVisible {
            startUpdateTimer()
        } else {
            stopUpdateTimer()
        }
    }
    
    func stopUpdateTimer() {
        updateTimerTask?.cancel()
        updateTimerTask = nil
    }
    
    // MARK: - Private Methods
    
    private func startUpdateTimer() {
        stopUpdateTimer()
        
        updateTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5), clock: .continuous)
                if Task.isCancelled { break }
                
                if let self, let provider = self.currentTimeProvider {
                    self.updatePlaybackTime(currentTime: provider())
                }
            }
        }
    }
}
