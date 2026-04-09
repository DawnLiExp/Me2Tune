//
//  SDPlaybackState.swift
//  Me2Tune
//
//  SwiftData V1 迁移快照模型 - 仅用于历史 store 升级，不参与当前运行时读写
//

import Foundation
import SwiftData

@Model
final class SDPlaybackState {
    // MARK: - Properties

    var playlistCurrentIndex: Int?
    var albumCurrentIndex: Int?
    var playingSourceType: String?
    var playingSourceAlbumURLString: String?
    var volume: Double?

    /// 单例标记，确保数据库中只有一条记录
    @Attribute(.unique)
    var isSingleton: Bool = true

    // MARK: - Initialization

    init() {
        self.isSingleton = true
    }
}

// MARK: - Source Type Constants

extension SDPlaybackState {
    static let sourcePlaylist = "playlist"
    static let sourceAlbum = "album"
}
