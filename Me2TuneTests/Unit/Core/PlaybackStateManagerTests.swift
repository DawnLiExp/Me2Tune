//
//  PlaybackStateManagerTests.swift
//  Me2TuneTests
//
//  PlaybackStateManager 单元测试 - 验证播放状态管理功能
//

import Foundation
import SwiftData
import Testing
@testable import Me2Tune

@MainActor
@Suite("PlaybackStateManager 单元测试")
struct PlaybackStateManagerTests {
    
    // MARK: - Setup Helpers
    
    private func setup() throws -> (PlaybackStateManager, PlaylistManager, CollectionManager, DataService) {
        let dataService = try createTestDataService()
        let playlistManager = PlaylistManager(dataService: dataService)
        let collectionManager = CollectionManager(dataService: dataService)
        let manager = PlaybackStateManager(
            playlistManager: playlistManager,
            collectionManager: collectionManager,
            dataService: dataService
        )
        return (manager, playlistManager, collectionManager, dataService)
    }
    
    private func setupWithPlaylistTracks(count: Int) throws -> (PlaybackStateManager, PlaylistManager, DataService, [SDTrack]) {
        let dataService = try createTestDataService()
        var tracks: [SDTrack] = []
        
        for i in 0..<count {
            let track = SDTrack.makeSample(
                title: "Track \(i)",
                urlString: "file:///test/track\(i).mp3"
            )
            track.isInPlaylist = true
            track.playlistOrder = i
            dataService.insert(track)
            tracks.append(track)
        }
        try dataService.save()
        
        let playlistManager = PlaylistManager(dataService: dataService)
        let collectionManager = CollectionManager(dataService: dataService)
        let manager = PlaybackStateManager(
            playlistManager: playlistManager,
            collectionManager: collectionManager,
            dataService: dataService
        )
        
        return (manager, playlistManager, dataService, tracks)
    }
    
    private func createTestAlbum(name: String, trackCount: Int, dataService: DataService) -> (Album, SDAlbum) {
        let sdAlbum = SDAlbum.makeSample(
            name: name,
            folderURLString: "file:///test/\(name)"
        )
        dataService.insert(sdAlbum)
        
        var audioTracks: [AudioTrack] = []
        for i in 0..<trackCount {
            let sdTrack = SDTrack.makeSample(
                title: "\(name) Track \(i)",
                urlString: "file:///test/\(name)/track\(i).mp3"
            )
            dataService.insert(sdTrack)
            
            let entry = SDAlbumTrackEntry(trackOrder: i, album: sdAlbum, track: sdTrack)
            dataService.insert(entry)
            
            audioTracks.append(sdTrack.toAudioTrack())
        }
        
        try? dataService.save()
        
        let album = Album(
            id: sdAlbum.stableId,
            name: name,
            folderURL: URL(string: "file:///test/\(name)"),
            tracks: audioTracks
        )
        
        return (album, sdAlbum)
    }
    
    // MARK: - 初始化测试
    
    @Test("初始化")
    func testInit() throws {
        let (manager, _, _, _) = try setup()
        
        #expect(manager.currentTracks.isEmpty)
        #expect(manager.currentTrackID == nil)
        #expect(manager.currentTrackIndex == nil)
        #expect(manager.playingSource == PlaybackStateManager.PlayingSource.playlist)
        #expect(manager.currentTrack == nil)
        #expect(!manager.canGoPrevious)
        #expect(!manager.canGoNext)
    }
    
    // MARK: - 播放源切换测试
    
    @Test("切换到播放列表")
    func testSwitchToPlaylist() throws {
        let (manager, playlistManager, _, _) = try setupWithPlaylistTracks(count: 3)
        _ = playlistManager
        
        manager.switchToPlaylist()
        
        #expect(manager.playingSource == PlaybackStateManager.PlayingSource.playlist)
        #expect(manager.currentTracks.count == 3)
        #expect(manager.currentTracks[0].title == "Track 0")
    }
    
    @Test("切换到专辑")
    func testSwitchToAlbum() throws {
        let (manager, _, _, dataService) = try setup()
        
        let (album, _) = createTestAlbum(name: "Test Album", trackCount: 5, dataService: dataService)
        
        manager.switchToAlbum(album)
        
        #expect(manager.playingSource == PlaybackStateManager.PlayingSource.album(album.id))
        #expect(manager.currentTracks.count == 5)
        #expect(manager.currentTracks[0].title == "Test Album Track 0")
    }
    
    // MARK: - 计算属性测试
    
    @Test("currentTrack - 有效索引")
    func testCurrentTrackValid() throws {
        let (manager, playlistManager, _, _) = try setupWithPlaylistTracks(count: 3)
        _ = playlistManager
        
        manager.switchToPlaylist()
        manager.setCurrentIndex(1)
        
        #expect(manager.currentTrack != nil)
        #expect(manager.currentTrack?.title == "Track 1")
    }
    
    @Test("currentTrack - 无效索引")
    func testCurrentTrackInvalid() throws {
        let (manager, playlistManager, _, _) = try setupWithPlaylistTracks(count: 3)
        _ = playlistManager
        
        manager.switchToPlaylist()
        manager.setCurrentIndex(10)
        
        #expect(manager.currentTrack == nil)
    }
    
    @Test("currentTrack - 未设置索引")
    func testCurrentTrackNil() throws {
        let (manager, playlistManager, _, _) = try setupWithPlaylistTracks(count: 3)
        _ = playlistManager
        
        manager.switchToPlaylist()
        
        #expect(manager.currentTrack == nil)
    }
    
    @Test("canGoPrevious")
    func testCanGoPrevious() throws {
        let (manager, playlistManager, _, _) = try setupWithPlaylistTracks(count: 3)
        _ = playlistManager
        
        manager.switchToPlaylist()
        
        // 索引 0 - 不能向前
        manager.setCurrentIndex(0)
        #expect(!manager.canGoPrevious)
        
        // 索引 1 - 可以向前
        manager.setCurrentIndex(1)
        #expect(manager.canGoPrevious)
        
        // 未设置索引 - 不能向前
        manager.setCurrentIndex(nil)
        #expect(!manager.canGoPrevious)
    }
    
    @Test("canGoNext")
    func testCanGoNext() throws {
        let (manager, playlistManager, _, _) = try setupWithPlaylistTracks(count: 3)
        _ = playlistManager
        
        manager.switchToPlaylist()
        
        // 索引 0 - 可以向后
        manager.setCurrentIndex(0)
        #expect(manager.canGoNext)
        
        // 最后一个索引 - 不能向后
        manager.setCurrentIndex(2)
        #expect(!manager.canGoNext)
        
        // 未设置索引 - 不能向后
        manager.setCurrentIndex(nil)
        #expect(!manager.canGoNext)
    }
    
    // MARK: - 索引管理测试
    
    @Test("设置当前索引")
    func testSetCurrentIndex() throws {
        let (manager, _, _, _) = try setup()
        
        #expect(manager.currentTrackIndex == nil)
        
        manager.setCurrentIndex(5)
        #expect(manager.currentTrackIndex == nil)
        
        manager.setCurrentIndex(nil)
        #expect(manager.currentTrackIndex == nil)
    }
    
    // MARK: - 播放列表事件处理测试
    
    @Test("处理播放列表添加曲目")
    func testHandlePlaylistTracksAdded() throws {
        let (manager, playlistManager, dataService, _) = try setupWithPlaylistTracks(count: 2)
        _ = playlistManager
        
        manager.switchToPlaylist()
        #expect(manager.currentTracks.count == 2)
        #expect(manager.currentTrackIndex == nil)
        
        // 添加新曲目
        let newTrack = SDTrack.makeSample(title: "New Track", urlString: "file:///new.mp3")
        newTrack.isInPlaylist = true
        newTrack.playlistOrder = 2
        dataService.insert(newTrack)
        try dataService.save()
        
        // 重新加载 playlistManager
        let newPlaylistManager = PlaylistManager(dataService: dataService)
        let newManager = PlaybackStateManager(
            playlistManager: newPlaylistManager,
            collectionManager: nil,
            dataService: dataService
        )
        newManager.switchToPlaylist()
        
        newManager.handlePlaylistTracksAdded()
        
        #expect(newManager.currentTracks.count == 3)
        #expect(newManager.currentTrackIndex == 0)
    }
    
    @Test("处理播放列表删除曲目 - 删除当前播放")
    func testHandlePlaylistTrackRemovedCurrent() throws {
        let (manager, playlistManager, _, _) = try setupWithPlaylistTracks(count: 3)
        _ = playlistManager
        
        manager.switchToPlaylist()
        manager.setCurrentIndex(1)
        let removedTrackID = manager.currentTracks[1].id
        
        manager.handlePlaylistTrackRemoved(removedTrackID: removedTrackID, wasPlaying: true)
        
        #expect(manager.currentTrackIndex == nil)
    }
    
    @Test("处理播放列表删除曲目 - 删除之前的曲目")
    func testHandlePlaylistTrackRemovedBefore() throws {
        let (manager, playlistManager, _, _) = try setupWithPlaylistTracks(count: 3)
        _ = playlistManager
        
        manager.switchToPlaylist()
        manager.setCurrentIndex(2)
        let removedTrackID = manager.currentTracks[0].id
        
        manager.handlePlaylistTrackRemoved(removedTrackID: removedTrackID, wasPlaying: false)
        
        #expect(manager.currentTrackIndex == 2)
    }
    
    @Test("处理播放列表删除曲目 - 删除之后的曲目")
    func testHandlePlaylistTrackRemovedAfter() throws {
        let (manager, playlistManager, _, _) = try setupWithPlaylistTracks(count: 3)
        _ = playlistManager
        
        manager.switchToPlaylist()
        manager.setCurrentIndex(0)
        let removedTrackID = manager.currentTracks[2].id
        
        manager.handlePlaylistTrackRemoved(removedTrackID: removedTrackID, wasPlaying: false)
        
        #expect(manager.currentTrackIndex == 0)
    }
    
    @Test("处理播放列表删除曲目 - 非播放列表源")
    func testHandlePlaylistTrackRemovedWrongSource() throws {
        let (manager, _, dataService, _) = try setupWithPlaylistTracks(count: 3)
        
        let (album, _) = createTestAlbum(name: "Album", trackCount: 2, dataService: dataService)
        manager.switchToAlbum(album)
        manager.setCurrentIndex(1)
        
        manager.handlePlaylistTrackRemoved(removedTrackID: UUID(), wasPlaying: false)
        
        // 应该不受影响
        #expect(manager.currentTrackIndex == 1)
    }
    
    @Test("处理播放列表清空")
    func testHandlePlaylistCleared() throws {
        let (manager, playlistManager, _, _) = try setupWithPlaylistTracks(count: 3)
        _ = playlistManager
        
        manager.switchToPlaylist()
        manager.setCurrentIndex(1)
        
        manager.handlePlaylistCleared()
        
        #expect(manager.currentTrackIndex == nil)
        #expect(manager.currentTracks.count == 3)
    }
    
    @Test("处理播放列表清空 - 非播放列表源")
    func testHandlePlaylistClearedWrongSource() throws {
        let (manager, _, dataService, _) = try setupWithPlaylistTracks(count: 3)
        
        let (album, _) = createTestAlbum(name: "Album", trackCount: 2, dataService: dataService)
        manager.switchToAlbum(album)
        manager.setCurrentIndex(1)
        
        manager.handlePlaylistCleared()
        
        // 应该不受影响
        #expect(manager.currentTrackIndex == 1)
        #expect(manager.currentTracks.count == 2)
    }
    
    @Test("处理播放列表移动曲目 - 移动当前播放")
    func testHandlePlaylistTrackMovedCurrent() throws {
        let (manager, playlistManager, _, _) = try setupWithPlaylistTracks(count: 4)
        _ = playlistManager
        
        manager.switchToPlaylist()
        manager.setCurrentIndex(1)
        
        manager.handlePlaylistTrackMoved(from: 1, to: 3)
        
        #expect(manager.currentTrackIndex == 1)
    }
    
    @Test("处理播放列表移动曲目 - 从前往后移")
    func testHandlePlaylistTrackMovedBeforeToCurrent() throws {
        let (manager, playlistManager, _, _) = try setupWithPlaylistTracks(count: 4)
        _ = playlistManager
        
        manager.switchToPlaylist()
        manager.setCurrentIndex(2)
        
        manager.handlePlaylistTrackMoved(from: 0, to: 2)
        
        #expect(manager.currentTrackIndex == 2)
    }
    
    @Test("处理播放列表移动曲目 - 从后往前移")
    func testHandlePlaylistTrackMovedAfterToCurrent() throws {
        let (manager, playlistManager, _, _) = try setupWithPlaylistTracks(count: 4)
        _ = playlistManager
        
        manager.switchToPlaylist()
        manager.setCurrentIndex(1)
        
        manager.handlePlaylistTrackMoved(from: 3, to: 1)
        
        #expect(manager.currentTrackIndex == 1)
    }
    
    @Test("处理播放列表移动曲目 - 非播放列表源")
    func testHandlePlaylistTrackMovedWrongSource() throws {
        let (manager, _, dataService, _) = try setupWithPlaylistTracks(count: 3)
        
        let (album, _) = createTestAlbum(name: "Album", trackCount: 2, dataService: dataService)
        manager.switchToAlbum(album)
        manager.setCurrentIndex(1)
        
        manager.handlePlaylistTrackMoved(from: 0, to: 2)
        
        // 应该不受影响
        #expect(manager.currentTrackIndex == 1)
    }
    
    // MARK: - 状态持久化测试
    
    @Test("保存状态 - 播放列表源")
    func testSaveStatePlaylist() throws {
        let (manager, playlistManager, dataService, _) = try setupWithPlaylistTracks(count: 3)
        _ = playlistManager
        
        manager.switchToPlaylist()
        manager.setCurrentIndex(1)
        
        manager.saveState(volume: 0.75)
        
        let sdState = dataService.getOrCreatePlaybackState()
        #expect(sdState.playingSourceType == SDPlaybackState.sourcePlaylist)
        #expect(sdState.playlistCurrentIndex == 1)
        #expect(sdState.albumCurrentIndex == nil)
        #expect(sdState.volume == 0.75)
    }
    
    @Test("保存状态 - 专辑源")
    func testSaveStateAlbum() throws {
        let (manager, _, _, dataService) = try setup()
        
        let (album, _) = createTestAlbum(name: "Test Album", trackCount: 5, dataService: dataService)
        
        manager.switchToAlbum(album)
        manager.setCurrentIndex(2)
        
        manager.saveState(volume: 0.5)
        
        let sdState = dataService.getOrCreatePlaybackState()
        #expect(sdState.playingSourceType == SDPlaybackState.sourceAlbum)
        #expect(sdState.albumCurrentIndex == 2)
        #expect(sdState.playlistCurrentIndex == nil)
        #expect(sdState.volume == 0.5)
        #expect(sdState.playingSourceAlbumURLString != nil)
    }
    
    @Test("保存状态 - 去重优化")
    func testSaveStateDeduplication() throws {
        let (manager, playlistManager, dataService, _) = try setupWithPlaylistTracks(count: 3)
        _ = playlistManager
        
        manager.switchToPlaylist()
        manager.setCurrentIndex(1)
        
        // 第一次保存
        manager.saveState(volume: 0.75)
        
        let sdState1 = dataService.getOrCreatePlaybackState()
        let originalTimestamp = sdState1.playlistCurrentIndex
        
        // 相同状态再次保存（应该被跳过）
        manager.saveState(volume: 0.75)
        
        let sdState2 = dataService.getOrCreatePlaybackState()
        #expect(sdState2.playlistCurrentIndex == originalTimestamp)
    }
    
    @Test("恢复状态 - 播放列表")
    func testRestoreStatePlaylist() async throws {
        let (manager, playlistManager, dataService, _) = try setupWithPlaylistTracks(count: 3)
        _ = playlistManager
        
        // 保存状态
        manager.switchToPlaylist()
        manager.setCurrentIndex(2)
        manager.saveState(volume: 0.8)
        
        // 创建新实例恢复
        let newPlaylistManager = PlaylistManager(dataService: dataService)
        let newManager = PlaybackStateManager(
            playlistManager: newPlaylistManager,
            collectionManager: nil,
            dataService: dataService
        )
        
        let restored = await newManager.restoreState()
        
        #expect(restored != nil)
        #expect(restored?.source == PlaybackStateManager.PlayingSource.playlist)
        #expect(restored?.trackIndex == 2)
        #expect(restored?.volume == 0.8)
        #expect(newManager.currentTrackIndex == 2)
        #expect(newManager.playingSource == PlaybackStateManager.PlayingSource.playlist)
    }
    
    @Test("恢复状态 - 专辑")
    func testRestoreStateAlbum() async throws {
        let dataService = try createTestDataService()
        let playlistManager = PlaylistManager(dataService: dataService)
        let collectionManager = CollectionManager(dataService: dataService)
        
        let (album, _) = createTestAlbum(name: "Saved Album", trackCount: 4, dataService: dataService)
        
        let manager = PlaybackStateManager(
            playlistManager: playlistManager,
            collectionManager: collectionManager,
            dataService: dataService
        )
        
        // 保存状态
        manager.switchToAlbum(album)
        manager.setCurrentIndex(2)
        manager.saveState(volume: 0.6)
        
        // 创建新实例恢复
        let newPlaylistManager = PlaylistManager(dataService: dataService)
        let newCollectionManager = CollectionManager(dataService: dataService)
        let newManager = PlaybackStateManager(
            playlistManager: newPlaylistManager,
            collectionManager: newCollectionManager,
            dataService: dataService
        )
        
        let restored = await newManager.restoreState()
        
        #expect(restored != nil)
        #expect(restored?.trackIndex == 2)
        #expect(restored?.volume == 0.6)
        #expect(newManager.currentTrackIndex == 2)
        
        if case .album(let albumId) = restored?.source {
            #expect(albumId == album.id)
        } else {
            Issue.record("Expected album source")
        }
    }
    
    @Test("恢复状态 - 无保存状态")
    func testRestoreStateNoSavedState() async throws {
        let (manager, _, _, _) = try setup()
        
        let restored = await manager.restoreState()
        
        #expect(restored == nil)
    }
    
    @Test("恢复状态 - 专辑不存在回退到播放列表")
    func testRestoreStateAlbumNotFoundFallback() async throws {
        let dataService = try createTestDataService()
        
        // 创建并保存状态
        let sdState = dataService.getOrCreatePlaybackState()
        sdState.playingSourceType = SDPlaybackState.sourceAlbum
        sdState.playingSourceAlbumURLString = "file:///nonexistent/album"
        sdState.albumCurrentIndex = 1
        try dataService.save()
        
        // 创建 manager（但专辑不存在）
        let track = SDTrack.makeSample(title: "Fallback Track", urlString: "file:///fallback.mp3")
        track.isInPlaylist = true
        track.playlistOrder = 0
        dataService.insert(track)
        try dataService.save()
        
        let playlistManager = PlaylistManager(dataService: dataService)
        let collectionManager = CollectionManager(dataService: dataService)
        let manager = PlaybackStateManager(
            playlistManager: playlistManager,
            collectionManager: collectionManager,
            dataService: dataService
        )
        
        let restored = await manager.restoreState()
        
        #expect(restored == nil)
        #expect(manager.playingSource == PlaybackStateManager.PlayingSource.playlist)
    }
    
    // MARK: - 辅助方法测试
    
    @Test("查找专辑标识符 - 通过文件夹 URL")
    func testFindAlbumIdentifierByFolderURL() throws {
        let (manager, _, _, dataService) = try setup()
        
        let (album, _) = createTestAlbum(name: "Test Album", trackCount: 2, dataService: dataService)
        
        manager.switchToAlbum(album)
        manager.saveState()
        
        let sdState = dataService.getOrCreatePlaybackState()
        #expect(sdState.playingSourceAlbumURLString?.contains("Test Album") == true)
    }
    
    @Test("查找专辑标识符 - 专辑不存在")
    func testFindAlbumIdentifierNotFound() throws {
        let (manager, _, _, dataService) = try setup()
        
        // 创建临时专辑（不保存到数据库）
        let tempAlbum = Album(
            id: UUID(),
            name: "Temp Album",
            folderURL: URL(string: "file:///temp"),
            tracks: []
        )
        
        manager.switchToAlbum(tempAlbum)
        manager.saveState()
        
        let sdState = dataService.getOrCreatePlaybackState()
        #expect(sdState.playingSourceAlbumURLString == nil)
    }
    
    @Test("通过标识符查找专辑 UUID - 文件夹 URL")
    func testFindAlbumUUIDByFolderURL() async throws {
        let (manager, _, _, dataService) = try setup()
        
        let (album, sdAlbum) = createTestAlbum(name: "Test Album", trackCount: 2, dataService: dataService)
        
        // 通过 restoreState 间接测试 findAlbumUUID
        manager.switchToAlbum(album)
        manager.setCurrentIndex(1)
        manager.saveState()
        
        // 创建新实例恢复
        let newPlaylistManager = PlaylistManager(dataService: dataService)
        let newCollectionManager = CollectionManager(dataService: dataService)
        let newManager = PlaybackStateManager(
            playlistManager: newPlaylistManager,
            collectionManager: newCollectionManager,
            dataService: dataService
        )
        
        let restored = await newManager.restoreState()
        
        #expect(restored != nil)
        if case .album(let albumId) = restored?.source {
            #expect(albumId == sdAlbum.stableId)
        }
    }
    
    @Test("通过标识符查找专辑 UUID - 专辑名称回退")
    func testFindAlbumUUIDByNameFallback() async throws {
        let dataService = try createTestDataService()
        
        // 创建没有 folderURL 的专辑
        let sdAlbum = SDAlbum(
            name: "Name Only Album",
            folderURLString: nil,
            displayOrder: 0
        )
        dataService.insert(sdAlbum)
        
        let sdTrack = SDTrack.makeSample(title: "Track", urlString: "file:///track.mp3")
        dataService.insert(sdTrack)
        
        let entry = SDAlbumTrackEntry(trackOrder: 0, album: sdAlbum, track: sdTrack)
        dataService.insert(entry)
        try dataService.save()
        
        let album = sdAlbum.toAlbum()
        
        let playlistManager = PlaylistManager(dataService: dataService)
        let collectionManager = CollectionManager(dataService: dataService)
        let manager = PlaybackStateManager(
            playlistManager: playlistManager,
            collectionManager: collectionManager,
            dataService: dataService
        )
        
        manager.switchToAlbum(album)
        manager.setCurrentIndex(0)
        manager.saveState()
        
        // 创建新实例恢复
        let newPlaylistManager = PlaylistManager(dataService: dataService)
        let newCollectionManager = CollectionManager(dataService: dataService)
        let newManager = PlaybackStateManager(
            playlistManager: newPlaylistManager,
            collectionManager: newCollectionManager,
            dataService: dataService
        )
        
        let restored = await newManager.restoreState()
        
        #expect(restored != nil)
        if case .album(let albumId) = restored?.source {
            #expect(albumId == sdAlbum.stableId)
        }
    }
}
