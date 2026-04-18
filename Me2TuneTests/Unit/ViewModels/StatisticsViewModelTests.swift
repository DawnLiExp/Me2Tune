//
//  StatisticsViewModelTests.swift
//  Me2TuneTests
//
//  Unit tests for settings statistics snapshot refresh scheduling.
//

import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("StatisticsViewModel 单元测试")
struct StatisticsViewModelTests {
    @Test("refreshPresentationSnapshot 会刷新概览与所有周期缓存")
    func refreshPresentationSnapshotRefreshesOverviewAndAllPeriods() async throws {
        let dataService = try createTestDataService()

        let albumA = SDAlbum(name: "Album A", folderURLString: "file:///tmp/album-a", displayOrder: 0)
        let albumB = SDAlbum(name: "Album B", folderURLString: "file:///tmp/album-b", displayOrder: 1)
        dataService.insert(albumA)
        dataService.insert(albumB)

        dataService.insert(SDTrack.makeSample(title: "Track 1", artist: "Artist A", albumTitle: "Album A", urlString: "file:///tmp/stat-track-1.mp3"))
        dataService.insert(SDTrack.makeSample(title: "Track 2", artist: "Artist B", albumTitle: "Album A", urlString: "file:///tmp/stat-track-2.mp3"))
        dataService.insert(SDTrack.makeSample(title: "Track 3", artist: "Artist A", albumTitle: "Album B", urlString: "file:///tmp/stat-track-3.mp3"))
        try dataService.save()

        let statisticsManager = MockStatisticsManager(periodData: [
            .daily: [DailyStatItem(id: "d", date: Date(), playCount: 2)],
            .weekly: [DailyStatItem(id: "w", date: Date(), playCount: 5)],
            .monthly: [DailyStatItem(id: "m", date: Date(), playCount: 9)]
        ])
        let viewModel = StatisticsViewModel(
            dataService: dataService,
            statisticsManager: statisticsManager
        )
        viewModel.selectedPeriod = .weekly

        await viewModel.refreshPresentationSnapshot()

        #expect(viewModel.totalTracks == 3)
        #expect(viewModel.totalAlbums == 2)
        #expect(viewModel.uniqueArtists == 2)
        #expect(viewModel.stats == (statisticsManager.periodData[.weekly] ?? []))
        #expect(statisticsManager.fetchCalls.sorted { $0.rawValue < $1.rawValue } == StatPeriod.allCases.sorted { $0.rawValue < $1.rawValue })
    }

    @Test("loadOverviewIfNeeded 仅首次加载概览")
    func loadOverviewIfNeededLoadsOnce() async throws {
        let dataService = try createTestDataService()
        dataService.insert(SDTrack.makeSample(title: "Track 1", artist: "Artist A", albumTitle: "Album A", urlString: "file:///tmp/overview-track-1.mp3"))
        try dataService.save()

        let statisticsManager = MockStatisticsManager()
        let viewModel = StatisticsViewModel(
            dataService: dataService,
            statisticsManager: statisticsManager
        )

        await viewModel.loadOverviewIfNeeded()

        dataService.insert(SDTrack.makeSample(title: "Track 2", artist: "Artist B", albumTitle: "Album B", urlString: "file:///tmp/overview-track-2.mp3"))
        try dataService.save()

        await viewModel.loadOverviewIfNeeded()

        #expect(viewModel.totalTracks == 1)
        #expect(statisticsManager.fetchCalls.isEmpty)
    }

    @Test("beginPresentationSession 会按延迟刷新快照")
    func beginPresentationSessionRunsDelayedSnapshot() async throws {
        let dataService = try createTestDataService()
        dataService.insert(SDTrack.makeSample(title: "Track 1", artist: "Artist A", albumTitle: "Album A", urlString: "file:///tmp/scheduled-track-1.mp3"))
        try dataService.save()

        let statisticsManager = MockStatisticsManager(periodData: [
            .daily: [DailyStatItem(id: "d", date: Date(), playCount: 7)]
        ])
        let viewModel = StatisticsViewModel(
            dataService: dataService,
            statisticsManager: statisticsManager
        )

        viewModel.beginPresentationSession(refreshDelay: .milliseconds(30))
        try? await Task.sleep(for: .milliseconds(120))

        #expect(viewModel.totalTracks == 1)
        #expect(viewModel.stats == (statisticsManager.periodData[.daily] ?? []))
        #expect(statisticsManager.fetchCalls.count == StatPeriod.allCases.count)
    }

    @Test("结束展示会话后不会执行刷新")
    func endPresentationSessionPreventsExecution() async throws {
        let dataService = try createTestDataService()
        dataService.insert(SDTrack.makeSample(title: "Track 1", artist: "Artist A", albumTitle: "Album A", urlString: "file:///tmp/cancel-track-1.mp3"))
        try dataService.save()

        let statisticsManager = MockStatisticsManager(periodData: [
            .daily: [DailyStatItem(id: "d", date: Date(), playCount: 7)]
        ])
        let viewModel = StatisticsViewModel(
            dataService: dataService,
            statisticsManager: statisticsManager
        )

        viewModel.beginPresentationSession(refreshDelay: .milliseconds(80))
        viewModel.endPresentationSession()
        try? await Task.sleep(for: .milliseconds(160))

        #expect(viewModel.totalTracks == 0)
        #expect(viewModel.stats.isEmpty)
        #expect(statisticsManager.fetchCalls.isEmpty)
    }

    @Test("关闭后再次打开会刷新新快照")
    func reopeningPresentationSessionRefreshesNewSnapshot() async throws {
        let dataService = try createTestDataService()
        dataService.insert(SDTrack.makeSample(title: "Track 1", artist: "Artist A", albumTitle: "Album A", urlString: "file:///tmp/reopen-track-1.mp3"))
        try dataService.save()

        let statisticsManager = MockStatisticsManager(periodData: [
            .daily: [DailyStatItem(id: "d1", date: Date(), playCount: 3)],
            .weekly: [],
            .monthly: []
        ])
        let viewModel = StatisticsViewModel(
            dataService: dataService,
            statisticsManager: statisticsManager
        )

        viewModel.beginPresentationSession(refreshDelay: .milliseconds(20))
        try? await Task.sleep(for: .milliseconds(120))

        #expect(viewModel.stats == (statisticsManager.periodData[.daily] ?? []))

        statisticsManager.periodData = [
            .daily: [DailyStatItem(id: "d2", date: Date().addingTimeInterval(60), playCount: 8)],
            .weekly: [],
            .monthly: []
        ]

        viewModel.endPresentationSession()
        viewModel.beginPresentationSession(refreshDelay: .milliseconds(20))
        try? await Task.sleep(for: .milliseconds(120))

        #expect(viewModel.stats == (statisticsManager.periodData[.daily] ?? []))
        #expect(statisticsManager.fetchCalls.count == StatPeriod.allCases.count * 2)
    }
}

@MainActor
private final class MockStatisticsManager: StatisticsManagerProtocol {
    var periodData: [StatPeriod: [DailyStatItem]]
    private(set) var fetchCalls: [StatPeriod] = []

    init(periodData: [StatPeriod: [DailyStatItem]] = [:]) {
        self.periodData = periodData
    }

    func incrementTodayPlayCount() async {}

    func fetchAggregatedStats(period: StatPeriod) async -> [DailyStatItem] {
        fetchCalls.append(period)
        return periodData[period] ?? []
    }

    func fetchRecentStatistics(days: Int) async -> [DailyStatItem] {
        []
    }

    func cleanupOldData(keepDays: Int) {}
}
