//
//  SDAlbumTrackEntry.swift
//  Me2Tune
//
//  Album-Track 中间模型 - 支持专辑内歌曲排序 + 多专辑归属
//

import Foundation
import SwiftData

@Model
final class SDAlbumTrackEntry {
    // MARK: - Properties

    var trackOrder: Int

    // MARK: - Relationships

    var album: SDAlbum?
    var track: SDTrack?

    // MARK: - Initialization

    init(trackOrder: Int, album: SDAlbum? = nil, track: SDTrack? = nil) {
        self.trackOrder = trackOrder
        self.album = album
        self.track = track
    }
}
