//
//  PersistenceService.swift
//  Me2Tune
//
//  持久化服务 - 分离播放状态和列表内容
//

import Foundation
import OSLog

// MARK: - Playback State

struct PlaybackState: Codable, Sendable, Equatable {
    var playlistCurrentIndex: Int?
    var albumCurrentIndex: Int?
    var playingSource: PlayingSourceData?
    var volume: Double?

    enum PlayingSourceData: Codable, Sendable, Equatable {
        case playlist
        case album(UUID)
    }
}

// MARK: - Playlist Content

struct PlaylistContent: Codable, Sendable {
    var tracks: [AudioTrack]
}

struct CollectionState: Codable, Sendable {
    var albums: [Album]
}

@MainActor
final class PersistenceService {
    private let playbackStateFileURL: URL
    private let playlistContentFileURL: URL
    private let collectionFileURL: URL
    private let logger = Logger.persistence

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let appDirectory = appSupport.appendingPathComponent("Me2Tune", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        playbackStateFileURL = appDirectory.appendingPathComponent("playbackState.json")
        playlistContentFileURL = appDirectory.appendingPathComponent("playlistContent.json")
        collectionFileURL = appDirectory.appendingPathComponent("collections.json")

        logger.debug("Persistence paths initialized")
    }

    // MARK: - Playback State (轻量级，高频保存)

    func savePlaybackState(_ state: PlaybackState) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        try data.write(to: playbackStateFileURL, options: .atomic)
        logger.debug("💾 Playback state saved (source: \(String(describing: state.playingSource)))")
    }

    func loadPlaybackState() throws -> PlaybackState {
        let data = try Data(contentsOf: playbackStateFileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(PlaybackState.self, from: data)
    }

    // MARK: - Playlist Content (重量级，仅内容变化时保存)

    func savePlaylistContent(_ content: PlaylistContent) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        try data.write(to: playlistContentFileURL, options: .atomic)
        logger.debug("💾 Playlist content saved (\(content.tracks.count) tracks)")
    }

    func loadPlaylistContent() throws -> PlaylistContent {
        let data = try Data(contentsOf: playlistContentFileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(PlaylistContent.self, from: data)
    }

    // MARK: - Collections

    func save(_ state: CollectionState) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        try data.write(to: collectionFileURL, options: .atomic)
        logger.debug("Collection state saved with \(state.albums.count) albums")
    }

    func loadCollections() throws -> CollectionState {
        let data = try Data(contentsOf: collectionFileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(CollectionState.self, from: data)
    }
}
