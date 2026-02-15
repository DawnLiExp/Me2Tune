//
//  StatisticsManagerTests.swift
//  Me2TuneTests
//
//  【Level 3】业务逻辑测试 - 验证 StatisticsManager 的数据聚合和清理功能
//

import Foundation
import SwiftData
import Testing
@testable import Me2Tune

@MainActor
@Suite("StatisticsManager 业务逻辑测试")
struct StatisticsManagerTests {
    
    // MARK: - 测试用 Manager（使用独立数据库）
    
    /// 为测试创建独立的 Manager 实例
    @MainActor
    final class TestStatisticsManager {
        let container: ModelContainer
        var modelContext: ModelContext { container.mainContext }
        
        init() throws {
            container = try createTestModelContainer()
        }
        
        // 复制核心业务逻辑（简化版）
        func incrementPlayCount(for dateString: String) throws {
            let descriptor = FetchDescriptor<SDStatistics>(
                predicate: #Predicate { $0.dateString == dateString }
            )
            
            if let stat = try modelContext.fetch(descriptor).first {
                stat.playCount += 1
            } else {
                let newStat = SDStatistics(dateString: dateString, playCount: 1)
                modelContext.insert(newStat)
            }
            try modelContext.save()
        }
        
        func fetchRecentDays(_ days: Int) throws -> [SDStatistics] {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let startDate = calendar.date(byAdding: .day, value: -days + 1, to: today)!
            let startString = formatDate(startDate)
            
            let descriptor = FetchDescriptor<SDStatistics>(
                predicate: #Predicate { $0.dateString >= startString },
                sortBy: [SortDescriptor(\.dateString)]
            )
            
            return try modelContext.fetch(descriptor)
        }
        
        func deleteOldRecords(olderThan days: Int) throws {
            let calendar = Calendar.current
            let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date())!
            let cutoffString = formatDate(cutoffDate)
            
            let descriptor = FetchDescriptor<SDStatistics>(
                predicate: #Predicate { $0.dateString < cutoffString }
            )
            
            let oldRecords = try modelContext.fetch(descriptor)
            for record in oldRecords {
                modelContext.delete(record)
            }
            try modelContext.save()
        }
        
        private func formatDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }
    }
    
    // MARK: - Test 1: 首次播放创建新记录
    
    @Test("首次播放应创建新的统计记录")
    func testFirstPlayCreatesNewRecord() throws {
        // Arrange
        let manager = try TestStatisticsManager()
        let today = formatDate(Date())
        
        // Act
        try manager.incrementPlayCount(for: today)
        
        // Assert
        let descriptor = FetchDescriptor<SDStatistics>()
        let results = try manager.modelContext.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results.first?.playCount == 1)
    }
    
    // MARK: - Test 2: 同一天多次播放累加
    
    @Test("同一天多次播放应累加计数")
    func testMultiplePlaysSameDay() throws {
        // Arrange
        let manager = try TestStatisticsManager()
        let today = formatDate(Date())
        
        // Act - 模拟播放 3 次
        try manager.incrementPlayCount(for: today)
        try manager.incrementPlayCount(for: today)
        try manager.incrementPlayCount(for: today)
        
        // Assert
        let descriptor = FetchDescriptor<SDStatistics>(
            predicate: #Predicate { $0.dateString == today }
        )
        let results = try manager.modelContext.fetch(descriptor)
        #expect(results.first?.playCount == 3)
    }
    
    // MARK: - Test 3: 不同天播放独立计数
    
    @Test("不同日期的播放应独立统计")
    func testDifferentDaysIndependentCount() throws {
        // Arrange
        let manager = try TestStatisticsManager()
        let calendar = Calendar.current
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        
        // Act
        try manager.incrementPlayCount(for: formatDate(today))
        try manager.incrementPlayCount(for: formatDate(today))
        try manager.incrementPlayCount(for: formatDate(yesterday))
        
        // Assert
        let descriptor = FetchDescriptor<SDStatistics>(
            sortBy: [SortDescriptor(\.dateString, order: .reverse)]
        )
        let results = try manager.modelContext.fetch(descriptor)
        
        #expect(results.count == 2)
        #expect(results[0].playCount == 2)  // 今天
        #expect(results[1].playCount == 1)  // 昨天
    }
    
    // MARK: - Test 4: 查询最近 N 天
    
    @Test("应能正确查询最近指定天数的统计")
    func testFetchRecentDays() throws {
        // Arrange
        let manager = try TestStatisticsManager()
        let calendar = Calendar.current
        let today = Date()
        
        // 插入 10 天的数据
        for i in 0..<10 {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            let dateString = formatDate(date)
            let stat = SDStatistics.makeSample(dateString: dateString, playCount: i + 1)
            manager.modelContext.insert(stat)
        }
        try manager.modelContext.save()
        
        // Act - 查询最近 7 天
        let recent = try manager.fetchRecentDays(7)
        
        // Assert
        #expect(recent.count == 7)
        // 验证日期排序正确（从旧到新）
        #expect(recent.first!.dateString < recent.last!.dateString)
    }
    
    // MARK: - Test 5: 清理过期数据
    
    @Test("应能删除超过指定天数的旧记录")
    func testCleanupOldRecords() throws {
        // Arrange
        let manager = try TestStatisticsManager()
        let calendar = Calendar.current
        let today = Date()
        
        // 插入新旧两组数据
        let oldDate = calendar.date(byAdding: .day, value: -400, to: today)!
        let oldStat = SDStatistics.makeSample(dateString: formatDate(oldDate))
        manager.modelContext.insert(oldStat)
        
        let newStat = SDStatistics.makeSample(dateString: formatDate(today))
        manager.modelContext.insert(newStat)
        
        try manager.modelContext.save()
        
        // Act - 删除 365 天前的数据
        try manager.deleteOldRecords(olderThan: 365)
        
        // Assert - 只剩下新数据
        let descriptor = FetchDescriptor<SDStatistics>()
        let remaining = try manager.modelContext.fetch(descriptor)
        #expect(remaining.count == 1)
        #expect(remaining.first?.dateString == formatDate(today))
    }
    
    // MARK: - Test 6: 边界条件 - 删除刚好 365 天的记录
    
    @Test("刚好 365 天的记录应被保留（边界条件）")
    func testCleanupBoundary() throws {
        // Arrange
        let manager = try TestStatisticsManager()
        let calendar = Calendar.current
        let today = Date()
        
        // 刚好 365 天前
        let boundaryDate = calendar.date(byAdding: .day, value: -365, to: today)!
        let boundaryStat = SDStatistics.makeSample(dateString: formatDate(boundaryDate))
        manager.modelContext.insert(boundaryStat)
        
        // 366 天前（应被删除）
        let oldDate = calendar.date(byAdding: .day, value: -366, to: today)!
        let oldStat = SDStatistics.makeSample(dateString: formatDate(oldDate))
        manager.modelContext.insert(oldStat)
        
        try manager.modelContext.save()
        
        // Act
        try manager.deleteOldRecords(olderThan: 365)
        
        // Assert
        let descriptor = FetchDescriptor<SDStatistics>()
        let remaining = try manager.modelContext.fetch(descriptor)
        #expect(remaining.count == 1)
        #expect(remaining.first?.dateString == formatDate(boundaryDate))
    }
    
    // MARK: - Test 7: 空数据库清理（不应崩溃）
    
    @Test("空数据库执行清理不应报错")
    func testCleanupEmptyDatabase() throws {
        // Arrange
        let manager = try TestStatisticsManager()
        
        // Act & Assert - 不应抛出异常
        try manager.deleteOldRecords(olderThan: 365)
        
        let descriptor = FetchDescriptor<SDStatistics>()
        let results = try manager.modelContext.fetch(descriptor)
        #expect(results.isEmpty)
    }
    
    // MARK: - Helper
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - 性能测试示例

@MainActor
@Suite("StatisticsManager 性能测试")
struct StatisticsManagerPerformanceTests {
    
    @Test("大量数据插入性能")
    func testBulkInsertPerformance() throws {
        // Arrange
        let manager = try StatisticsManagerTests.TestStatisticsManager()
        let calendar = Calendar.current
        let today = Date()
        
        // Act - 插入 365 天的数据
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<365 {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            let dateString = formatDate(date)
            let stat = SDStatistics.makeSample(dateString: dateString, playCount: i % 10)
            manager.modelContext.insert(stat)
        }
        try manager.modelContext.save()
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        // Assert - 应在 1 秒内完成
        #expect(elapsed < 1.0)
        
        // 验证数据正确性
        let descriptor = FetchDescriptor<SDStatistics>()
        let results = try manager.modelContext.fetch(descriptor)
        #expect(results.count == 365)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
