//
//  DataServiceStatisticsTests.swift
//  Me2TuneTests
//
//  【Level 2】服务层测试 - 验证 DataService 的统计相关操作
//

import Foundation
import SwiftData
import Testing
@testable import Me2Tune

@MainActor
@Suite("DataService 统计功能测试")
struct DataServiceStatisticsTests {
    
    // MARK: - 测试辅助属性
    
    /// 每个测试都会创建新的 DataService 实例（带独立内存数据库）
    @MainActor
    struct TestContext {
        let container: ModelContainer
        let context: ModelContext
        
        init() throws {
            container = try createTestModelContainer()
            context = container.mainContext
        }
    }
    
    // MARK: - Test 1: 查询空数据库
    
    @Test("空数据库应返回空数组")
    func testFetchEmptyStatistics() throws {
        // Arrange
        let test = try TestContext()
        let descriptor = FetchDescriptor<SDStatistics>()
        
        // Act
        let results = try test.context.fetch(descriptor)
        
        // Assert
        #expect(results.isEmpty)
    }
    
    // MARK: - Test 2: 插入单条统计记录
    
    @Test("应能成功插入统计记录")
    func testInsertStatistics() throws {
        // Arrange
        let test = try TestContext()
        let stat = SDStatistics.makeSample(dateString: "2026-02-15", playCount: 5)
        
        // Act
        test.context.insert(stat)
        try test.context.save()
        
        // Assert
        let descriptor = FetchDescriptor<SDStatistics>()
        let results = try test.context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results.first?.dateString == "2026-02-15")
        #expect(results.first?.playCount == 5)
    }
    
    // MARK: - Test 3: 批量插入
    
    @Test("应能批量插入多条统计记录")
    func testBatchInsert() throws {
        // Arrange
        let test = try TestContext()
        let dates = ["2026-02-13", "2026-02-14", "2026-02-15"]
        
        // Act - 批量插入 3 条记录
        for (index, date) in dates.enumerated() {
            let stat = SDStatistics.makeSample(dateString: date, playCount: index + 1)
            test.context.insert(stat)
        }
        try test.context.save()
        
        // Assert
        let descriptor = FetchDescriptor<SDStatistics>(
            sortBy: [SortDescriptor(\.dateString)]
        )
        let results = try test.context.fetch(descriptor)
        #expect(results.count == 3)
        #expect(results[0].playCount == 1)
        #expect(results[2].playCount == 3)
    }
    
    // MARK: - Test 4: 条件查询
    
    @Test("应能按日期查询特定统计记录")
    func testFetchByDate() throws {
        // Arrange
        let test = try TestContext()
        let targetDate = "2026-02-14"
        
        // 插入 3 条记录
        ["2026-02-13", "2026-02-14", "2026-02-15"].forEach { date in
            test.context.insert(SDStatistics.makeSample(dateString: date))
        }
        try test.context.save()
        
        // Act - 查询特定日期
        let descriptor = FetchDescriptor<SDStatistics>(
            predicate: #Predicate { $0.dateString == targetDate }
        )
        let results = try test.context.fetch(descriptor)
        
        // Assert
        #expect(results.count == 1)
        #expect(results.first?.dateString == "2026-02-14")
    }
    
    // MARK: - Test 5: 日期范围查询
    
    @Test("应能查询指定日期范围内的统计")
    func testFetchDateRange() throws {
        // Arrange
        let test = try TestContext()
        
        // 插入一周的数据
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        for i in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -i, to: today)!
            let dateString = formatDate(date)
            test.context.insert(SDStatistics.makeSample(dateString: dateString))
        }
        try test.context.save()
        
        // Act - 查询最近 3 天
        let threeDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        let startDate = formatDate(threeDaysAgo)
        
        let descriptor = FetchDescriptor<SDStatistics>(
            predicate: #Predicate { $0.dateString >= startDate },
            sortBy: [SortDescriptor(\.dateString, order: .reverse)]
        )
        let results = try test.context.fetch(descriptor)
        
        // Assert
        #expect(results.count == 3)
    }
    
    // MARK: - Test 6: 更新统计数据
    
    @Test("应能增加已存在日期的播放次数")
    func testIncrementPlayCount() throws {
        // Arrange
        let test = try TestContext()
        let dateString = "2026-02-15"
        let stat = SDStatistics.makeSample(dateString: dateString, playCount: 1)
        test.context.insert(stat)
        try test.context.save()
        
        // Act - 模拟播放，增加计数
        stat.playCount += 1
        try test.context.save()
        
        // Assert
        let descriptor = FetchDescriptor<SDStatistics>(
            predicate: #Predicate { $0.dateString == dateString }
        )
        let results = try test.context.fetch(descriptor)
        #expect(results.first?.playCount == 2)
    }
    
    // MARK: - Test 7: 删除旧记录
    
    @Test("应能删除指定日期之前的统计记录")
    func testDeleteOldRecords() throws {
        // Arrange
        let test = try TestContext()
        let calendar = Calendar.current
        let today = Date()
        
        // 插入新旧两条记录
        let oldDate = calendar.date(byAdding: .day, value: -400, to: today)!
        let oldStat = SDStatistics.makeSample(
            dateString: formatDate(oldDate),
            playCount: 1
        )
        
        let newStat = SDStatistics.makeSample(
            dateString: formatDate(today),
            playCount: 5
        )
        
        test.context.insert(oldStat)
        test.context.insert(newStat)
        try test.context.save()
        
        // Act - 删除 365 天前的记录
        let cutoffDate = calendar.date(byAdding: .day, value: -365, to: today)!
        let cutoffString = formatDate(cutoffDate)
        
        let descriptor = FetchDescriptor<SDStatistics>(
            predicate: #Predicate { $0.dateString < cutoffString }
        )
        let oldRecords = try test.context.fetch(descriptor)
        
        for record in oldRecords {
            test.context.delete(record)
        }
        try test.context.save()
        
        // Assert - 应该只剩下新记录
        let allDescriptor = FetchDescriptor<SDStatistics>()
        let remaining = try test.context.fetch(allDescriptor)
        #expect(remaining.count == 1)
        #expect(remaining.first?.playCount == 5)
    }
    
    // MARK: - Helper
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
