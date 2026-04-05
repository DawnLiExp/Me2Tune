//
//  SDStatisticsTests.swift
//  Me2TuneTests
//
//  【Level 1】模型基础测试 - 验证 SDStatistics 初始化和属性
//

import Foundation
import SwiftData
import Testing
@testable import Me2Tune

// MARK: - 测试套件

@MainActor  // SwiftData 需要在主线程操作
@Suite("SDStatistics 模型测试")
struct SDStatisticsTests {
    
    // MARK: - Test 1: 初始化验证
    
    @Test("初始化时应正确设置所有属性")
    func testInitialization() throws {
        // Arrange（准备数据）
        let dateString = "2026-02-15"
        let playCount = 42
        let now = Date()
        
        // Act（执行操作）
        let statistics = SDStatistics(
            dateString: dateString,
            playCount: playCount,
            createdAt: now
        )
        
        // Assert（验证结果）
        #expect(statistics.dateString == dateString)
        #expect(statistics.playCount == playCount)
        #expect(statistics.createdAt == now)
    }
    
    // MARK: - Test 2: 默认值验证
    
    @Test("使用默认参数初始化时应设置合理的默认值")
    func testDefaultValues() throws {
        // Arrange & Act
        let statistics = SDStatistics(dateString: "2026-02-15")
        
        // Assert
        #expect(statistics.playCount == 0)  // 默认播放次数为 0
        #expect(statistics.createdAt.timeIntervalSinceNow < 1)  // 创建时间接近现在
    }
    
    // MARK: - Test 3: 数据持久化测试
    
    @Test("数据应能正确保存到 SwiftData 并查询")
    func testPersistence() throws {
        // Arrange - 创建测试用的内存数据库
        let container = try createTestModelContainer()
        let context = container.mainContext
        
        let dateString = "2026-02-15"
        let statistics = SDStatistics(dateString: dateString, playCount: 10)
        
        // Act - 插入数据
        context.insert(statistics)
        try context.save()
        
        // 查询刚插入的数据
        let descriptor = FetchDescriptor<SDStatistics>(
            predicate: #Predicate { $0.dateString == dateString }
        )
        let results = try context.fetch(descriptor)
        
        // Assert - 验证能查到数据且内容正确
        #expect(results.count == 1)
        #expect(results.first?.playCount == 10)
    }
    
    // MARK: - Test 4: 唯一性约束测试
    
    @Test("相同日期的统计记录应覆盖（因为 dateString 是 unique）")
    func testUniqueConstraint() throws {
        // Arrange
        let container = try createTestModelContainer()
        let context = container.mainContext
        
        let dateString = "2026-02-15"
        let stat1 = SDStatistics(dateString: dateString, playCount: 5)
        let stat2 = SDStatistics(dateString: dateString, playCount: 10)
        
        // Act
        context.insert(stat1)
        try context.save()
        
        context.insert(stat2)
        // 注意：SwiftData 会自动处理唯一性冲突
        try context.save()
        
        // Assert
        let descriptor = FetchDescriptor<SDStatistics>(
            predicate: #Predicate { $0.dateString == dateString }
        )
        let results = try context.fetch(descriptor)
        
        // 由于 unique 约束，应该只有一条记录
        #expect(results.count == 1)
    }
    
    // MARK: - Test 5: 修改数据测试
    
    @Test("应能修改已保存的统计数据")
    func testUpdatePlayCount() throws {
        // Arrange
        let container = try createTestModelContainer()
        let context = container.mainContext
        
        let statistics = SDStatistics(dateString: "2026-02-15", playCount: 1)
        context.insert(statistics)
        try context.save()
        
        // Act - 模拟增加播放次数
        statistics.playCount += 1
        try context.save()
        
        // Assert - 重新查询验证更新成功
        let descriptor = FetchDescriptor<SDStatistics>()
        let results = try context.fetch(descriptor)
        #expect(results.first?.playCount == 2)
    }
    
    // MARK: - Test 6: 删除数据测试
    
    @Test("应能删除统计数据")
    func testDeletion() throws {
        // Arrange
        let container = try createTestModelContainer()
        let context = container.mainContext
        
        let statistics = SDStatistics(dateString: "2026-02-15")
        context.insert(statistics)
        try context.save()
        
        // Act
        context.delete(statistics)
        try context.save()
        
        // Assert
        let descriptor = FetchDescriptor<SDStatistics>()
        let results = try context.fetch(descriptor)
        #expect(results.isEmpty)
    }
}
