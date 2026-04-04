//
//  TrackNavigationPolicy.swift
//  Me2Tune
//
//  Pure index navigation policy for playback transitions.
//

import Foundation

enum TrackNavigationPolicy {
    static func nextIndex(after index: Int, count: Int, repeatMode: RepeatMode) -> Int? {
        guard count > 0, index >= 0, index < count else { return nil }

        switch repeatMode {
        case .one:
            return index
        case .all:
            return index < count - 1 ? index + 1 : 0
        case .off:
            return index < count - 1 ? index + 1 : nil
        }
    }

    static func previousIndex(before index: Int, count: Int, repeatMode: RepeatMode) -> Int? {
        guard count > 0, index >= 0, index < count else { return nil }

        switch repeatMode {
        case .one:
            return index
        case .all:
            return index > 0 ? index - 1 : count - 1
        case .off:
            return index > 0 ? index - 1 : nil
        }
    }

    static func nextValidIndex(
        after index: Int,
        tracks: [AudioTrack],
        repeatMode: RepeatMode,
        failedIDs: Set<UUID>,
        maxAttempts: Int = 10
    ) -> Int? {
        guard !tracks.isEmpty, maxAttempts > 0 else { return nil }
        guard tracks.indices.contains(index) else { return nil }

        var cursor = index
        var attempts = 0

        while attempts < maxAttempts {
            guard let next = nextIndex(after: cursor, count: tracks.count, repeatMode: repeatMode) else {
                return nil
            }
            if !failedIDs.contains(tracks[next].id) {
                return next
            }
            cursor = next
            attempts += 1
        }

        return nil
    }

    static func previousValidIndex(
        before index: Int,
        tracks: [AudioTrack],
        failedIDs: Set<UUID>
    ) -> Int? {
        guard !tracks.isEmpty else { return nil }
        guard index > 0, index <= tracks.count else { return nil }

        var cursor = index - 1
        while cursor >= 0 {
            if !failedIDs.contains(tracks[cursor].id) {
                return cursor
            }
            cursor -= 1
        }

        return nil
    }

    static func isGaplessAlreadyHandled(currentIndex: Int?, expectedNext: Int?) -> Bool {
        guard let currentIndex, let expectedNext else { return false }
        return currentIndex == expectedNext
    }
}
