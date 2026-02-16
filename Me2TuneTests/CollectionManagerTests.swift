//
//  CollectionManagerTests.swift
//  Me2TuneTests
//
//  CollectionManager 单元测试 - 验证专辑收藏管理功能
//

import Foundation
import SwiftData
import Testing
@testable import Me2Tune

@MainActor
@Suite("CollectionManager 单元测试")
struct CollectionManagerTests {
    
    // MARK: - Setup Helpers
    
    private func setup() throws -> (CollectionManager, DataService) {
        let dataService = try createTestDataService()
        let manager = CollectionManager(dataService: dataService)
        return (manager, dataService)
    }
    
    private func setupWithAlbums(count: Int) throws -> (CollectionManager, DataService, [SDAlbum]) {
        let dataService = try createTestDataService()
        var albums: [SDAlbum] = []
        
        for i in 0..<count {
            let album = SDAlbum.makeSample(
                name: "Album \(i)",
                folderURLString: "file:///test/album\(i)",
                displayOrder: i
            )
            dataService.insert(album)
            albums.append(album)
        }
        try dataService.save()
        
        let manager = CollectionManager(dataService: dataService)
        return (manager, dataService, albums)
    }
    
    // MARK: - 基础测试
    
    @Test("初始化")
    func testInit() throws {
        let (manager, _) = try setup()
        #expect(manager.albums.isEmpty)
        #expect(manager.albumCount == 0)
        #expect(!manager.isLoaded)
        #expect(!manager.isLoading)
    }
    
    @Test("计算属性 - albumCount")
    func testAlbumCount() throws {
        let (manager, dataService) = try setup()
        
        // 初始为空
        #expect(manager.albumCount == 0)
        
        // 手动添加到数据库并加载
        let album1 = SDAlbum.makeSample(name: "Album 1", displayOrder: 0)
        let album2 = SDAlbum.makeSample(name: "Album 2", folderURLString: "file:///test/album2", displayOrder: 1)
        dataService.insert(album1)
        dataService.insert(album2)
        try dataService.save()
        
        // 重新创建 manager 以加载数据
        let manager2 = CollectionManager(dataService: dataService)
        Task {
            await manager2.ensureLoaded()
            #expect(manager2.albumCount == 2)
        }
    }
    
    // MARK: - 延迟加载测试
    
    @Test("延迟加载 - scheduleDelayedLoad")
    func testScheduleDelayedLoad() async throws {
        let (manager, dataService) = try setup()
        
        // 创建测试数据
        let album = SDAlbum.makeSample(name: "Test Album")
        dataService.insert(album)
        try dataService.save()
        
        // 调度延迟加载
        manager.scheduleDelayedLoad(delay: 0.1)
        #expect(!manager.isLoaded)
        
        // 使用轮询等待加载完成（最多等待 1 秒）
        var attempts = 0
        while !manager.isLoaded && attempts < 20 {
            try await Task.sleep(for: .milliseconds(50))
            attempts += 1
        }
        
        #expect(manager.isLoaded, "Manager should be loaded after delay")
        #expect(manager.albumCount == 1, "Should have loaded 1 album")
    }
    
    @Test("延迟加载 - 避免重复调度")
    func testScheduleDelayedLoadIdempotent() async throws {
        let (manager, _) = try setup()
        
        // 第一次调度
        manager.scheduleDelayedLoad(delay: 0.5)
        
        // 第二次调度应该被忽略
        manager.scheduleDelayedLoad(delay: 0.5)
        
        // 等待一段时间后取消
        try await Task.sleep(for: .seconds(0.1))
        
        // ensureLoaded 应该能取消延迟任务
        await manager.ensureLoaded()
        #expect(manager.isLoaded)
    }
    
    @Test("立即加载 - ensureLoaded")
    func testEnsureLoaded() async throws {
        let (manager, dataService) = try setup()
        
        let album1 = SDAlbum.makeSample(name: "Album 1", displayOrder: 0)
        let album2 = SDAlbum.makeSample(name: "Album 2", folderURLString: "file:///test/album2", displayOrder: 1)
        dataService.insert(album1)
        dataService.insert(album2)
        try dataService.save()
        
        #expect(!manager.isLoaded)
        
        await manager.ensureLoaded()
        
        #expect(manager.isLoaded)
        #expect(!manager.isLoading)
        #expect(manager.albumCount == 2)
    }
    
    @Test("立即加载 - 幂等性")
    func testEnsureLoadedIdempotent() async throws {
        let (manager, _) = try setup()
        
        await manager.ensureLoaded()
        #expect(manager.isLoaded)
        
        // 第二次调用应该立即返回
        await manager.ensureLoaded()
        #expect(manager.isLoaded)
    }
    
    @Test("单专辑预填充 - populateWithSingleAlbum")
    func testPopulateWithSingleAlbum() throws {
        let (manager, _) = try setup()
        
        let track = AudioTrack(
            id: UUID(),
            url: URL(string: "file:///test.mp3")!,
            title: "Test Track",
            artist: nil,
            albumTitle: nil,
            duration: 180,
            format: .unknown,
            bookmark: nil
        )
        let album = Album(
            id: UUID(),
            name: "Single Album",
            folderURL: nil,
            tracks: [track]
        )
        
        manager.populateWithSingleAlbum(album)
        
        #expect(manager.albumCount == 1)
        #expect(manager.albums.first?.name == "Single Album")
        
        // 重复添加应该被忽略
        manager.populateWithSingleAlbum(album)
        #expect(manager.albumCount == 1)
    }
    
    @Test("单专辑预填充 - 已加载后忽略")
    func testPopulateWithSingleAlbumAfterLoaded() async throws {
        let (manager, _) = try setup()
        
        await manager.ensureLoaded()
        
        let track = AudioTrack(
            id: UUID(),
            url: URL(string: "file:///test.mp3")!,
            title: "Test Track",
            artist: nil,
            albumTitle: nil,
            duration: 180,
            format: .unknown,
            bookmark: nil
        )
        let album = Album(
            id: UUID(),
            name: "Should Be Ignored",
            folderURL: nil,
            tracks: [track]
        )
        
        manager.populateWithSingleAlbum(album)
        
        // 已加载后应该忽略
        #expect(manager.albumCount == 0)
    }
    
    // MARK: - 单专辑加载测试
    
    @Test("加载单专辑 - 缓存命中")
    func testLoadSingleAlbumFromCache() async throws {
        let (manager, dataService) = try setup()
        
        let album = SDAlbum.makeSample(name: "Cached Album")
        dataService.insert(album)
        try dataService.save()
        
        await manager.ensureLoaded()
        
        let loaded = await manager.loadSingleAlbum(id: album.stableId)
        #expect(loaded != nil)
        #expect(loaded?.name == "Cached Album")
    }
    
    @Test("加载单专辑 - 索引命中")
    func testLoadSingleAlbumFromIndex() async throws {
        let dataService = try createTestDataService()
        
        let album = SDAlbum.makeSample(name: "Indexed Album")
        dataService.insert(album)
        try dataService.save()
        
        // 先加载一次建立索引
        let manager1 = CollectionManager(dataService: dataService)
        await manager1.ensureLoaded()
        
        // 用新的 manager 实例（内存为空但索引已建立）
        let manager2 = CollectionManager(dataService: dataService)
        await manager2.ensureLoaded()
        
        let loaded = await manager2.loadSingleAlbum(id: album.stableId)
        #expect(loaded != nil)
        #expect(loaded?.name == "Indexed Album")
    }
    
    @Test("加载单专辑 - 数据库查询")
    func testLoadSingleAlbumFromDatabase() async throws {
        let (manager, dataService) = try setup()
        
        let album = SDAlbum.makeSample(name: "DB Album")
        dataService.insert(album)
        try dataService.save()
        
        // 不加载，直接查询
        let loaded = await manager.loadSingleAlbum(id: album.stableId)
        #expect(loaded != nil)
        #expect(loaded?.name == "DB Album")
    }
    
    @Test("加载单专辑 - 不存在")
    func testLoadSingleAlbumNotFound() async throws {
        let (manager, _) = try setup()
        
        let randomId = UUID()
        let loaded = await manager.loadSingleAlbum(id: randomId)
        #expect(loaded == nil)
    }
    
    // MARK: - 专辑添加测试
    
    @Test("从播放列表创建专辑")
    func testAddAlbumFromPlaylist() async throws {
        let (manager, dataService) = try setup()
        
        // 创建临时文件
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let file1 = tempDir.appendingPathComponent("song1.mp3")
        let file2 = tempDir.appendingPathComponent("song2.mp3")
        try "dummy".write(to: file1, atomically: true, encoding: .utf8)
        try "dummy".write(to: file2, atomically: true, encoding: .utf8)
        
        let track1 = await AudioTrack(url: file1)
        let track2 = await AudioTrack(url: file2)
        
        let albumId = await manager.addAlbumFromPlaylist(name: "Playlist Album", tracks: [track1, track2])
        
        #expect(albumId != nil)
        #expect(manager.albumCount == 1)
        #expect(manager.albums.first?.name == "Playlist Album")
        #expect(manager.albums.first?.tracks.count == 2)
        
        // 验证数据库
        let dbAlbums = try dataService.fetchAlbums()
        #expect(dbAlbums.count == 1)
        #expect(dbAlbums.first?.trackEntries.count == 2)
    }
    
    @Test("从播放列表创建专辑 - 空列表")
    func testAddAlbumFromPlaylistEmpty() async throws {
        let (manager, _) = try setup()
        
        let albumId = await manager.addAlbumFromPlaylist(name: "Empty Album", tracks: [])
        
        #expect(albumId == nil)
        #expect(manager.albumCount == 0)
    }
    
    @Test("从文件夹添加专辑")
    func testAddAlbumFromDirectory() async throws {
        let (manager, _) = try setup()
        
        // 创建测试文件夹
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let file1 = tempDir.appendingPathComponent("track1.mp3")
        let file2 = tempDir.appendingPathComponent("track2.flac")
        try "audio data".write(to: file1, atomically: true, encoding: .utf8)
        try "audio data".write(to: file2, atomically: true, encoding: .utf8)
        
        await manager.addAlbum(from: tempDir)
        
        #expect(manager.albumCount == 1)
        #expect(manager.albums.first?.folderURL?.path == tempDir.path)
    }
    
    @Test("从音频文件添加专辑")
    func testAddAlbumFromAudioFile() async throws {
        let (manager, _) = try setup()
        
        // 创建单个音频文件
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let audioFile = tempDir.appendingPathComponent("song.mp3")
        try "audio data".write(to: audioFile, atomically: true, encoding: .utf8)
        
        await manager.addAlbum(from: audioFile)
        
        #expect(manager.albumCount == 1)
        #expect(manager.albums.first?.folderURL?.path == tempDir.path)
    }
    
    @Test("递归扫描文件夹")
    func testScanAndAddAlbumsRecursive() async throws {
        let (manager, _) = try setup()
        
        // 创建嵌套文件夹结构
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let subDir1 = tempDir.appendingPathComponent("SubAlbum1", isDirectory: true)
        let subDir2 = tempDir.appendingPathComponent("SubAlbum2", isDirectory: true)
        
        try FileManager.default.createDirectory(at: subDir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subDir2, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // 根目录文件
        let rootFile = tempDir.appendingPathComponent("root.mp3")
        try "audio".write(to: rootFile, atomically: true, encoding: .utf8)
        
        // 子目录文件
        let sub1File = subDir1.appendingPathComponent("sub1.mp3")
        let sub2File = subDir2.appendingPathComponent("sub2.flac")
        try "audio".write(to: sub1File, atomically: true, encoding: .utf8)
        try "audio".write(to: sub2File, atomically: true, encoding: .utf8)
        
        await manager.addAlbum(from: tempDir)
        
        // 应该创建 3 个专辑（根目录 + 2个子目录）
        #expect(manager.albumCount == 3)
    }
    
    // MARK: - 专辑操作测试
    
    @Test("删除专辑")
    func testRemoveAlbum() async throws {
        let (manager, dataService, albums) = try setupWithAlbums(count: 3)
        
        await manager.ensureLoaded()
        #expect(manager.albumCount == 3)
        
        let albumIdToRemove = albums[1].stableId
        manager.removeAlbum(id: albumIdToRemove)
        
        #expect(manager.albumCount == 2)
        #expect(!manager.albums.contains { $0.id == albumIdToRemove })
        
        // 验证数据库
        let dbAlbums = try dataService.fetchAlbums()
        #expect(dbAlbums.count == 2)
    }
    
    @Test("删除专辑 - 不存在")
    func testRemoveAlbumNotFound() async throws {
        let (manager, _) = try setup()
        
        await manager.ensureLoaded()
        
        let randomId = UUID()
        manager.removeAlbum(id: randomId)
        
        #expect(manager.albumCount == 0)
    }
    
    @Test("重命名专辑")
    func testRenameAlbum() async throws {
        let (manager, dataService, albums) = try setupWithAlbums(count: 2)
        
        await manager.ensureLoaded()
        
        let albumId = albums[0].stableId
        manager.renameAlbum(id: albumId, newName: "Renamed Album")
        
        #expect(manager.albums.first?.name == "Renamed Album")
        
        // 验证数据库
        let dbAlbum = dataService.findAlbum(byStableId: albumId)
        #expect(dbAlbum?.name == "Renamed Album")
    }
    
    @Test("重命名专辑 - 不存在")
    func testRenameAlbumNotFound() async throws {
        let (manager, _) = try setup()
        
        await manager.ensureLoaded()
        
        let randomId = UUID()
        manager.renameAlbum(id: randomId, newName: "Should Not Crash")
        
        #expect(manager.albumCount == 0)
    }
    
    @Test("移动专辑顺序")
    func testMoveAlbum() async throws {
        let (manager, dataService, _) = try setupWithAlbums(count: 4)
        
        await manager.ensureLoaded()
        
        // 移动第 0 个到第 2 个位置
        manager.moveAlbum(from: 0, to: 2)
        
        #expect(manager.albums[0].name == "Album 1")
        #expect(manager.albums[1].name == "Album 2")
        #expect(manager.albums[2].name == "Album 0")
        #expect(manager.albums[3].name == "Album 3")
        
        // 验证数据库 displayOrder
        let dbAlbums = try dataService.fetchAlbums()
        #expect(dbAlbums[0].displayOrder == 0)
        #expect(dbAlbums[1].displayOrder == 1)
        #expect(dbAlbums[2].displayOrder == 2)
    }
    
    @Test("移动专辑 - 相同位置")
    func testMoveAlbumSamePosition() async throws {
        let (manager, _, _) = try setupWithAlbums(count: 3)
        
        await manager.ensureLoaded()
        
        let originalOrder = manager.albums.map { $0.name }
        
        manager.moveAlbum(from: 1, to: 1)
        
        let newOrder = manager.albums.map { $0.name }
        #expect(originalOrder == newOrder)
    }
    
    @Test("移动专辑 - 无效索引")
    func testMoveAlbumInvalidIndex() async throws {
        let (manager, _, _) = try setupWithAlbums(count: 2)
        
        await manager.ensureLoaded()
        
        let originalOrder = manager.albums.map { $0.name }
        
        manager.moveAlbum(from: 0, to: 10)
        
        let newOrder = manager.albums.map { $0.name }
        #expect(originalOrder == newOrder)
    }
    
    @Test("清空所有专辑")
    func testClearAllAlbums() async throws {
        let (manager, dataService, _) = try setupWithAlbums(count: 5)
        
        await manager.ensureLoaded()
        #expect(manager.albumCount == 5)
        
        manager.clearAllAlbums()
        
        #expect(manager.albumCount == 0)
        #expect(manager.albums.isEmpty)
        
        // 验证数据库
        let dbAlbums = try dataService.fetchAlbums()
        #expect(dbAlbums.isEmpty)
    }
    
    // MARK: - 文件扫描测试
    
    @Test("扫描文件夹 - 过滤音频文件")
    func testScanFolderOnlyAudioFiles() async throws {
        let (manager, _) = try setup()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // 创建混合文件
        let mp3File = tempDir.appendingPathComponent("audio.mp3")
        let flacFile = tempDir.appendingPathComponent("song.flac")
        let txtFile = tempDir.appendingPathComponent("readme.txt")
        let jpgFile = tempDir.appendingPathComponent("cover.jpg")
        
        try "audio".write(to: mp3File, atomically: true, encoding: .utf8)
        try "audio".write(to: flacFile, atomically: true, encoding: .utf8)
        try "text".write(to: txtFile, atomically: true, encoding: .utf8)
        try "image".write(to: jpgFile, atomically: true, encoding: .utf8)
        
        await manager.addAlbum(from: tempDir)
        
        #expect(manager.albumCount == 1)
        
        // 只应该包含 2 个音频文件
        let album = manager.albums.first
        #expect(album?.tracks.count == 2)
    }
    
    @Test("扫描文件夹 - 支持的音频格式")
    func testSupportedAudioFormats() async throws {
        let (manager, _) = try setup()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // 测试多种格式
        let formats = ["mp3", "m4a", "aac", "wav", "flac", "ape", "wv"]
        for format in formats {
            let file = tempDir.appendingPathComponent("track.\(format)")
            try "audio".write(to: file, atomically: true, encoding: .utf8)
        }
        
        await manager.addAlbum(from: tempDir)
        
        #expect(manager.albumCount == 1)
        #expect(manager.albums.first?.tracks.count == formats.count)
    }
    
    // MARK: - 边界条件和错误测试
    
    @Test("处理重复专辑")
    func testAddDuplicateAlbum() async throws {
        let (manager, _) = try setup()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let file = tempDir.appendingPathComponent("track.mp3")
        try "audio".write(to: file, atomically: true, encoding: .utf8)
        
        // 第一次添加
        await manager.addAlbum(from: tempDir)
        #expect(manager.albumCount == 1)
        
        // 第二次添加应该被忽略
        await manager.addAlbum(from: tempDir)
        #expect(manager.albumCount == 1)
    }
    
    @Test("并发加载轨道")
    func testConcurrentTrackLoading() async throws {
        let (manager, _) = try setup()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // 创建多个音频文件
        for i in 0..<10 {
            let file = tempDir.appendingPathComponent("track\(i).mp3")
            try "audio".write(to: file, atomically: true, encoding: .utf8)
        }
        
        await manager.addAlbum(from: tempDir)
        
        #expect(manager.albumCount == 1)
        #expect(manager.albums.first?.tracks.count == 10)
    }
    
    @Test("lastScrollAlbumId 状态管理")
    func testLastScrollAlbumIdState() async throws {
        let (manager, _) = try setup()
        
        #expect(manager.lastScrollAlbumId == nil)
        
        let testId = UUID()
        manager.lastScrollAlbumId = testId
        
        #expect(manager.lastScrollAlbumId == testId)
    }
}
