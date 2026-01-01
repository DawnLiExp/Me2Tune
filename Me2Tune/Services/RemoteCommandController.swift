//
//  RemoteCommandController.swift
//  Me2Tune
//
//  媒体快捷键控制器 - 处理系统媒体键和远程命令
//

import Foundation
import MediaPlayer
import OSLog

private let logger = Logger.remoteCommand

@MainActor
final class RemoteCommandController {
    static let shared = RemoteCommandController()
    
    private var isEnabled = false
    private weak var viewModel: PlayerViewModel?
    
    private init() {}
    
    // MARK: - Public Methods
    
    func setup(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }
    
    func enable() {
        guard !isEnabled else { return }
        
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // 播放命令
        commandCenter.playCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let self, let viewModel = self.viewModel else { return .commandFailed }
            Task { @MainActor in
                if !viewModel.isPlaying {
                    viewModel.play()
                }
            }
            return .success
        }
        
        // 暂停命令
        commandCenter.pauseCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let self, let viewModel = self.viewModel else { return .commandFailed }
            Task { @MainActor in
                if viewModel.isPlaying {
                    viewModel.pause()
                }
            }
            return .success
        }
        
        // 切换播放/暂停
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let self, let viewModel = self.viewModel else { return .commandFailed }
            Task { @MainActor in
                viewModel.togglePlayPause()
            }
            return .success
        }
        
        // 下一曲
        commandCenter.nextTrackCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let self, let viewModel = self.viewModel else { return .commandFailed }
            Task { @MainActor in
                if viewModel.canGoNext {
                    viewModel.next()
                }
            }
            return .success
        }
        
        // 上一曲
        commandCenter.previousTrackCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let self, let viewModel = self.viewModel else { return .commandFailed }
            Task { @MainActor in
                if viewModel.canGoPrevious {
                    viewModel.previous()
                }
            }
            return .success
        }
        
        // 进度调整
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event -> MPRemoteCommandHandlerStatus in
            guard let self,
                  let viewModel = self.viewModel,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent
            else {
                return .commandFailed
            }
            
            Task { @MainActor in
                viewModel.seek(to: positionEvent.positionTime)
            }
            return .success
        }
        
        isEnabled = true
        logger.info("✅ Media keys enabled")
    }
    
    func disable() {
        guard isEnabled else { return }
        
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        
        // 清除 Now Playing 信息
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        isEnabled = false
        logger.info("❌ Media keys disabled")
    }
}
