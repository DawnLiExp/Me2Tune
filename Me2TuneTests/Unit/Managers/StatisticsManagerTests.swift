//
//  StatisticsManagerTests.swift
//  Me2TuneTests
//
//  【Level 3】StatisticsManager 单元测试 - 验证统计业务逻辑
//

import Foundation
import SwiftData
import Testing
@testable import Me2Tune

@MainActor
@Suite("StatisticsManager 单元测试")
struct StatisticsManagerTests {
    
    // MARK: - 基础功能测试
    
    @Test("首次播放创建统计记录")
    func testFirstPlayCreatesRecord() async throws {
        // Arrange
        let statsManager = try createTestStatisticsManager()
        
        // Act
        await statsManager.incrementTodayPlayCount()
        
        // Assert
        let stats = await statsManager.fetchRecentStatistics(days: 1)
        #expect(stats.count == 1)
        #expect(stats.first?.playCount == 1)
    }
    
    @Test("同一天多次播放累加计数")
    func testMultiplePlaysSameDay() async throws {
        // Arrange
        let statsManager = try createTestStatisticsManager()
        
        // Act - 模拟播放 3 次
        await statsManager.incrementTodayPlayCount()
        await statsManager.incrementTodayPlayCount()
        await statsManager.incrementTodayPlayCount()
        
        // Assert
        let stats = await statsManager.fetchRecentStatistics(days: 1)
        #expect(stats.first?.playCount == 3)
    }
    
    @Test("不同日期独立统计")
    func testDifferentDaysIndependentCount() async throws {
        // Arrange
        let dataService = try createTestDataService()
        let statsManager = StatisticsManager(dataService: dataService)
        
        let today = formatDate(Date())
        let yesterday = formatDate(Date().addingTimeInterval(-86400))
        
        // 手动插入不同日期的数据
        dataService.insert(SDStatistics.makeSample(dateString: today, playCount: 2))
        dataService.insert(SDStatistics.makeSample(dateString: yesterday, playCount: 1))
        try dataService.save()
        
        // Act
        let stats = await statsManager.fetchRecentStatistics(days: 7)
        
        // Assert
        #expect(stats.count == 7)
        
        let todayStats = stats.first { $0.id == today }
        let yesterdayStats = stats.first { $0.id == yesterday }
        
        #expect(todayStats?.playCount == 2)
        #expect(yesterdayStats?.playCount == 1)
    }
    
    // MARK: - 聚合统计测试
    
    @Test("日统计模式返回原始数据")
    func testDailyAggregation() async throws {
        // Arrange
        let dataService = try createTestDataService()
        let statsManager = StatisticsManager(dataService: dataService)
        
        // 插入最近 7 天数据
        for i in 0..<7 {
            let date = Date().addingTimeInterval(TimeInterval(-i * 86400))
            dataService.insert(SDStatistics.makeSample(
                dateString: formatDate(date),
                playCount: i + 1
            ))
        }
        try dataService.save()
        
        // Act
        let stats = await statsManager.fetchAggregatedStats(period: .daily)
        
        // Assert
        #expect(stats.count == 30) // 默认 30 天
        
        // 验证最近一天的数据
        let todayCount = stats.last?.playCount ?? 0
        #expect(todayCount == 1)
    }
    
    @Test("周统计聚合")
    func testWeeklyAggregation() async throws {
        // Arrange
        let dataService = try createTestDataService()
        let statsManager = StatisticsManager(dataService: dataService)
        
        // 插入 14 天数据（2 周）
        for i in 0..<14 {
            let date = Date().addingTimeInterval(TimeInterval(-i * 86400))
            dataService.insert(SDStatistics.makeSample(
                dateString: formatDate(date),
                playCount: 1
            ))
        }
        try dataService.save()
        
        // Act
        let stats = await statsManager.fetchAggregatedStats(period: .weekly)
        
        // Assert
        #expect(stats.count >= 2) // 至少 2 周的数据
        
        // 验证总播放次数
        let totalPlays = stats.reduce(0) { $0 + $1.playCount }
        #expect(totalPlays == 14)
    }
    
    @Test("月统计聚合")
    func testMonthlyAggregation() async throws {
        // Arrange
        let dataService = try createTestDataService()
        let statsManager = StatisticsManager(dataService: dataService)
        
        let calendar = Calendar.autoupdatingCurrent
        let today = Date()
        
        // 本月 15 天
        for i in 0..<15 {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            dataService.insert(SDStatistics.makeSample(
                dateString: formatDate(date),
                playCount: 1
            ))
        }
        
        // 上月 15 天
        for i in 15..<30 {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            dataService.insert(SDStatistics.makeSample(
                dateString: formatDate(date),
                playCount: 2
            ))
        }
        try dataService.save()
        
        // Act
        let stats = await statsManager.fetchAggregatedStats(period: .monthly)
        
        // Assert
        #expect(stats.count >= 1)
        
        // 验证总播放次数
        let totalPlays = stats.reduce(0) { $0 + $1.playCount }
        #expect(totalPlays == 45) // 15*1 + 15*2
    }
    
    // MARK: - 数据清理测试
    
    @Test("清理超过指定天数的旧记录")
    func testCleanupOldData() async throws {
        // Arrange
        let dataService = try createTestDataService()
        let statsManager = StatisticsManager(dataService: dataService)
        
        let calendar = Calendar.autoupdatingCurrent
        let today = Date()
        
        // 插入 400 天前的旧数据
        let oldDate = calendar.date(byAdding: .day, value: -400, to: today)!
        dataService.insert(SDStatistics.makeSample(dateString: formatDate(oldDate)))
        
        // 插入今天的新数据
        dataService.insert(SDStatistics.makeSample(dateString: formatDate(today)))
        try dataService.save()
        
        // Act - 清理 365 天前的数据
        statsManager.cleanupOldData(keepDays: 365)
        
        // Assert - 只剩下新数据
        let descriptor = FetchDescriptor<SDStatistics>()
        let remaining = try dataService.fetch(descriptor)
        #expect(remaining.count == 1)
        #expect(remaining.first?.dateString == formatDate(today))
    }
    
    @Test("边界条件 - 刚好保留天数的记录不删除")
    func testCleanupBoundary() async throws {
        // Arrange
        let dataService = try createTestDataService()
        let statsManager = StatisticsManager(dataService: dataService)
        
        let calendar = Calendar.autoupdatingCurrent
        let today = Date()
        
        // 刚好 365 天前（应保留）
        let boundaryDate = calendar.date(byAdding: .day, value: -365, to: today)!
        dataService.insert(SDStatistics.makeSample(dateString: formatDate(boundaryDate)))
        
        // 366 天前（应删除）
        let oldDate = calendar.date(byAdding: .day, value: -366, to: today)!
        dataService.insert(SDStatistics.makeSample(dateString: formatDate(oldDate)))
        try dataService.save()
        
        // Act
        statsManager.cleanupOldData(keepDays: 365)
        
        // Assert
        let descriptor = FetchDescriptor<SDStatistics>()
        let remaining = try dataService.fetch(descriptor)
        #expect(remaining.count == 1)
        #expect(remaining.first?.dateString == formatDate(boundaryDate))
    }
    
    @Test("空数据库清理不报错")
    func testCleanupEmptyDatabase() throws {
        // Arrange
        let statsManager = try createTestStatisticsManager()
        
        // Act & Assert - 不应抛出异常
        statsManager.cleanupOldData(keepDays: 365)
    }
    
    // MARK: - 数据填充测试
    
    @Test("查询结果自动填充缺失日期（零值）")
    func testFetchFillsGaps() async throws {
        // Arrange
        let dataService = try createTestDataService()
        let statsManager = StatisticsManager(dataService: dataService)
        
        let calendar = Calendar.autoupdatingCurrent
        let today = Date()
        
        // 只插入 3 天数据（有间隔）
        let day0 = formatDate(today)
        let day3 = formatDate(calendar.date(byAdding: .day, value: -3, to: today)!)
        let day6 = formatDate(calendar.date(byAdding: .day, value: -6, to: today)!)
        
        dataService.insert(SDStatistics.makeSample(dateString: day0, playCount: 1))
        dataService.insert(SDStatistics.makeSample(dateString: day3, playCount: 2))
        dataService.insert(SDStatistics.makeSample(dateString: day6, playCount: 3))
        try dataService.save()
        
        // Act - 查询最近 7 天
        let stats = await statsManager.fetchRecentStatistics(days: 7)
        
        // Assert - 应该返回完整的 7 天数据
        #expect(stats.count == 7)
        
        // 验证有数据的日期
        #expect(stats.last?.playCount == 1) // 今天
        #expect(stats[3].playCount == 2)    // 3 天前
        #expect(stats[0].playCount == 3)    // 6 天前
        
        // 验证中间日期被填充为 0
        #expect(stats[1].playCount == 0)
        #expect(stats[2].playCount == 0)
    }
    
    // MARK: - Helper
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        return formatter.string(from: date)
    }
}

// MARK: - 性能测试

@MainActor
@Suite("StatisticsManager 性能测试")
struct StatisticsManagerPerformanceTests {
    
    @Test("大量数据插入性能")
    func testBulkInsertPerformance() throws {
        // Arrange
        let dataService = try createTestDataService()
        let calendar = Calendar.autoupdatingCurrent
        let today = Date()
        
        // Act - 插入 365 天的数据
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<365 {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            let dateString = formatDate(date)
            let stat = SDStatistics.makeSample(dateString: dateString, playCount: i % 10)
            dataService.insert(stat)
        }
        try dataService.save()
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        // Assert - 应在 1 秒内完成
        #expect(elapsed < 1.0)
        
        // 验证数据正确性
        let descriptor = FetchDescriptor<SDStatistics>()
        let results = try dataService.fetch(descriptor)
        #expect(results.count == 365)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        return formatter.string(from: date)
    }
}
