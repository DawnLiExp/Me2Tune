//
//  DataService.swift
//  Me2Tune
//
//  SwiftData 数据服务 - ModelContainer 配置 + 通用 CRUD 操作
//

import Foundation
import OSLog
import SwiftData

private let logger = Logger.persistence

@MainActor
final class DataService {
    // MARK: - Singleton

    static let shared = DataService()

    // MARK: - Properties

    let modelContainer: ModelContainer
    var modelContext: ModelContext {
        modelContainer.mainContext
    }

    // MARK: - Initialization

    private init() {
        let schema = Schema([
            SDTrack.self,
            SDAlbum.self,
            SDAlbumTrackEntry.self,
            SDPlaybackState.self,
        ])

        let config = ModelConfiguration(
            "Me2Tune",
            isStoredInMemoryOnly: false
        )

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            modelContainer.mainContext.autosaveEnabled = true
            logger.info("✅ DataService initialized - SwiftData ModelContainer ready")
        } catch {
            fatalError("❌ Failed to create ModelContainer: \(error)")
        }
    }

    // MARK: - Generic CRUD

    func insert(_ model: some PersistentModel) {
        modelContext.insert(model)
    }

    func delete(_ model: some PersistentModel) {
        modelContext.delete(model)
    }

    func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        try modelContext.fetch(descriptor)
    }

    func fetchCount(_ descriptor: FetchDescriptor<some PersistentModel>) throws -> Int {
        try modelContext.fetchCount(descriptor)
    }

    func save() throws {
        try modelContext.save()
    }

    // MARK: - Track Operations

    /// 根据 URL 查找已存在的 SDTrack
    func findTrack(byURL urlString: String) -> SDTrack? {
        var descriptor = FetchDescriptor<SDTrack>(
            predicate: #Predicate { $0.urlString == urlString }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// 获取 Playlist 中的所有歌曲，按 playlistOrder 排序
    func fetchPlaylistTracks() throws -> [SDTrack] {
        var descriptor = FetchDescriptor<SDTrack>(
            predicate: #Predicate { $0.isInPlaylist == true },
            sortBy: [SortDescriptor(\.playlistOrder)]
        )
        descriptor.fetchLimit = 20000
        return try modelContext.fetch(descriptor)
    }

    /// 获取 Playlist 歌曲数
    func playlistTrackCount() throws -> Int {
        let descriptor = FetchDescriptor<SDTrack>(
            predicate: #Predicate { $0.isInPlaylist == true }
        )
        return try modelContext.fetchCount(descriptor)
    }

    // MARK: - Album Operations

    /// 获取所有专辑，按 displayOrder 排序
    func fetchAlbums() throws -> [SDAlbum] {
        let descriptor = FetchDescriptor<SDAlbum>(
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// 根据 folderURLString 查找专辑
    func findAlbum(byFolderURL urlString: String) -> SDAlbum? {
        var descriptor = FetchDescriptor<SDAlbum>(
            predicate: #Predicate { $0.folderURLString == urlString }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// 获取专辑数量
    func albumCount() throws -> Int {
        let descriptor = FetchDescriptor<SDAlbum>(predicate: nil as Predicate<SDAlbum>?)
        return try modelContext.fetchCount(descriptor)
    }

    // MARK: - Playback State Operations

    /// 获取或创建播放状态单例
    func getOrCreatePlaybackState() -> SDPlaybackState {
        let descriptor = FetchDescriptor<SDPlaybackState>()
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let state = SDPlaybackState()
        modelContext.insert(state)
        return state
    }
}
