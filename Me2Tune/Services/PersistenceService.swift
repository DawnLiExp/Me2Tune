//
//  PersistenceService.swift
//  Me2Tune
//
//  播放列表持久化服务
//

import Foundation
import OSLog

struct PlaylistState: Codable, Sendable {
    var trackURLs: [URL]
    var currentIndex: Int?
}

struct CollectionState: Codable, Sendable {
    var albums: [Album]
}

actor PersistenceService {
    private let fileURL: URL
    private let collectionFileURL: URL
    private let logger = Logger(subsystem: "me2.Me2Tune", category: "PersistenceService")

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let appDirectory = appSupport.appendingPathComponent("Me2Tune", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        fileURL = appDirectory.appendingPathComponent("playlist.json")
        collectionFileURL = appDirectory.appendingPathComponent("collections.json")
        
        logger.debug("Persistence paths initialized")
    }

    func save(_ state: PlaylistState) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
        logger.debug("Playlist state saved")
    }

    func save(_ state: CollectionState) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        try data.write(to: collectionFileURL, options: .atomic)
        logger.debug("Collection state saved")
    }

    func load() async throws -> PlaylistState {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(PlaylistState.self, from: data)
    }

    func loadCollections() async throws -> CollectionState {
        let data = try Data(contentsOf: collectionFileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(CollectionState.self, from: data)
    }
}
