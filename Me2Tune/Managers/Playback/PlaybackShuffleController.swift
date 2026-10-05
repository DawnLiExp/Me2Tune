//
//  PlaybackShuffleController.swift
//  Me2Tune
//
//  Manages shuffle playback queue, history stack, and deterministic track selection.
//

import Foundation
import Observation
import OSLog

@MainActor
final class PlaybackShuffleController {
    private enum Key {
        static let isShuffleEnabled = "isShuffleEnabled"
    }

    private let logger = Logger.coordinator

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Key.isShuffleEnabled)
            logger.debug("Shuffle mode changed: \(self.isEnabled)")
        }
    }

    /// Shuffled upcoming track IDs to play next
    private(set) var upcomingIDs: [UUID] = []

    /// Stack of previously played track IDs
    private(set) var historyIDs: [UUID] = []

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Key.isShuffleEnabled)
    }

    /// Reshuffles upcoming tracks based on currently available tracks.
    func reshuffle(
        tracks: [AudioTrack],
        currentTrackID: UUID?,
        preserveHistory: Bool = false
    ) {
        if !preserveHistory {
            historyIDs.removeAll()
        }
        guard !tracks.isEmpty else {
            upcomingIDs.removeAll()
            return
        }

        let candidates = tracks.filter { $0.id != currentTrackID }.map(\.id)
        upcomingIDs = candidates.shuffled()
        logger.debug("Reshuffled \(self.upcomingIDs.count) tracks (current: \(String(describing: currentTrackID)))")
    }

    /// Toggles shuffle mode, reinitializing or clearing shuffle queue.
    func toggle(tracks: [AudioTrack], currentTrackID: UUID?) {
        isEnabled.toggle()
        if isEnabled {
            reshuffle(tracks: tracks, currentTrackID: currentTrackID, preserveHistory: false)
        } else {
            upcomingIDs.removeAll()
            historyIDs.removeAll()
        }
    }

    /// Peeks or finds next valid track without mutating state.
    func peekNextValidTrackID(
        tracks: [AudioTrack],
        currentTrackID: UUID?,
        repeatMode: RepeatMode,
        failedIDs: Set<UUID>
    ) -> UUID? {
        guard !tracks.isEmpty else { return nil }

        // 1. Try finding a valid track in upcoming queue
        for id in upcomingIDs {
            if !failedIDs.contains(id), tracks.contains(where: { $0.id == id }) {
                return id
            }
        }

        // 2. If upcoming is exhausted (or empty), check repeatMode
        if repeatMode == .all {
            let available = tracks.filter { !failedIDs.contains($0.id) }
            guard !available.isEmpty else { return nil }

            if available.count == 1 {
                return available.first?.id
            }

            let others = available.filter { $0.id != currentTrackID }
            return (others.first ?? available.first)?.id
        }

        return nil
    }

    /// Retrieves and consumes the next valid track ID, updating upcoming and history stacks.
    func consumeNextValidTrackID(
        tracks: [AudioTrack],
        currentTrackID: UUID?,
        repeatMode: RepeatMode,
        failedIDs: Set<UUID>
    ) -> UUID? {
        guard !tracks.isEmpty else { return nil }

        // Find index of first valid track in upcomingIDs
        while !upcomingIDs.isEmpty {
            let candidateID = upcomingIDs.removeFirst()
            if !failedIDs.contains(candidateID), tracks.contains(where: { $0.id == candidateID }) {
                if let currentTrackID {
                    historyIDs.append(currentTrackID)
                }
                return candidateID
            }
        }

        // Upcoming is exhausted: if repeatMode == .all, refill and reshuffle!
        if repeatMode == .all {
            let available = tracks.filter { !failedIDs.contains($0.id) }
            guard !available.isEmpty else { return nil }

            if available.count == 1 {
                let singleID = available[0].id
                if let currentTrackID, currentTrackID != singleID {
                    historyIDs.append(currentTrackID)
                }
                return singleID
            }

            let candidates = available.filter { $0.id != currentTrackID }.map(\.id)
            upcomingIDs = (candidates.isEmpty ? available.map(\.id) : candidates).shuffled()

            if !upcomingIDs.isEmpty {
                let chosenID = upcomingIDs.removeFirst()
                if let currentTrackID {
                    historyIDs.append(currentTrackID)
                }
                return chosenID
            }
        }

        return nil
    }

    /// Retrieves and consumes the previous track ID from history.
    func consumePreviousTrackID(
        tracks: [AudioTrack],
        currentTrackID: UUID?,
        failedIDs: Set<UUID>
    ) -> UUID? {
        while !historyIDs.isEmpty {
            let candidateID = historyIDs.removeLast()
            if !failedIDs.contains(candidateID), tracks.contains(where: { $0.id == candidateID }) {
                if let currentTrackID {
                    // Put current track back to the top of upcoming so "Next" returns to it
                    upcomingIDs.insert(currentTrackID, at: 0)
                }
                return candidateID
            }
        }
        return nil
    }

    /// Called when a track starts playing (manual selection, auto transition, or direct switch).
    func handleTrackStarted(newTrackID: UUID, previousTrackID: UUID?, tracks: [AudioTrack]) {
        guard isEnabled else { return }

        // If upcoming is empty, populate with remaining tracks in the current list
        if upcomingIDs.isEmpty {
            let existingHistory = Set(historyIDs)
            let remaining = tracks.filter { $0.id != newTrackID && !existingHistory.contains($0.id) }.map(\.id)
            if !remaining.isEmpty {
                upcomingIDs = remaining.shuffled()
            }
        }

        upcomingIDs.removeAll { $0 == newTrackID }

        if let previousTrackID, previousTrackID != newTrackID {
            if historyIDs.last != previousTrackID {
                historyIDs.append(previousTrackID)
            }
        }
    }

    /// Updates internal IDs when tracks are removed.
    func handleTracksRemoved(removedIDs: Set<UUID>) {
        upcomingIDs.removeAll { removedIDs.contains($0) }
        historyIDs.removeAll { removedIDs.contains($0) }
    }

    /// Updates internal IDs when new tracks are added.
    func handleTracksAdded(newTracks: [AudioTrack]) {
        guard isEnabled else { return }
        let existingIDs = Set(upcomingIDs).union(historyIDs)
        let freshIDs = newTracks.map(\.id).filter { !existingIDs.contains($0) }
        if !freshIDs.isEmpty {
            upcomingIDs.append(contentsOf: freshIDs.shuffled())
        }
    }

    /// Resets all queues.
    func reset() {
        upcomingIDs.removeAll()
        historyIDs.removeAll()
    }
}
