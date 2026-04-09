//
//  DataServiceTests.swift
//  Me2TuneTests
//
//  【Level 2】DataService 单元测试 - 验证数据访问层功能
//

import Foundation
import SwiftData
import Testing
@testable import Me2Tune

@MainActor
@Suite("DataService 单元测试")
struct DataServiceTests {
    
    // MARK: - Track 操作测试
    
    @Test("插入和查询 Track")
    func testInsertAndFindTrack() throws {
        // Arrange
        let dataService = try createTestDataService()
        let track = SDTrack.makeSample(
            title: "Test Track",
            urlString: "file:///music/test.flac"
        )
        
        // Act
        dataService.insert(track)
        try dataService.save()
        
        // Assert
        let found = dataService.findTrack(byURL: "file:///music/test.flac")
        #expect(found != nil)
        #expect(found?.title == "Test Track")
    }
    
    @Test("通过 UUID 查找 Track")
    func testFindTrackByStableId() throws {
        // Arrange
        let dataService = try createTestDataService()
        let track = SDTrack.makeSample()
        dataService.insert(track)
        try dataService.save()
        
        // Act
        let found = dataService.findTrack(byStableId: track.stableId)
        
        // Assert
        #expect(found != nil)
        #expect(found?.stableId == track.stableId)
    }
    
    @Test("查询播放列表轨道")
    func testFetchPlaylistTracks() throws {
        // Arrange
        let dataService = try createTestDataService()
        
        let track1 = SDTrack.makeSample(title: "Track 1", urlString: "file:///1.mp3")
        track1.isInPlaylist = true
        track1.playlistOrder = 0
        
        let track2 = SDTrack.makeSample(title: "Track 2", urlString: "file:///2.mp3")
        track2.isInPlaylist = true
        track2.playlistOrder = 1
        
        let track3 = SDTrack.makeSample(title: "Track 3", urlString: "file:///3.mp3")
        track3.isInPlaylist = false
        
        dataService.insert(track1)
        dataService.insert(track2)
        dataService.insert(track3)
        try dataService.save()
        
        // Act
        let playlistTracks = try dataService.fetchPlaylistTracks()
        
        // Assert
        #expect(playlistTracks.count == 2)
        #expect(playlistTracks[0].title == "Track 1")
        #expect(playlistTracks[1].title == "Track 2")
    }
    
    @Test("统计播放列表歌曲数量")
    func testPlaylistTrackCount() throws {
        // Arrange
        let dataService = try createTestDataService()
        
        for i in 0..<5 {
            let track = SDTrack.makeSample(urlString: "file:///\(i).mp3")
            track.isInPlaylist = i < 3
            dataService.insert(track)
        }
        try dataService.save()
        
        // Act
        let count = try dataService.playlistTrackCount()
        
        // Assert
        #expect(count == 3)
    }
    
    // MARK: - Album 操作测试
    
    @Test("插入和查询 Album")
    func testInsertAndFindAlbum() throws {
        // Arrange
        let dataService = try createTestDataService()
        let album = SDAlbum.makeSample(
            name: "Test Album",
            folderURLString: "file:///music/album"
        )
        
        // Act
        dataService.insert(album)
        try dataService.save()
        
        // Assert
        let found = dataService.findAlbum(byFolderURL: "file:///music/album")
        #expect(found != nil)
        #expect(found?.name == "Test Album")
    }
    
    @Test("查询所有专辑")
    func testFetchAlbums() throws {
        // Arrange
        let dataService = try createTestDataService()
        
        let album1 = SDAlbum.makeSample(name: "Album A", displayOrder: 1)
        let album2 = SDAlbum.makeSample(name: "Album B", folderURLString: "file:///test/album2", displayOrder: 0)
        
        dataService.insert(album1)
        dataService.insert(album2)
        try dataService.save()
        
        // Act
        let albums = try dataService.fetchAlbums()
        
        // Assert
        #expect(albums.count == 2)
        // 验证按 displayOrder 排序
        #expect(albums[0].name == "Album B")
        #expect(albums[1].name == "Album A")
    }
    
    @Test("统计专辑数量")
    func testAlbumCount() throws {
        // Arrange
        let dataService = try createTestDataService()
        
        for i in 0..<3 {
            dataService.insert(SDAlbum.makeSample(
                name: "Album \(i)",
                folderURLString: "file:///test/album\(i)"
            ))
        }
        try dataService.save()
        
        // Act
        let count = try dataService.albumCount()
        
        // Assert
        #expect(count == 3)
    }

    @Test("V1 升级到 V2 后保留媒体库数据")
    func testMigrateV1ToV2KeepsLibraryData() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Me2TuneMigration-\(UUID().uuidString)", isDirectory: true)
        let storeURL = directoryURL.appendingPathComponent("Me2Tune.store")

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        // Step 1: 建立 V1 store 并写入样本数据
        do {
            let v1Schema = Schema(Me2TuneSchemaV1.models)
            let v1Config = ModelConfiguration(schema: v1Schema, url: storeURL)
            let v1Container = try ModelContainer(for: v1Schema, configurations: [v1Config])
            let context = v1Container.mainContext

            let track = SDTrack.makeSample(title: "Legacy Track", urlString: "file:///legacy/track.mp3")
            track.isInPlaylist = true
            track.playlistOrder = 0
            context.insert(track)

            let album = SDAlbum.makeSample(name: "Legacy Album", folderURLString: "file:///legacy/album")
            context.insert(album)
            context.insert(SDAlbumTrackEntry(trackOrder: 0, album: album, track: track))

            let legacyState = SDPlaybackState()
            legacyState.playingSourceType = SDPlaybackState.sourcePlaylist
            legacyState.playlistCurrentIndex = 0
            context.insert(legacyState)

            try context.save()
        }

        // Step 2: 用 V2 + migration plan 打开同一 store，验证核心媒体数据仍可读取
        do {
            let v2Schema = Schema(Me2TuneSchemaV2.models)
            let v2Config = ModelConfiguration(schema: v2Schema, url: storeURL)
            let v2Container = try ModelContainer(
                for: v2Schema,
                migrationPlan: Me2TuneMigrationPlan.self,
                configurations: [v2Config]
            )
            let migratedService = DataService(modelContainer: v2Container)

            let tracks = try migratedService.fetchPlaylistTracks()
            #expect(tracks.count == 1)
            #expect(tracks.first?.title == "Legacy Track")

            let albums = try migratedService.fetchAlbums()
            #expect(albums.count == 1)
            #expect(albums.first?.name == "Legacy Album")
        }
    }
    
    // MARK: - Generic CRUD 测试
    
    @Test("删除模型")
    func testDeleteModel() throws {
        // Arrange
        let dataService = try createTestDataService()
        let track = SDTrack.makeSample()
        dataService.insert(track)
        try dataService.save()
        
        // Act
        dataService.delete(track)
        try dataService.save()
        
        // Assert
        let descriptor = FetchDescriptor<SDTrack>()
        let tracks = try dataService.fetch(descriptor)
        #expect(tracks.isEmpty)
    }
    
    @Test("查询计数")
    func testFetchCount() throws {
        // Arrange
        let dataService = try createTestDataService()
        
        for i in 0..<10 {
            dataService.insert(SDTrack.makeSample(urlString: "file:///\(i).mp3"))
        }
        try dataService.save()
        
        // Act
        let descriptor = FetchDescriptor<SDTrack>()
        let count = try dataService.fetchCount(descriptor)
        
        // Assert
        #expect(count == 10)
    }
}
