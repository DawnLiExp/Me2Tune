//
//  PlaybackProgressController.swift
//  Me2Tune
//
//  Full 界面播放进度轮询控制器
//

import Foundation

@MainActor
final class PlaybackProgressController {
    typealias TimeProvider = @MainActor () -> TimeInterval
    typealias TickHandler = @MainActor (TimeInterval) -> Void
    typealias IntervalResolver = @MainActor (WindowStateMonitor.WindowVisibilityState) -> TimeInterval

    private let timeProvider: TimeProvider
    private let tickHandler: TickHandler
    private let intervalResolver: IntervalResolver

    private var isPlaying = false
    private var visibilityState: WindowStateMonitor.WindowVisibilityState = .activeFocused
    private var pollingTask: Task<Void, Never>?

    init(
        timeProvider: @escaping TimeProvider,
        tickHandler: @escaping TickHandler
    ) {
        self.timeProvider = timeProvider
        self.tickHandler = tickHandler
        self.intervalResolver = { state in
            switch state {
            case .activeFocused:
                return 0.3
            case .inactive:
                return 0.5
            case .hidden, .miniVisible, .miniHidden:
                return 0
            }
        }
    }

    init(
        timeProvider: @escaping TimeProvider,
        tickHandler: @escaping TickHandler,
        intervalResolver: @escaping IntervalResolver
    ) {
        self.timeProvider = timeProvider
        self.tickHandler = tickHandler
        self.intervalResolver = intervalResolver
    }

    func updatePlaybackState(isPlaying: Bool) {
        guard self.isPlaying != isPlaying else { return }
        self.isPlaying = isPlaying
        rebuildPollingTaskIfNeeded()
    }

    func updateVisibilityState(_ state: WindowStateMonitor.WindowVisibilityState) {
        let previousShouldPoll = shouldPoll
        let previousInterval = currentInterval

        visibilityState = state

        let nextShouldPoll = shouldPoll
        if !previousShouldPoll && nextShouldPoll {
            refreshNow()
            return
        }

        let intervalChanged = previousShouldPoll && nextShouldPoll && previousInterval != currentInterval
        rebuildPollingTaskIfNeeded(force: intervalChanged)
    }

    func refreshNow() {
        tickHandler(timeProvider())
        rebuildPollingTaskIfNeeded()
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    nonisolated func stopFromDeinit() {
        Task { @MainActor [weak self] in
            self?.stop()
        }
    }

    private var shouldPoll: Bool {
        guard isPlaying else { return false }
        return visibilityState == .activeFocused || visibilityState == .inactive
    }

    private var currentInterval: TimeInterval {
        intervalResolver(visibilityState)
    }

    private func rebuildPollingTaskIfNeeded(force: Bool = false) {
        let shouldStartPolling = shouldPoll
        let hasActivePollingTask = pollingTask != nil

        if !force, shouldStartPolling == hasActivePollingTask {
            return
        }

        stop()
        guard shouldStartPolling else { return }

        let interval = currentInterval
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval), clock: .continuous)
                guard !Task.isCancelled, let self else { break }
                guard self.shouldPoll else { break }

                let time = self.timeProvider()
                self.tickHandler(time)
            }

            self?.pollingTask = nil
        }
    }
}
