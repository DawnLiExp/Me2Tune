//
//  IntegrationTests.swift
//  Me2TuneTests
//
//  【Level 4】集成测试 - 验证多个组件协同工作
//

import Foundation
import SwiftData
import Testing
@testable import Me2Tune

@MainActor
@Suite("集成测试 - 数据服务与业务逻辑")
struct DataServicesIntegrationTests {
    
    @Test("PlaylistManager + DataService 集成")
    func testPlaylistManagerIntegration() async throws {
        // Arrange - 共享同一个 DataService
        let dataService = try createTestDataService()
        _ = PlaylistManager(dataService: dataService)
        
        // Act - 通过 DataService 直接添加歌曲到播放列表
        let track = SDTrack.makeSample(title: "Integration Test")
        dataService.insert(track)
        try dataService.save()
        
        // 将歌曲加入播放列表
        track.isInPlaylist = true
        track.playlistOrder = 0
        try dataService.save()
        
        // Assert - 通过 DataService 验证
        let count = try dataService.playlistTrackCount()
        #expect(count == 1)
        
        let tracks = try dataService.fetchPlaylistTracks()
        #expect(tracks.first?.title == "Integration Test")
    }
    
    @Test("StatisticsManager + DataService 集成")
    func testStatisticsManagerIntegration() async throws {
        // Arrange
        let dataService = try createTestDataService()
        let statsManager = StatisticsManager(dataService: dataService)
        
        // Act - 增加播放计数
        await statsManager.incrementTodayPlayCount()
        await statsManager.incrementTodayPlayCount()
        
        // Assert - 通过 DataService 验证数据持久化
        let descriptor = FetchDescriptor<SDStatistics>()
        let stats = try dataService.fetch(descriptor)
        
        #expect(stats.count == 1)
        #expect(stats.first?.playCount == 2)
    }
    
    @Test("PlaylistManager + StatisticsManager 共享 DataService")
    func testSharedDataService() async throws {
        // Arrange - 使用同一个 DataService
        let dataService = try createTestDataService()
        _ = PlaylistManager(dataService: dataService)
        let statsManager = StatisticsManager(dataService: dataService)
        
        // Act - 添加歌曲并播放
        let track = SDTrack.makeSample()
        dataService.insert(track)
        track.isInPlaylist = true
        try dataService.save()
        
        await statsManager.incrementTodayPlayCount()
        
        // Assert - 验证两者都能访问同一数据库
        let trackCount = try dataService.playlistTrackCount()
        let stats = await statsManager.fetchRecentStatistics(days: 1)
        
        #expect(trackCount == 1)
        #expect(stats.first?.playCount == 1)
    }
}
