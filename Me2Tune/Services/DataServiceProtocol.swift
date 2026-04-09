//
//  DataServiceProtocol.swift
//  Me2Tune
//
//  数据服务协议 - 定义 SwiftData 数据访问接口
//

import Foundation
import SwiftData

@MainActor
protocol DataServiceProtocol {
    var modelContext: ModelContext { get }
    
    // MARK: - Generic CRUD
    
    func insert(_ model: some PersistentModel)
    func delete(_ model: some PersistentModel)
    func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws(AppError) -> [T]
    func fetchCount(_ descriptor: FetchDescriptor<some PersistentModel>) throws(AppError) -> Int
    func save() throws(AppError)
    
    // MARK: - Track Operations
    
    func findTrack(byURL urlString: String) -> SDTrack?
    func findTrack(byStableId id: UUID) -> SDTrack?
    func fetchPlaylistTracks() throws(AppError) -> [SDTrack]
    func playlistTrackCount() throws(AppError) -> Int
    
    // MARK: - Album Operations
    
    func fetchAlbums() throws(AppError) -> [SDAlbum]
    func findAlbum(byFolderURL urlString: String) -> SDAlbum?
    func findAlbum(byStableId id: UUID) -> SDAlbum?
    func albumCount() throws(AppError) -> Int
    
    // MARK: - Playback State Operations
    
    func fetchPlaybackStateIfExists() -> SDPlaybackState?
    func getOrCreatePlaybackState() -> SDPlaybackState
}
