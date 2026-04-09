//
//  PlaybackPersistenceController.swift
//  Me2Tune
//
//  Coordinates debounced playback persistence scheduling.
//

import Foundation

@MainActor
final class PlaybackPersistenceController {
    private var saveTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?

    private let saveDebounce: Duration
    private let volumeDebounce: Duration

    private let saveHandler: @MainActor () -> Void
    private let volumeApplyHandler: @MainActor (Double) -> Void

    init(
        saveDebounce: Duration = .milliseconds(200),
        volumeDebounce: Duration = .milliseconds(500),
        saveHandler: @escaping @MainActor () -> Void,
        volumeApplyHandler: @escaping @MainActor (Double) -> Void
    ) {
        self.saveDebounce = saveDebounce
        self.volumeDebounce = volumeDebounce
        self.saveHandler = saveHandler
        self.volumeApplyHandler = volumeApplyHandler
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: saveDebounce)
            guard !Task.isCancelled else { return }
            saveHandler()
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

    func cancelAll() {
        saveTask?.cancel()
        saveTask = nil
        volumeTask?.cancel()
        volumeTask = nil
    }

    nonisolated func cancelAllFromDeinit() {
        Task { @MainActor [weak self] in
            self?.cancelAll()
        }
    }
}
