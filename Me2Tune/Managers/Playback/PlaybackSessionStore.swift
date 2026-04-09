//
//  PlaybackSessionStore.swift
//  Me2Tune
//
//  会话快照存储 - UserDefaults 持久化播放来源、曲目 ID 与音量
//

import Foundation

// MARK: - Snapshot

struct PlaybackSessionSnapshot: Codable, Equatable {
    enum SourceKind: String, Codable {
        case playlist
        case album
    }

    var sourceKind: SourceKind
    var currentTrackID: UUID?
    var albumID: UUID?
    var volume: Double
    var schemaVersion: Int = 1
}

// MARK: - Store

@MainActor
final class PlaybackSessionStore {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "PlaybackSessionSnapshot_v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> PlaybackSessionSnapshot? {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(PlaybackSessionSnapshot.self, from: data)
        else {
            return nil
        }
        return snapshot
    }

    func save(_ snapshot: PlaybackSessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
