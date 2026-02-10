//
//  SDPlaybackState.swift
//  Me2Tune
//
//  SwiftData 播放状态模型 - 单例记录，持久化当前播放位置和音量
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
