//
//  PersistenceService.swift
//  Me2Tune
//
//  播放列表持久化服务
//

import Foundation

struct PlaylistState: Codable {
    var trackURLs: [URL]
    var currentIndex: Int?
}

struct CollectionState: Codable { // 新增
    var albums: [Album]
}

actor PersistenceService {
    private let fileURL: URL
    private let collectionFileURL: URL // 新增

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first!

        let appDirectory = appSupport.appendingPathComponent("Me2Tune", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        fileURL = appDirectory.appendingPathComponent("playlist.json")
        collectionFileURL = appDirectory.appendingPathComponent("collections.json") // 新增
    }

    func save(_ state: PlaylistState) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }

    func save(_ state: CollectionState) async throws { // 新增
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        try data.write(to: collectionFileURL, options: .atomic)
    }

    func load() async throws -> PlaylistState {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(PlaylistState.self, from: data)
    }

    func loadCollections() async throws -> CollectionState { // 新增
        let data = try Data(contentsOf: collectionFileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(CollectionState.self, from: data)
    }
}
