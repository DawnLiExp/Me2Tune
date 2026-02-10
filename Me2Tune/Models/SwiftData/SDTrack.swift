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
        channels: Int?
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
            channels: track.format.channels
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
            id: persistentModelID.hashValue != 0 ? stableUUID : UUID(),
            url: url,
            title: title,
            artist: artist,
            albumTitle: albumTitle,
            duration: duration,
            format: format,
            bookmark: bookmark
        )
    }

    /// 基于 urlString 生成稳定的 UUID（确保同一 SDTrack 每次转出的 UUID 一致）
    private var stableUUID: UUID {
        UUID(uuidString: String(urlString.hashValue, radix: 16).padding(toLength: 32, withPad: "0", startingAt: 0)
            .enumerated().map { offset, char in
                [8, 12, 16, 20].contains(offset) ? "-\(char)" : String(char)
            }.joined()) ?? UUID()
    }
}
