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

    // MARK: - Migration Telemetry

    private static let currentSchemaVersion = "2.0.0"
    private static let migrationFromSchemaVersion = "1.0.0"
    private static let migrationToSchemaVersion = "2.0.0"

    private static let v1ToV2MigrationCompletedKey = "migration.v1_to_v2.completed"
    private static let v1ToV2MigrationCompletedAtKey = "migration.v1_to_v2.completedAt"
    private static let v1ToV2MigrationFromVersionKey = "migration.v1_to_v2.fromVersion"
    private static let v1ToV2MigrationToVersionKey = "migration.v1_to_v2.toVersion"

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
        let defaults = UserDefaults.standard

        try? FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )

        let schema = Schema(Me2TuneSchemaV2.models)
        let config = ModelConfiguration(schema: schema, url: storeURL)

        do {
            // 优先按当前 Schema 直接打开，避免每次启动都触发迁移校验路径。
            // 仅在旧库无法直接打开时，回退到带 migration plan 的升级流程。
            let container: ModelContainer
            do {
                container = try ModelContainer(for: schema, configurations: [config])
                logger.info(
                    "DataService open path=direct schema=\(Self.currentSchemaVersion) migrationMarker=\(Self.v1ToV2MarkerDescription(defaults: defaults))"
                )
            } catch {
                logger.notice(
                    "DataService open path=direct_failed schema=\(Self.currentSchemaVersion) migrateFrom=\(Self.migrationFromSchemaVersion) migrateTo=\(Self.migrationToSchemaVersion) error=\(error)"
                )
                container = try ModelContainer(
                    for: schema,
                    migrationPlan: Me2TuneMigrationPlan.self,
                    configurations: [config]
                )
                let markerAlreadyExists = Self.markV1ToV2MigrationCompleted(defaults: defaults)
                logger.notice(
                    "DataService open path=migration schemaBefore=\(Self.migrationFromSchemaVersion) schemaAfter=\(Self.migrationToSchemaVersion) migrationMarkerAlreadyExists=\(markerAlreadyExists)"
                )
            }
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

    // MARK: - Migration Marker Helpers

    private static func markV1ToV2MigrationCompleted(defaults: UserDefaults) -> Bool {
        let wasMarked = defaults.bool(forKey: v1ToV2MigrationCompletedKey)
        if wasMarked { return true }

        defaults.set(true, forKey: v1ToV2MigrationCompletedKey)
        defaults.set(Date(), forKey: v1ToV2MigrationCompletedAtKey)
        defaults.set(migrationFromSchemaVersion, forKey: v1ToV2MigrationFromVersionKey)
        defaults.set(migrationToSchemaVersion, forKey: v1ToV2MigrationToVersionKey)
        return false
    }

    private static func v1ToV2MarkerDescription(defaults: UserDefaults) -> String {
        defaults.bool(forKey: v1ToV2MigrationCompletedKey) ? "set" : "unset"
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
}
