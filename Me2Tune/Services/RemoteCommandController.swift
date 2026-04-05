//
//  RemoteCommandController.swift
//  Me2Tune
//
//  媒体快捷键控制器 - handlers 模式
//

import Foundation
import MediaPlayer
import OSLog

private let logger = Logger.remoteCommand

@MainActor
final class RemoteCommandController {
    static let shared = RemoteCommandController()

    private var isEnabled = false
    private var handlers: PlaybackCommandHandlers?

    private init() {}

    // MARK: - Public Methods

    func register(handlers: PlaybackCommandHandlers) {
        self.handlers = handlers
    }

    func enable() {
        guard !isEnabled else { return }
        guard handlers != nil else {
            logger.warning("Cannot enable media keys before handlers registration")
            return
        }

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let self, let handlers = self.handlers else { return .commandFailed }
            Task { @MainActor in
                if !handlers.isPlaying() {
                    handlers.play()
                }
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let self, let handlers = self.handlers else { return .commandFailed }
            Task { @MainActor in
                if handlers.isPlaying() {
                    handlers.pause()
                }
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let self, let handlers = self.handlers else { return .commandFailed }
            Task { @MainActor in
                handlers.togglePlayPause()
            }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let self, let handlers = self.handlers else { return .commandFailed }
            Task { @MainActor in
                if handlers.canGoNext() {
                    handlers.next()
                }
            }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let self, let handlers = self.handlers else { return .commandFailed }
            Task { @MainActor in
                if handlers.canGoPrevious() {
                    handlers.previous()
                }
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event -> MPRemoteCommandHandlerStatus in
            guard let self,
                  let handlers = self.handlers,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent
            else {
                return .commandFailed
            }

            Task { @MainActor in
                handlers.seek(positionEvent.positionTime)
            }
            return .success
        }

        isEnabled = true
        logger.info("Media keys enabled")
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

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

        isEnabled = false
        logger.info("Media keys disabled")
    }
}
