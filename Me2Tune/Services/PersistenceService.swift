//
//  PersistenceService.swift
//  Me2Tune
//
//  播放列表持久化服务 - 优化版：缓存元数据 + UI状态记忆
//

import Foundation
import OSLog

struct PlaylistState: Codable, Sendable {
    var tracks: [AudioTrack]
    var currentIndex: Int?
}

struct CollectionState: Codable, Sendable {
    var albums: [Album]
}

struct UIState: Codable, Sendable {
    var isArtworkExpanded: Bool
    var isPlaylistVisible: Bool
    var windowHeight: CGFloat
    var windowX: CGFloat?
    var windowY: CGFloat?

    static let `default` = UIState(
        isArtworkExpanded: true,
        isPlaylistVisible: true,
        windowHeight: 900,
        windowX: nil,
        windowY: nil,
    )
}

actor PersistenceService {
    private let fileURL: URL
    private let collectionFileURL: URL
    private let uiStateFileURL: URL
    private let logger = Logger(subsystem: "me2.Me2Tune", category: "PersistenceService")

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first!

        let appDirectory = appSupport.appendingPathComponent("Me2Tune", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        fileURL = appDirectory.appendingPathComponent("playlist.json")
        collectionFileURL = appDirectory.appendingPathComponent("collections.json")
        uiStateFileURL = appDirectory.appendingPathComponent("uiState.json")

        logger.debug("Persistence paths initialized")
    }

    // MARK: - Playlist

    func save(_ state: PlaylistState) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
        logger.debug("Playlist state saved with \(state.tracks.count) tracks")
    }

    func load() async throws -> PlaylistState {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(PlaylistState.self, from: data)
    }

    // MARK: - Collections

    func save(_ state: CollectionState) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        try data.write(to: collectionFileURL, options: .atomic)
        logger.debug("Collection state saved with \(state.albums.count) albums")
    }

    func loadCollections() async throws -> CollectionState {
        let data = try Data(contentsOf: collectionFileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(CollectionState.self, from: data)
    }

    // MARK: - UI State

    func save(_ state: UIState) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        try data.write(to: uiStateFileURL, options: .atomic)
        logger.debug("UI state saved: artwork=\(state.isArtworkExpanded), playlist=\(state.isPlaylistVisible), height=\(state.windowHeight), pos=(\(state.windowX ?? 0), \(state.windowY ?? 0))")
    }

    func loadUIState() async throws -> UIState {
        let data = try Data(contentsOf: uiStateFileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(UIState.self, from: data)
    }
}
