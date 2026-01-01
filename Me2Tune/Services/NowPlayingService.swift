//
//  NowPlayingService.swift
//  Me2Tune
//
//  Now Playing 信息管理 - 更新系统媒体控制中心
//

import AppKit
import Foundation
import MediaPlayer
import OSLog

private let logger = Logger.nowPlaying

@MainActor
final class NowPlayingService {
    static let shared = NowPlayingService()
    
    private init() {}
    
    // MARK: - Public Methods
    
    func updateNowPlayingInfo(
        track: AudioTrack,
        artwork: NSImage?,
        currentTime: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool
    ) {
        var nowPlayingInfo: [String: Any] = [:]
        
        // 基本信息
        nowPlayingInfo[MPMediaItemPropertyTitle] = track.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = track.artist ?? "Unknown Artist"
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
}
