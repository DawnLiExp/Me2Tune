//
//  StatisticsViewModel.swift
//  Me2Tune
//
//  统计功能视图模型 - 负责数据聚合加载与性能优化
//

import Foundation
import Observation
import OSLog
import SwiftData

private let logger = Logger.application

@MainActor
@Observable
final class StatisticsViewModel {
    // MARK: - Properties
    
    private(set) var stats: [DailyStatItem] = []
    private(set) var totalTracks: Int = 0
    private(set) var totalAlbums: Int = 0
    private(set) var uniqueArtists: Int = 0
    private(set) var isLoading: Bool = false
    
    var selectedPeriod: StatPeriod = .daily
    
    private let dataService = DataService.shared
    private let statisticsManager = StatisticsManager.shared
    
    private var modelContext: ModelContext {
        dataService.modelContext
    }
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Actions
    
    func loadStatistics() async {
        guard !isLoading else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        // Parallel queries for overview counts and aggregated stats
        async let trackCount = fetchTotalTracks()
        async let albumCount = fetchTotalAlbums()
        async let artistCount = fetchUniqueArtists()
        async let aggregatedStats = statisticsManager.fetchAggregatedStats(period: selectedPeriod)
        
        let (tCount, aCount, rCount, sData) = await (trackCount, albumCount, artistCount, aggregatedStats)
        
        self.totalTracks = tCount
        self.totalAlbums = aCount
        self.uniqueArtists = rCount
        self.stats = sData
    }
    
    // MARK: - Private Helpers
    
    private func fetchTotalTracks() async -> Int {
        let descriptor = FetchDescriptor<SDTrack>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }
    
    private func fetchTotalAlbums() async -> Int {
        let descriptor = FetchDescriptor<SDAlbum>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }
    
    private func fetchUniqueArtists() async -> Int {
        // Performance: fetch only 'artist' property
        var descriptor = FetchDescriptor<SDTrack>(
            predicate: #Predicate<SDTrack> { $0.artist != nil }
        )
        descriptor.propertiesToFetch = [\.artist]
        
        do {
            let tracks = try modelContext.fetch(descriptor)
            let artists = Set(tracks.compactMap(\.artist))
            return artists.count
        } catch {
            logger.error("❌ Failed to fetch unique artists: \(error)")
            return 0
        }
    }
}
