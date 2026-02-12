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

struct DailyStatItem: Identifiable {
    let id: String // yyyy-MM-dd
    let date: Date
    let playCount: Int
}

// MARK: - Manager

@MainActor
final class StatisticsManager {
    static let shared = StatisticsManager()
    
    private let dataService = DataService.shared
    private var modelContext: ModelContext {
        dataService.modelContext
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        return formatter
    }()
    
    private init() {}
    
    // MARK: - Actions
    
    func incrementTodayPlayCount() {
        let today = Self.dateFormatter.string(from: Date())
        
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
        } catch {
            logger.error("❌ Failed to increment play count: \(error)")
        }
    }
    
    /// Fetches statistics for the recent N days, filling gaps with zero values.
    func fetchRecentStatistics(days: Int = 30) async -> [DailyStatItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return []
        }
        
        // 1. Fetch existing records
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
        
        // 2. Fill missing dates to ensure continuous chart data
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
    
    func cleanupOldData(keepDays: Int = 30) {
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
}
