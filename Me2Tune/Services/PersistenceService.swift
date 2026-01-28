//
//  PersistenceService.swift
//  Me2Tune
//
//  持久化服务 - 单例模式 @MainActor
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
    // ✅ 单例模式
    static let shared = PersistenceService()
    
    private let playbackStateFileURL: URL
    private let playlistContentFileURL: URL
    private let collectionFileURL: URL
    private let logger = Logger.persistence

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let appDirectory = appSupport.appendingPathComponent("Me2Tune", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        playbackStateFileURL = appDirectory.appendingPathComponent("playbackState.json")
        playlistContentFileURL = appDirectory.appendingPathComponent("playlistContent.json")
        collectionFileURL = appDirectory.appendingPathComponent("collections.json")

        logger.debug("💾 PersistenceService initialized (singleton)")
    }

    // MARK: - Playback State

    func savePlaybackState(_ state: PlaybackState) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        try data.write(to: playbackStateFileURL, options: .atomic)
        logger.debug("💾 Playback state saved")
    }

    func loadPlaybackState() throws -> PlaybackState {
        let data = try Data(contentsOf: playbackStateFileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(PlaybackState.self, from: data)
    }

    // MARK: - Playlist Content

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
        logger.debug("💾 Collection state saved (\(state.albums.count) albums)")
    }

    func loadCollections() throws -> CollectionState {
        let data = try Data(contentsOf: collectionFileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(CollectionState.self, from: data)
    }
}
