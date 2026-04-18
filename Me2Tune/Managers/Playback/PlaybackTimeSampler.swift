//
//  PlaybackTimeSampler.swift
//  Me2Tune
//
//  Samples playback time while audio is playing and routes the sample to UI and statistics handlers.
//

import Foundation

@MainActor
final class PlaybackTimeSampler {
    typealias TimeProvider = @MainActor () -> TimeInterval
    typealias UIHandler = @MainActor (TimeInterval) -> Void
    typealias StatisticsHandler = @MainActor (TimeInterval) -> Void
    typealias IntervalResolver = @MainActor (WindowStateMonitor.WindowVisibilityState) -> TimeInterval

    private let timeProvider: TimeProvider
    private let uiHandler: UIHandler
    private let statisticsHandler: StatisticsHandler
    private let intervalResolver: IntervalResolver

    private var isPlaying = false
    private var visibilityState: WindowStateMonitor.WindowVisibilityState = .activeFocused
    private var pollingTask: Task<Void, Never>?

    init(
        timeProvider: @escaping TimeProvider,
        uiHandler: @escaping UIHandler,
        statisticsHandler: @escaping StatisticsHandler
    ) {
        self.timeProvider = timeProvider
        self.uiHandler = uiHandler
        self.statisticsHandler = statisticsHandler
        self.intervalResolver = Self.defaultInterval(for:)
    }

    init(
        timeProvider: @escaping TimeProvider,
        uiHandler: @escaping UIHandler,
        statisticsHandler: @escaping StatisticsHandler,
        intervalResolver: @escaping IntervalResolver
    ) {
        self.timeProvider = timeProvider
        self.uiHandler = uiHandler
        self.statisticsHandler = statisticsHandler
        self.intervalResolver = intervalResolver
    }

    func updatePlaybackState(isPlaying: Bool) {
        guard self.isPlaying != isPlaying else { return }
        self.isPlaying = isPlaying
        rebuildPollingTaskIfNeeded()
    }

    func updateVisibilityState(_ state: WindowStateMonitor.WindowVisibilityState) {
        let previousShouldPublishUI = shouldPublishUI
        let previousInterval = currentInterval

        visibilityState = state

        if isPlaying, !previousShouldPublishUI, shouldPublishUI {
            emitSample()
            let intervalChanged = previousInterval != currentInterval
            rebuildPollingTaskIfNeeded(force: intervalChanged)
            return
        }

        let intervalChanged = isPlaying && previousInterval != currentInterval
        rebuildPollingTaskIfNeeded(force: intervalChanged)
    }

    func refreshNow() {
        emitSample()
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

    private var shouldSample: Bool {
        isPlaying
    }

    private var shouldPublishUI: Bool {
        switch visibilityState {
        case .activeFocused, .inactive, .miniVisible:
            true
        case .hidden, .miniHidden:
            false
        }
    }

    private var currentInterval: TimeInterval {
        intervalResolver(visibilityState)
    }

    private func emitSample() {
        let time = timeProvider()
        statisticsHandler(time)
        if shouldPublishUI {
            uiHandler(time)
        }
    }

    private func rebuildPollingTaskIfNeeded(force: Bool = false) {
        let shouldStartPolling = shouldSample
        let hasActivePollingTask = pollingTask != nil

        if !force, shouldStartPolling == hasActivePollingTask {
            return
        }

        stop()
        guard shouldStartPolling else { return }

        let interval = currentInterval
        guard interval > 0 else { return }

        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval), clock: .continuous)
                guard !Task.isCancelled, let self else { break }
                guard self.shouldSample else { break }
                self.emitSample()
            }

            self?.pollingTask = nil
        }
    }

    private static func defaultInterval(for state: WindowStateMonitor.WindowVisibilityState) -> TimeInterval {
        switch state {
        case .activeFocused:
            0.3
        case .inactive:
            0.5
        case .hidden, .miniVisible, .miniHidden:
            1.0
        }
    }
}
