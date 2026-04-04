//
//  PlaybackPersistenceController.swift
//  Me2Tune
//
//  Coordinates debounced and periodic playback persistence scheduling.
//

import Foundation
import OSLog

@MainActor
final class PlaybackPersistenceController {
    private var saveTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?

    private let saveDebounce: Duration
    private let volumeDebounce: Duration
    private let periodicInterval: Duration

    private let saveHandler: @MainActor (Double?) -> Void
    private let volumeApplyHandler: @MainActor (Double) -> Void

    private let logger = Logger.persistence

    init(
        saveDebounce: Duration = .milliseconds(50),
        volumeDebounce: Duration = .milliseconds(500),
        periodicInterval: Duration = .seconds(5),
        saveHandler: @escaping @MainActor (Double?) -> Void,
        volumeApplyHandler: @escaping @MainActor (Double) -> Void
    ) {
        self.saveDebounce = saveDebounce
        self.volumeDebounce = volumeDebounce
        self.periodicInterval = periodicInterval
        self.saveHandler = saveHandler
        self.volumeApplyHandler = volumeApplyHandler
    }

    func scheduleSave(volume: Double? = nil) {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: saveDebounce)
            guard !Task.isCancelled else { return }
            saveHandler(volume)
        }
    }

    func scheduleVolumeApply(_ volume: Double) {
        volumeTask?.cancel()
        volumeTask = Task { @MainActor in
            try? await Task.sleep(for: volumeDebounce)
            guard !Task.isCancelled else { return }
            volumeApplyHandler(volume)
        }
    }

    func startPeriodicSave(volumeProvider: @escaping @MainActor () -> Double) {
        stopPeriodicSave()
        periodicTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: periodicInterval, clock: .continuous)
                guard !Task.isCancelled else { break }
                saveHandler(volumeProvider())
            }
        }
        logger.debug("Periodic persistence started")
    }

    func stopPeriodicSave() {
        periodicTask?.cancel()
        periodicTask = nil
    }

    func cancelAll() {
        saveTask?.cancel()
        saveTask = nil
        volumeTask?.cancel()
        volumeTask = nil
        stopPeriodicSave()
    }

    nonisolated func cancelAllFromDeinit() {
        Task { @MainActor [weak self] in
            self?.cancelAll()
        }
    }
}
