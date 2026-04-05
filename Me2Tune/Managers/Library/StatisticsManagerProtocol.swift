//
//  StatisticsManagerProtocol.swift
//  Me2Tune
//
//  统计管理器协议 - 定义统计数据操作接口
//

import Foundation

@MainActor
protocol StatisticsManagerProtocol: Sendable {
    /// 增加今天的播放计数
    func incrementTodayPlayCount() async

    /// 获取聚合统计数据
    func fetchAggregatedStats(period: StatPeriod) async -> [DailyStatItem]

    /// 获取最近指定天数的统计数据
    func fetchRecentStatistics(days: Int) async -> [DailyStatItem]

    /// 清理旧数据
    func cleanupOldData(keepDays: Int)
}
