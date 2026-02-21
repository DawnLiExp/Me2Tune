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
final class DataService: DataServiceProtocol {
    // MARK: - Singleton

    static let shared = DataService()

    // MARK: - Properties

    let modelContainer: ModelContainer
    let isMigrationFailed: Bool

    var modelContext: ModelContext {
        modelContainer.mainContext
    }

    // MARK: - Initialization

    /// 公开初始化器 - 用于测试时注入自定义 ModelContainer
    init(modelContainer: ModelContainer, isMigrationFailed: Bool = false) {
        self.modelContainer = modelContainer
        self.isMigrationFailed = isMigrationFailed
    }

    /// 便利初始化器 - 用于生产环境
    private convenience init() {
        let appSupportURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let storeDirectory = appSupportURL.appendingPathComponent("Me2Tune", isDirectory: true)
        let storeURL = storeDirectory.appendingPathComponent("Me2Tune.store")

        try? FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )

        let schema = Schema(Me2TuneSchemaV1.models)
        let config = ModelConfiguration(schema: schema, url: storeURL)

        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: Me2TuneMigrationPlan.self,
                configurations: [config]
            )
            container.mainContext.autosaveEnabled = true
            logger.info("✅ DataService initialized - store: \(storeURL.path)")
            self.init(modelContainer: container, isMigrationFailed: false)
        } catch {
            logger.critical("❌ Migration failed, falling back to in-memory store: \(error)")
            let memConfig = ModelConfiguration(isStoredInMemoryOnly: true)
            // 内存容器初始化不应失败，force-try 可接受
            let fallback = try! ModelContainer(for: schema, configurations: [memConfig])
            self.init(modelContainer: fallback, isMigrationFailed: true)
        }
    }

    // MARK: - Generic CRUD

    func insert(_ model: some PersistentModel) {
        modelContext.insert(model)
    }

    func delete(_ model: some PersistentModel) {
        modelContext.delete(model)
    }

    func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws(AppError) -> [T] {
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw AppError.swiftDataFailed(underlying: error)
        }
    }

    func fetchCount(_ descriptor: FetchDescriptor<some PersistentModel>) throws(AppError) -> Int {
        do {
            return try modelContext.fetchCount(descriptor)
        } catch {
            throw AppError.swiftDataFailed(underlying: error)
        }
    }

    func save() throws(AppError) {
        do {
            try modelContext.save()
        } catch {
            throw AppError.swiftDataFailed(underlying: error)
        }
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

    func fetchPlaylistTracks() throws(AppError) -> [SDTrack] {
        var descriptor = FetchDescriptor<SDTrack>(
            predicate: #Predicate { $0.isInPlaylist == true },
            sortBy: [SortDescriptor(\.playlistOrder)]
        )
        descriptor.fetchLimit = 20000
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw AppError.swiftDataFailed(underlying: error)
        }
    }

    func playlistTrackCount() throws(AppError) -> Int {
        let descriptor = FetchDescriptor<SDTrack>(
            predicate: #Predicate { $0.isInPlaylist == true }
        )
        do {
            return try modelContext.fetchCount(descriptor)
        } catch {
            throw AppError.swiftDataFailed(underlying: error)
        }
    }

    // MARK: - Album Operations

    func fetchAlbums() throws(AppError) -> [SDAlbum] {
        let descriptor = FetchDescriptor<SDAlbum>(
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw AppError.swiftDataFailed(underlying: error)
        }
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

    func albumCount() throws(AppError) -> Int {
        let descriptor = FetchDescriptor<SDAlbum>(predicate: nil as Predicate<SDAlbum>?)
        do {
            return try modelContext.fetchCount(descriptor)
        } catch {
            throw AppError.swiftDataFailed(underlying: error)
        }
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
