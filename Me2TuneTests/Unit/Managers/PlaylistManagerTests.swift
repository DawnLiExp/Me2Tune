//
//  PlaylistManagerTests.swift
//  Me2TuneTests
//
//  Unit tests for PlaylistManager
//

import Testing
import Foundation
import SwiftData
@testable import Me2Tune

@MainActor
struct PlaylistManagerTests {
    
    // MARK: - Setup
    
    private func setup() throws -> (PlaylistManager, DataService) {
        let dataService = try createTestDataService()
        let manager = PlaylistManager(dataService: dataService)
        return (manager, dataService)
    }

    // MARK: - Basic Tests

    @Test("初始化")
    func testInit() throws {
        let (manager, _) = try setup()
        #expect(manager.tracks.isEmpty)
        #expect(manager.count == 0)
        #expect(manager.isEmpty)
    }

    // MARK: - Query Tests

    @Test("通过索引获取曲目")
    func testTrackAtIndex() throws {
        let dataService = try createTestDataService()
        
        let track1 = SDTrack.makeSample(title: "Song 1", urlString: "file:///song1.mp3")
        track1.isInPlaylist = true
        track1.playlistOrder = 0
        dataService.insert(track1)
        try dataService.save()
        
        // Init manager AFTER data is in DB
        let manager = PlaylistManager(dataService: dataService)
        
        #expect(manager.count == 1)
        let retrieved = manager.track(at: 0)
        #expect(retrieved?.title == "Song 1")
        #expect(manager.track(at: 1) == nil)
        #expect(manager.track(at: -1) == nil)
    }

    @Test("获取曲目索引")
    func testIndexOfTrack() throws {
        let (_, dataService) = try setup()
        
        let track1 = SDTrack.makeSample(title: "Song 1", urlString: "file:///song1.mp3")
        track1.isInPlaylist = true
        track1.playlistOrder = 0
        dataService.insert(track1)
        try dataService.save()
        
        let manager2 = PlaylistManager(dataService: dataService)
        
        let dto = manager2.tracks[0]
        #expect(manager2.index(of: dto) == 0)
        
        let unrelatedDTO = AudioTrack(
            id: UUID(),
            url: URL(string: "file:///other.mp3")!,
            title: "Other",
            artist: nil,
            albumTitle: nil,
            duration: 0,
            format: .unknown,
            bookmark: nil
        )
        #expect(manager2.index(of: unrelatedDTO) == nil)
    }

    // MARK: - Remove Tests

    @Test("移除曲目")
    func testRemoveTrack() async throws {
        let (manager, dataService) = try setup()
        
        // Create dummy files
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let file1 = tempDir.appendingPathComponent("song1.mp3")
        let file2 = tempDir.appendingPathComponent("song2.mp3")
        try "dummy".write(to: file1, atomically: true, encoding: .utf8)
        try "dummy".write(to: file2, atomically: true, encoding: .utf8)
        
        await manager.addTracks(urls: [file1, file2])
        #expect(manager.count == 2, "Manager should have 2 tracks initially")
        
        manager.removeTrack(at: 0)
        
        #expect(manager.count == 1, "Manager count should be 1 after removal")
        #expect(manager.tracks[0].title == "song2", "Remaining track should be song2")
        
        // Verify DB state
        let dbTracks = try dataService.fetchPlaylistTracks()
        #expect(dbTracks.count == 1, "DB should have 1 playlist track, found \(dbTracks.count)")
        if !dbTracks.isEmpty {
            #expect(dbTracks[0].title == "song2", "DB track should be song2")
            #expect(dbTracks[0].playlistOrder == 0, "song2 should be reindexed to 0, found \(String(describing: dbTracks[0].playlistOrder))")
        }
        
        let sdTrack1 = dataService.findTrack(byURL: file1.absoluteString)
        #expect(sdTrack1 == nil || sdTrack1?.isInPlaylist == false, "Removed track should either be deleted or marked not in playlist")
    }

    @Test("清空所有曲目")
    func testClearAll() throws {
        let (_, dataService) = try setup()
        
        let track1 = SDTrack.makeSample(title: "Song 1", urlString: "file:///song1.mp3")
        track1.isInPlaylist = true
        track1.playlistOrder = 0
        dataService.insert(track1)
        try dataService.save()
        
        let manager2 = PlaylistManager(dataService: dataService)
        #expect(manager2.count == 1)
        
        manager2.clearAll()
        
        #expect(manager2.isEmpty)
        #expect(try dataService.fetchPlaylistTracks().isEmpty)
    }

    // MARK: - Reorder Tests

    @Test("移动曲目顺序")
    func testMoveTrack() throws {
        let (_, dataService) = try setup()
        
        let track1 = SDTrack.makeSample(title: "Song 1", urlString: "file:///song1.mp3")
        track1.isInPlaylist = true
        track1.playlistOrder = 0
        dataService.insert(track1)
        
        let track2 = SDTrack.makeSample(title: "Song 2", urlString: "file:///song2.mp3")
        track2.isInPlaylist = true
        track2.playlistOrder = 1
        dataService.insert(track2)
        
        let track3 = SDTrack.makeSample(title: "Song 3", urlString: "file:///song3.mp3")
        track3.isInPlaylist = true
        track3.playlistOrder = 2
        dataService.insert(track3)
        
        try dataService.save()
        
        let manager2 = PlaylistManager(dataService: dataService)
        
        // Move Song 1 to the end (index 2)
        manager2.moveTrack(from: 0, to: 2)
        
        #expect(manager2.tracks[0].title == "Song 2")
        #expect(manager2.tracks[1].title == "Song 3")
        #expect(manager2.tracks[2].title == "Song 1")
        
        // Verify DB reindexing
        let dbTracks = try dataService.fetchPlaylistTracks()
        #expect(dbTracks.first(where: { $0.title == "Song 2" })?.playlistOrder == 0)
        #expect(dbTracks.first(where: { $0.title == "Song 3" })?.playlistOrder == 1)
        #expect(dbTracks.first(where: { $0.title == "Song 1" })?.playlistOrder == 2)
    }
}

// Since loadPlaylistContent is private, but I need it to sync for these manual DB injection tests.
// Actually, PlaylistManager.loadPlaylistContent() is private.
// I should use addTracks to test the flow properly, but for unit testing internal state,
// I might need to make it internal or test via public API.
// Wait, view_file showed:
// 191:     private func loadPlaylistContent() {
// So I can't call it. But init calls it.
// If I inject data into DataService BEFORE creating manager, it should work.

extension PlaylistManagerTests {
    // MARK: - Add Tests

    @Test("复用已有 SDTrack 时保持 stableId 并支持重排持久化")
    func testReuseExistingTrackKeepsStableIDAndReorderPersists() async throws {
        let dataService = try createTestDataService()

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let existingFile = tempDir.appendingPathComponent("a_existing.mp3")
        let newFile = tempDir.appendingPathComponent("b_new.mp3")
        try "dummy".write(to: existingFile, atomically: true, encoding: .utf8)
        try "dummy".write(to: newFile, atomically: true, encoding: .utf8)

        let existingTrack = SDTrack.makeSample(
            title: "Existing",
            urlString: existingFile.absoluteString
        )
        dataService.insert(existingTrack)
        try dataService.save()

        let manager = PlaylistManager(dataService: dataService)
        await manager.addTracks(urls: [existingFile, newFile])

        #expect(manager.count == 2)
        #expect(manager.tracks[0].id == existingTrack.stableId, "Reused SDTrack must project stableId to AudioTrack.id")

        manager.moveTrack(from: 0, to: 1)

        let playlistTracks = try dataService.fetchPlaylistTracks()
        let persistedExisting = playlistTracks.first(where: { $0.stableId == existingTrack.stableId })
        #expect(persistedExisting?.playlistOrder == 1)
    }

    @Test("添加曲目")
    func testAddTracks() async throws {
        let (manager, dataService) = try setup()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let file1 = tempDir.appendingPathComponent("test1.mp3")
        let file2 = tempDir.appendingPathComponent("test2.m4a")
        try "dummy content".write(to: file1, atomically: true, encoding: .utf8)
        try "dummy content".write(to: file2, atomically: true, encoding: .utf8)
        
        await manager.addTracks(urls: [file1, file2])
        
        #expect(manager.count == 2)
        #expect(manager.tracks[0].title == "test1")
        #expect(manager.tracks[1].title == "test2")
        
        // Verify DB
        let dbTracks = try dataService.fetchPlaylistTracks()
        #expect(dbTracks.count == 2)
        #expect(dbTracks.contains { $0.title == "test1" })
        #expect(dbTracks.contains { $0.title == "test2" })
    }

    @Test("从目录添加曲目")
    func testAddTracksFromDirectory() async throws {
        let (manager, _) = try setup()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let subDir = tempDir.appendingPathComponent("subdir", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let file1 = subDir.appendingPathComponent("inner.mp3")
        try "dummy".write(to: file1, atomically: true, encoding: .utf8)
        
        await manager.addTracks(urls: [tempDir])
        
        #expect(manager.count == 1)
        #expect(manager.tracks[0].title == "inner")
    }

    // MARK: - URL Processing Tests

    @Test("按目录排序URL")
    func testSortURLsByDirectory() async throws {
        let (manager, _) = try setup()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dirA = tempDir.appendingPathComponent("a", isDirectory: true)
        let dirB = tempDir.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let fileB1 = dirB.appendingPathComponent("song.mp3")
        let fileA1 = dirA.appendingPathComponent("song.mp3")
        let fileA2 = dirA.appendingPathComponent("another.mp3")
        
        try "dummy".write(to: fileB1, atomically: true, encoding: .utf8)
        try "dummy".write(to: fileA1, atomically: true, encoding: .utf8)
        try "dummy".write(to: fileA2, atomically: true, encoding: .utf8)
        
        // Add files in mixed order
        await manager.addTracks(urls: [fileB1, fileA1, fileA2])
        
        // Expected order: dirA/another, dirA/song, dirB/song
        #expect(manager.tracks[0].url.path.contains("a/another.mp3"))
        #expect(manager.tracks[1].url.path.contains("a/song.mp3"))
        #expect(manager.tracks[2].url.path.contains("b/song.mp3"))
    }

    @Test("初始化时已有数据")
    func testInitWithData() throws {
        let dataService = try createTestDataService()
        let track1 = SDTrack.makeSample(title: "Existing", urlString: "file:///existing.mp3")
        track1.isInPlaylist = true
        track1.playlistOrder = 0
        dataService.insert(track1)
        try dataService.save()
        
        let manager = PlaylistManager(dataService: dataService)
        #expect(manager.count == 1)
        #expect(manager.tracks.first?.title == "Existing")
    }
}
