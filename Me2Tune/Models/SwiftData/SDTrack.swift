//
//  SDTrack.swift
//  Me2Tune
//
//  SwiftData 歌曲模型 - 核心实体，支持 Playlist 和 Album 双归属
//

import Foundation
import SwiftData

@Model
final class SDTrack {
    // MARK: - Properties

    var title: String
    var artist: String?
    var albumTitle: String?
    var duration: TimeInterval

    @Attribute(.unique)
    var urlString: String

    var bookmark: Data?

    /// 稳定的唯一标识符，避免拖拽时频繁查询
    @Attribute(.unique)
    var stableId: UUID

    // MARK: - Audio Format (Embedded)

    var codec: String?
    var bitrate: Int?
    var sampleRate: Double?
    var bitDepth: Int?
    var channels: Int?

    // MARK: - Playlist Support

    var isInPlaylist: Bool = false
    var playlistOrder: Int?

    // MARK: - Relationships

    @Relationship(inverse: \SDAlbumTrackEntry.track)
    var albumEntries: [SDAlbumTrackEntry] = []

    // MARK: - Initialization

    init(
        title: String,
        artist: String?,
        albumTitle: String?,
        duration: TimeInterval,
        urlString: String,
        bookmark: Data?,
        codec: String?,
        bitrate: Int?,
        sampleRate: Double?,
        bitDepth: Int?,
        channels: Int?,
        stableId: UUID = UUID()
    ) {
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.duration = duration
        self.urlString = urlString
        self.bookmark = bookmark
        self.codec = codec
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channels = channels
        self.stableId = stableId
    }
}

// MARK: - DTO Conversion

extension SDTrack {
    /// 从 AudioTrack DTO 创建 SDTrack
    convenience init(from track: AudioTrack) {
        self.init(
            title: track.title,
            artist: track.artist,
            albumTitle: track.albumTitle,
            duration: track.duration,
            urlString: track.url.absoluteString,
            bookmark: track.bookmark,
            codec: track.format.codec,
            bitrate: track.format.bitrate,
            sampleRate: track.format.sampleRate,
            bitDepth: track.format.bitDepth,
            channels: track.format.channels,
            stableId: track.id // 使用 AudioTrack 的 ID
        )
    }

    /// 转换为 AudioTrack DTO
    @MainActor
    func toAudioTrack() -> AudioTrack {
        let url = URL(string: urlString) ?? URL(fileURLWithPath: urlString)
        let format = AudioFormat(
            codec: codec,
            bitrate: bitrate,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            channels: channels
        )
        return AudioTrack(
            id: stableId, // 直接使用 stableId
            url: url,
            title: title,
            artist: artist,
            albumTitle: albumTitle,
            duration: duration,
            format: format,
            bookmark: bookmark
        )
    }
}
