//
//  PersistenceService.swift
//  Me2Tune
//
//  播放列表持久化服务
//

import Foundation

struct PlaylistState: Codable, Sendable {
    var trackURLs: [URL]
    var currentIndex: Int?
}

actor PersistenceService {
    private let fileURL: URL
    
    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first!
        
        let appDirectory = appSupport.appendingPathComponent("Me2Tune", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        
        fileURL = appDirectory.appendingPathComponent("playlist.json")
    }
    
    // MARK: - Public Methods
    
    func save(_ state: PlaylistState) async throws {
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
    
    func load() async throws -> PlaylistState {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(PlaylistState.self, from: data)
    }
}
