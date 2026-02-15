//
//  StatisticsManager.swift
//  Me2Tune
//
//  统计数据管理器 - 负责数据持久化、聚合补全与定期清理
//

import Foundation
import OSLog
import SwiftData

private let logger = Logger.persistence

// MARK: - Models

struct DailyStatItem: Identifiable, Equatable {
    let id: String // yyyy-MM-dd or year-month or year-week
    let date: Date
    let playCount: Int
}

enum StatPeriod: String, CaseIterable {
    case daily = "stat_period_daily"
    case weekly = "stat_period_weekly"
    case monthly = "stat_period_monthly"
    
    var days: Int {
        switch self {
        case .daily: return 30
        case .weekly: return 84 // 12 weeks
        case .monthly: return 365
        }
    }
    
    var displayName: String {
        NSLocalizedString(rawValue, comment: "Statistics period display name")
    }
}

// MARK: - Manager

@MainActor
final class StatisticsManager: StatisticsManagerProtocol {
    static let shared = StatisticsManager()
    
    private let dataService: DataServiceProtocol
    private var modelContext: ModelContext {
        dataService.modelContext
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        return formatter
    }()
    
    /// 支持依赖注入 - 默认使用单例
    init(dataService: DataServiceProtocol = DataService.shared) {
        self.dataService = dataService
    }
    
    // MARK: - Actions
    
    func incrementTodayPlayCount() async {
        let now = Date()
        let today = Self.dateFormatter.string(from: now)
        
        let descriptor = FetchDescriptor<SDStatistics>(
            predicate: #Predicate { $0.dateString == today }
        )
        
        do {
            if let stat = try modelContext.fetch(descriptor).first {
                stat.playCount += 1
                logger.debug("📈 Increment playCount for \(today): \(stat.playCount)")
            } else {
                let newStat = SDStatistics(dateString: today, playCount: 1)
                modelContext.insert(newStat)
                logger.debug("📈 Created new statistics record for \(today)")
            }
            
            checkAndCleanupIfNeeded(today: today)
        } catch {
            logger.error("❌ Failed to increment play count: \(error)")
        }
    }
    
    /// Fetches aggregated statistics for the specified period.
    func fetchAggregatedStats(period: StatPeriod) async -> [DailyStatItem] {
        let rawData = await fetchRecentStatistics(days: period.days)
        
        switch period {
        case .daily:
            return rawData
        case .weekly:
            return aggregateByWeek(rawData)
        case .monthly:
            return aggregateByMonth(rawData)
        }
    }
    
    /// Fetches raw daily statistics for the recent N days, filling gaps with zero values.
    func fetchRecentStatistics(days: Int = 30) async -> [DailyStatItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return []
        }
        
        let descriptor = FetchDescriptor<SDStatistics>(
            predicate: #Predicate { $0.createdAt >= startDate },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        
        let dbStats: [SDStatistics]
        do {
            dbStats = try modelContext.fetch(descriptor)
        } catch {
            logger.error("❌ Failed to fetch statistics: \(error)")
            dbStats = []
        }
        
        let statsDict = Dictionary(
            uniqueKeysWithValues: dbStats.map { ($0.dateString, $0.playCount) }
        )
        
        var result: [DailyStatItem] = []
        for dayOffset in 0 ..< days {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else { continue }
            let dateString = Self.dateFormatter.string(from: date)
            let playCount = statsDict[dateString] ?? 0
            
            result.append(DailyStatItem(
                id: dateString,
                date: date,
                playCount: playCount
            ))
        }
        
        return result
    }
    
    func cleanupOldData(keepDays: Int = 365) {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -keepDays, to: Date()) else { return }
        
        let descriptor = FetchDescriptor<SDStatistics>(
            predicate: #Predicate { $0.createdAt < cutoffDate }
        )
        
        do {
            let oldStats = try modelContext.fetch(descriptor)
            if !oldStats.isEmpty {
                for stat in oldStats {
                    modelContext.delete(stat)
                }
                logger.info("🧹 Cleaned up \(oldStats.count) old statistics records")
            }
        } catch {
            logger.error("❌ Failed to cleanup old statistics: \(error)")
        }
    }
    
    // MARK: - Private Helpers
    
    /// Checks if cleanup has been performed today; if not, triggers it.
    private func checkAndCleanupIfNeeded(today: String) {
        let key = "LastStatisticsCleanupDate"
        let lastCleanup = UserDefaults.standard.string(forKey: key)
        
        if lastCleanup != today {
            // Perform cleanup asynchronously to avoid blocking the main task
            Task { @MainActor [weak self] in
                self?.cleanupOldData(keepDays: 365)
                UserDefaults.standard.set(today, forKey: key)
                logger.info("🧹 Daily statistics cleanup executed for \(today)")
            }
        }
    }
    
    private func aggregateByWeek(_ data: [DailyStatItem]) -> [DailyStatItem] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: data) { item in
            calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: item.date)
        }
        
        return grouped.compactMap { components, items in
            guard let date = calendar.date(from: components) else { return nil }
            let totalPlays = items.reduce(0) { $0 + $1.playCount }
            return DailyStatItem(
                id: "W\(components.yearForWeekOfYear!)-\(components.weekOfYear!)",
                date: date,
                playCount: totalPlays
            )
        }.sorted { $0.date < $1.date }
    }
    
    private func aggregateByMonth(_ data: [DailyStatItem]) -> [DailyStatItem] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: data) { item in
            calendar.dateComponents([.year, .month], from: item.date)
        }
        
        return grouped.compactMap { components, items in
            guard let date = calendar.date(from: components) else { return nil }
            let totalPlays = items.reduce(0) { $0 + $1.playCount }
            return DailyStatItem(
                id: "M\(components.year!)-\(components.month!)",
                date: date,
                playCount: totalPlays
            )
        }.sorted { $0.date < $1.date }
    }
}
