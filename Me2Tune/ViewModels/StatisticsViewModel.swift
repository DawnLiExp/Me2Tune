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
    
    var selectedPeriod: StatPeriod = .daily {
        didSet {
            if let cachedData = statsCache[selectedPeriod] {
                stats = cachedData
            }
        }
    }
    
    private let dataService: DataServiceProtocol
    private let statisticsManager: StatisticsManagerProtocol
    
    private var modelContext: ModelContext {
        dataService.modelContext
    }
    
    // MARK: - Cache
    
    private var statsCache: [StatPeriod: [DailyStatItem]] = [:]
    private var overviewLoaded = false
    
    // MARK: - Initialization
    
    init(
        dataService: DataServiceProtocol = DataService.shared,
        statisticsManager: StatisticsManagerProtocol = StatisticsManager.shared
    ) {
        self.dataService = dataService
        self.statisticsManager = statisticsManager
    }
    
    // MARK: - Actions
    
    func preloadAll() async {
        guard !isLoading else { return }
        
        isLoading = true
        defer { isLoading = false }
    
        if !overviewLoaded {
            async let trackCount = fetchTotalTracks()
            async let albumCount = fetchTotalAlbums()
            async let artistCount = fetchUniqueArtists()
            
            let (tCount, aCount, rCount) = await (trackCount, albumCount, artistCount)
            
            self.totalTracks = tCount
            self.totalAlbums = aCount
            self.uniqueArtists = rCount
            self.overviewLoaded = true
        }
        
        await loadAllPeriods()
        
        if let cachedData = statsCache[selectedPeriod] {
            stats = cachedData
        }
    }

    func loadCurrentPeriodIfNeeded() async {
        guard statsCache[selectedPeriod] == nil else {
            if let cachedData = statsCache[selectedPeriod] {
                stats = cachedData
            }
            return
        }
        
        guard !isLoading else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        let sData = await statisticsManager.fetchAggregatedStats(period: selectedPeriod)
        statsCache[selectedPeriod] = sData
        stats = sData
    }
    
    // MARK: - Private Helpers
    
    private func loadAllPeriods() async {
        await withTaskGroup(of: (StatPeriod, [DailyStatItem]).self) { group in
            for period in StatPeriod.allCases {
                group.addTask {
                    let data = await self.statisticsManager.fetchAggregatedStats(period: period)
                    return (period, data)
                }
            }
            
            for await (period, data) in group {
                statsCache[period] = data
            }
        }
    }
    
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
