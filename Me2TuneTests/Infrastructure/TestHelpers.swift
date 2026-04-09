//
//  TestHelpers.swift
//  Me2TuneTests
//
//  测试辅助工具 - 提供内存数据库和测试服务工厂函数
//

import Foundation
import SwiftData
import Testing
@testable import Me2Tune

// MARK: - Test ModelContainer Factory

/// 为每个测试创建独立的内存数据库，测试结束后自动销毁
@MainActor
func createTestModelContainer() throws -> ModelContainer {
    let schema = Schema(Me2TuneSchemaV2.models)   // 统一引用，不再硬编码列表
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

// MARK: - Test Service Factories

/// 创建测试用的 DataService 实例（使用独立内存数据库）
@MainActor
func createTestDataService() throws -> DataService {
    let container = try createTestModelContainer()
    return DataService(modelContainer: container)
}

/// 创建测试用的 StatisticsManager 实例
@MainActor
func createTestStatisticsManager() throws -> StatisticsManager {
    let dataService = try createTestDataService()
    return StatisticsManager(dataService: dataService)
}

/// 创建测试用的 PlaylistManager 实例
@MainActor
func createTestPlaylistManager() throws -> PlaylistManager {
    let dataService = try createTestDataService()
    return PlaylistManager(dataService: dataService)
}

/// 创建测试用的 CollectionManager 实例
@MainActor
func createTestCollectionManager() throws -> CollectionManager {
    let dataService = try createTestDataService()
    return CollectionManager(dataService: dataService)
}

/// 创建测试用的 PlaybackStateManager 实例
@MainActor
func createTestPlaybackStateManager(
    playlistManager: PlaylistManager? = nil,
    collectionManager: CollectionManager? = nil,
    dataService: DataService? = nil
) throws -> PlaybackStateManager {
    let service = try dataService ?? createTestDataService()
    let playlist = playlistManager ?? PlaylistManager(dataService: service)
    return PlaybackStateManager(
        playlistManager: playlist,
        collectionManager: collectionManager,
        dataService: service
    )
}

// MARK: - Sample Data Builders

extension SDTrack {
    /// 快速创建测试用的歌曲
    static func makeSample(
        title: String = "Test Song",
        artist: String? = "Test Artist",
        albumTitle: String? = nil,
        urlString: String = "file:///test.mp3",
        duration: TimeInterval = 180.0
    ) -> SDTrack {
        SDTrack(
            title: title,
            artist: artist,
            albumTitle: albumTitle,
            duration: duration,
            urlString: urlString,
            bookmark: nil,
            codec: "FLAC",
            bitrate: 1411,
            sampleRate: 44100,
            bitDepth: 16,
            channels: 2
        )
    }
}

extension SDStatistics {
    /// 快速创建测试统计数据
    static func makeSample(
        dateString: String,
        playCount: Int = 1
    ) -> SDStatistics {
        SDStatistics(
            dateString: dateString,
            playCount: playCount
        )
    }
}

extension SDAlbum {
    /// 快速创建测试专辑
    static func makeSample(
        name: String = "Test Album",
        folderURLString: String? = "file:///test/album",
        displayOrder: Int = 0
    ) -> SDAlbum {
        SDAlbum(
            name: name,
            folderURLString: folderURLString,
            displayOrder: displayOrder
        )
    }
}
