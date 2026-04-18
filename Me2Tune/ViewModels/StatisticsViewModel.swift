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
    private struct OverviewSnapshot {
        let totalTracks: Int
        let totalAlbums: Int
        let uniqueArtists: Int
    }

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
    @ObservationIgnored private var presentationRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var activePresentationSessionID: Int?
    @ObservationIgnored private var loadedStatisticsRevision: Int?
    private var nextPresentationSessionID = 0
    
    // MARK: - Initialization
    
    init(
        dataService: DataServiceProtocol = DataService.shared,
        statisticsManager: StatisticsManagerProtocol = StatisticsManager.shared
    ) {
        self.dataService = dataService
        self.statisticsManager = statisticsManager
    }
    
    // MARK: - Actions
    
    func loadOverviewIfNeeded() async {
        guard !overviewLoaded else { return }

        let snapshot = await fetchOverviewSnapshot()
        applyOverviewSnapshot(snapshot)
    }

    func refreshPresentationSnapshot() async {
        await refreshPresentationSnapshot(for: nil)
    }

    func beginPresentationSession(refreshDelay: Duration = .seconds(1)) {
        presentationRefreshTask?.cancel()

        nextPresentationSessionID += 1
        let sessionID = nextPresentationSessionID
        activePresentationSessionID = sessionID

        presentationRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(for: refreshDelay, clock: .continuous)
            guard !Task.isCancelled, self.activePresentationSessionID == sessionID else { return }

            while self.isLoading {
                try? await Task.sleep(for: .milliseconds(50), clock: .continuous)
                guard !Task.isCancelled, self.activePresentationSessionID == sessionID else { return }
            }

            await self.refreshPresentationSnapshotIfNeeded(for: sessionID)

            if self.activePresentationSessionID == sessionID {
                self.presentationRefreshTask = nil
            }
        }
    }

    func endPresentationSession() {
        presentationRefreshTask?.cancel()
        presentationRefreshTask = nil
        activePresentationSessionID = nil
    }

    private func refreshPresentationSnapshot(for sessionID: Int?) async {
        guard !isLoading else { return }

        let snapshotRevision = statisticsManager.statisticsRevision

        isLoading = true
        defer { isLoading = false }

        async let overviewSnapshot = fetchOverviewSnapshot()
        async let statsSnapshot = fetchAllPeriodsSnapshot()

        let (overview, periodSnapshots) = await (overviewSnapshot, statsSnapshot)

        if let sessionID, activePresentationSessionID != sessionID {
            return
        }

        applyOverviewSnapshot(overview)
        statsCache = periodSnapshots
        stats = statsCache[selectedPeriod] ?? []
        loadedStatisticsRevision = snapshotRevision
    }
    
    // MARK: - Private Helpers
    
    private func fetchAllPeriodsSnapshot() async -> [StatPeriod: [DailyStatItem]] {
        var snapshots: [StatPeriod: [DailyStatItem]] = [:]

        await withTaskGroup(of: (StatPeriod, [DailyStatItem]).self) { group in
            for period in StatPeriod.allCases {
                group.addTask {
                    let data = await self.statisticsManager.fetchAggregatedStats(period: period)
                    return (period, data)
                }
            }
            
            for await (period, data) in group {
                snapshots[period] = data
            }
        }

        return snapshots
    }

    private func refreshPresentationSnapshotIfNeeded(for sessionID: Int?) async {
        guard shouldRefreshPresentationSnapshot() else { return }
        await refreshPresentationSnapshot(for: sessionID)
    }

    private func shouldRefreshPresentationSnapshot() -> Bool {
        if !overviewLoaded {
            return true
        }

        if statsCache.count != StatPeriod.allCases.count {
            return true
        }

        return loadedStatisticsRevision != statisticsManager.statisticsRevision
    }

    private func fetchOverviewSnapshot() async -> OverviewSnapshot {
        async let trackCount = fetchTotalTracks()
        async let albumCount = fetchTotalAlbums()
        async let artistCount = fetchUniqueArtists()

        let (totalTracks, totalAlbums, uniqueArtists) = await (trackCount, albumCount, artistCount)
        return OverviewSnapshot(
            totalTracks: totalTracks,
            totalAlbums: totalAlbums,
            uniqueArtists: uniqueArtists
        )
    }

    private func applyOverviewSnapshot(_ snapshot: OverviewSnapshot) {
        totalTracks = snapshot.totalTracks
        totalAlbums = snapshot.totalAlbums
        uniqueArtists = snapshot.uniqueArtists
        overviewLoaded = true
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
