//
//  RemoteCommandController.swift
//  Me2Tune
//
//  媒体快捷键控制器 - handlers 模式 + 系统全局/前台键盘按键监听
//

import AppKit
import Foundation
import MediaPlayer
import OSLog

private let logger = Logger.remoteCommand

@MainActor
final class RemoteCommandController {
    static let shared = RemoteCommandController()

    private var isEnabled = false
    private var handlers: PlaybackCommandHandlers?

    private var localSystemMonitor: Any?
    private var localKeyMonitor: Any?

    private var lastActionTime: Date = .distantPast
    private let debounceInterval: TimeInterval = 0.2

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

        // 1. 播放命令
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.handlePlay()
            }
            return .success
        }

        // 2. 暂停命令
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.handlePause()
            }
            return .success
        }

        // 3. 播放/暂停切换命令（MacBook 键盘播放键核心映射）
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.handleTogglePlayPause()
            }
            return .success
        }

        // 4. 下一首命令
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.handleNext()
            }
            return .success
        }

        // 5. 上一首命令
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.handlePrevious()
            }
            return .success
        }

        // 6. 播放进度跳转命令
        commandCenter.changePlaybackPositionCommand.isEnabled = true
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

        // 注册前台键盘监听（捕获硬件媒体键与 F7/F8/F9/空格按键）
        setupLocalEventMonitors()

        // 确保系统媒体控制中心有初始占位信息，避免按键被重定向至 Apple Music
        if MPNowPlayingInfoCenter.default().nowPlayingInfo == nil {
            NowPlayingService.shared.setPlaceholderInfo()
        }

        isEnabled = true
        logger.info("Media keys and remote commands enabled")
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

        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.togglePlayPauseCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false

        if let monitor = localSystemMonitor {
            NSEvent.removeMonitor(monitor)
            localSystemMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }

        MPNowPlayingInfoCenter.default().playbackState = .stopped
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

        isEnabled = false
        logger.info("Media keys and remote commands disabled")
    }

    // MARK: - Action Dispatchers (with Debounce)

    private func shouldThrottleAction() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastActionTime) < debounceInterval {
            return true
        }
        lastActionTime = now
        return false
    }

    func handleTogglePlayPause() {
        guard !shouldThrottleAction() else { return }
        logger.debug("⌨️ Trigger: Toggle Play/Pause")
        handlers?.togglePlayPause()
    }

    func handlePlay() {
        guard !shouldThrottleAction() else { return }
        logger.debug("⌨️ Trigger: Play")
        handlers?.play()
    }

    func handlePause() {
        guard !shouldThrottleAction() else { return }
        logger.debug("⌨️ Trigger: Pause")
        handlers?.pause()
    }

    func handleNext() {
        guard !shouldThrottleAction() else { return }
        logger.debug("⌨️ Trigger: Next Track")
        handlers?.next()
    }

    func handlePrevious() {
        guard !shouldThrottleAction() else { return }
        logger.debug("⌨️ Trigger: Previous Track")
        handlers?.previous()
    }

    // MARK: - Local Keyboard Event Monitors

    private func setupLocalEventMonitors() {
        guard localSystemMonitor == nil, localKeyMonitor == nil else { return }

        // 1. 拦截硬件媒体按键（NX_KEYTYPE_PLAY, NX_KEYTYPE_NEXT, NX_KEYTYPE_PREVIOUS）
        localSystemMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard let self else { return event }
            return self.handleSystemDefinedEvent(event)
        }

        // 2. 拦截标准按键（F7, F8, F9 以及非文本编辑状态下的 Spacebar）
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDownEvent(event)
        }
    }

    private func handleSystemDefinedEvent(_ event: NSEvent) -> NSEvent? {
        // subtype == 8: NX_SUBTYPE_AUXILIARY_CONTROL_BUTTONS
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else {
            return event
        }

        let keyCode = Int((event.data1 & 0xFFFF0000) >> 16)
        let keyFlags = (event.data1 & 0x0000FFFF)
        let isKeyDown = (((keyFlags & 0xFF00) >> 8)) == 0xA

        guard isKeyDown else {
            // 对媒体键的 KeyUp 事件进行消费，防止系统触发蜂鸣声或次级监听
            switch Int32(keyCode) {
            case 16, 17, 18, 19, 20:
                return nil
            default:
                return event
            }
        }

        switch Int32(keyCode) {
        case 16: // NX_KEYTYPE_PLAY (Play/Pause)
            handleTogglePlayPause()
            return nil
        case 17, 19: // NX_KEYTYPE_NEXT, NX_KEYTYPE_FAST
            handleNext()
            return nil
        case 18, 20: // NX_KEYTYPE_PREVIOUS, NX_KEYTYPE_REWIND
            handlePrevious()
            return nil
        default:
            return event
        }
    }

    private func handleKeyDownEvent(_ event: NSEvent) -> NSEvent? {
        // 如果按下了 Command / Control / Option 等组合修饰键，不作快捷键拦截（如 Cmd+W 等保留系统行为）
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty else { return event }

        switch event.keyCode {
        case 100: // F8: 播放 / 暂停
            handleTogglePlayPause()
            return nil
        case 101: // F9: 下一首
            handleNext()
            return nil
        case 98:  // F7: 上一首
            handlePrevious()
            return nil
        case 49:  // Spacebar 空格键
            // 文本框聚焦输入时（如搜索栏、编辑框），保留空格键正常输入行为
            if !isTextInputFocused() {
                handleTogglePlayPause()
                return nil
            }
            return event
        default:
            return event
        }
    }

    private func isTextInputFocused() -> Bool {
        guard let keyWindow = NSApp.keyWindow else { return false }
        if let firstResponder = keyWindow.firstResponder {
            if firstResponder is NSTextView || firstResponder is NSText || firstResponder is NSTextField {
                return true
            }
        }
        return false
    }
}
