//
//  FailedTrackRegistry.swift
//  Me2Tune
//
//  Stores failed track IDs for playback retry/skip policy.
//

import Foundation
import OSLog

@MainActor
final class FailedTrackRegistry {
    private var failedIDs = Set<UUID>()
    private let logger = Logger.failedTrack

    func mark(_ id: UUID) {
        failedIDs.insert(id)
    }

    func isMarked(_ id: UUID) -> Bool {
        failedIDs.contains(id)
    }

    func clear(_ id: UUID) {
        failedIDs.remove(id)
    }

    func pruneStale(keeping liveIDs: Set<UUID>) {
        let previousCount = failedIDs.count
        failedIDs = failedIDs.intersection(liveIDs)
        if failedIDs.count != previousCount {
            logger.debug("Pruned stale failed IDs: \(previousCount) -> \(self.failedIDs.count)")
        }
    }
}
