//
//  PlaybackDecoderQueue.swift
//  Me2Tune
//
//  Tracks playback instances, including repeated instances of the same library track.
//

import Foundation

@MainActor
struct PlaybackDecoderQueue {
    private struct Entry {
        let reference: DecoderReference
        let track: AudioTrack
        var decoded = false
        var notified = false
        var rendered = false
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private(set) var currentID: ObjectIdentifier?
    private(set) var generation = UUID()
    private var ended = false

    var hasQueuedDecoder: Bool { entries.keys.contains { $0 != currentID } }
    var currentTrack: AudioTrack? { currentID.flatMap { entries[$0]?.track } }

    mutating func reset() {
        entries.removeAll()
        currentID = nil
        generation = UUID()
        ended = false
    }

    mutating func register(_ reference: DecoderReference, track: AudioTrack, current: Bool) {
        entries[reference.id] = Entry(reference: reference, track: track)
        if current { currentID = reference.id }
        ended = false
    }

    mutating func activate(_ id: ObjectIdentifier) -> AudioTrack? {
        guard let entry = entries[id] else { return nil }
        if let previous = currentID, previous != id { entries.removeValue(forKey: previous) }
        currentID = id
        return entry.track
    }

    mutating func decoded(_ id: ObjectIdentifier) {
        entries[id]?.decoded = true
    }

    // Preloaded short tracks may decode completely before they become audible.
    mutating func takeCompletedCurrentTrack() -> AudioTrack? {
        guard let id = currentID, var entry = entries[id], entry.decoded, !entry.notified else { return nil }
        entry.notified = true
        entries[id] = entry
        return entry.track
    }

    mutating func rendered(_ id: ObjectIdentifier) {
        entries[id]?.rendered = true
    }

    mutating func remove(_ id: ObjectIdentifier) -> (track: AudioTrack, isCurrent: Bool)? {
        guard let entry = entries.removeValue(forKey: id) else { return nil }
        let isCurrent = currentID == id
        if isCurrent { currentID = nil }
        return (entry.track, isCurrent)
    }

    mutating func takeEnd() -> Bool {
        guard !ended, !hasQueuedDecoder, let id = currentID, entries[id]?.rendered == true else { return false }
        ended = true
        entries.removeAll()
        currentID = nil
        return true
    }
}
