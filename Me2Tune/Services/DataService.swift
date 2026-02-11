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

    func findTrack(byURL urlString: String) -> SDTrack? {
        var descriptor = FetchDescriptor<SDTrack>(
            predicate: #Predicate { $0.urlString == urlString }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func findTrack(byStableId id: UUID) -> SDTrack? {
        var descriptor = FetchDescriptor<SDTrack>(
            predicate: #Predicate { $0.stableId == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func fetchPlaylistTracks() throws -> [SDTrack] {
        var descriptor = FetchDescriptor<SDTrack>(
            predicate: #Predicate { $0.isInPlaylist == true },
            sortBy: [SortDescriptor(\.playlistOrder)]
        )
        descriptor.fetchLimit = 20000
        return try modelContext.fetch(descriptor)
    }

    func playlistTrackCount() throws -> Int {
        let descriptor = FetchDescriptor<SDTrack>(
            predicate: #Predicate { $0.isInPlaylist == true }
        )
        return try modelContext.fetchCount(descriptor)
    }

    // MARK: - Album Operations

    func fetchAlbums() throws -> [SDAlbum] {
        let descriptor = FetchDescriptor<SDAlbum>(
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    func findAlbum(byFolderURL urlString: String) -> SDAlbum? {
        var descriptor = FetchDescriptor<SDAlbum>(
            predicate: #Predicate { $0.folderURLString == urlString }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func findAlbum(byStableId id: UUID) -> SDAlbum? {
        var descriptor = FetchDescriptor<SDAlbum>(
            predicate: #Predicate { $0.stableId == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func albumCount() throws -> Int {
        let descriptor = FetchDescriptor<SDAlbum>(predicate: nil as Predicate<SDAlbum>?)
        return try modelContext.fetchCount(descriptor)
    }

    // MARK: - Playback State Operations

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
