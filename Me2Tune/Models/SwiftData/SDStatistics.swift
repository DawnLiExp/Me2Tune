//
//  SDStatistics.swift
//  Me2Tune
//
//  SwiftData 统计数据模型 - 记录每日播放次数
//

import Foundation
import SwiftData

@Model
final class SDStatistics {
    // MARK: - Properties

    /// Unique identifier for the date (format: yyyy-MM-dd).
    @Attribute(.unique) var dateString: String

    var playCount: Int

    /// Used for cleanup logic to determine record age.
    var createdAt: Date

    // MARK: - Initialization

    init(dateString: String, playCount: Int = 0, createdAt: Date = Date()) {
        self.dateString = dateString
        self.playCount = playCount
        self.createdAt = createdAt
    }
}
