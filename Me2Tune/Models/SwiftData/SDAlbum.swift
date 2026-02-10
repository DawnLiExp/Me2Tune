//
//  SDAlbum.swift
//  Me2Tune
//
//  SwiftData 专辑模型 - 通过 SDAlbumTrackEntry 支持歌曲排序
//

import Foundation
import SwiftData

@Model
final class SDAlbum {
    // MARK: - Properties

    var name: String
    var folderURLString: String?
    var displayOrder: Int

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade, inverse: \SDAlbumTrackEntry.album)
    var trackEntries: [SDAlbumTrackEntry] = []

    // MARK: - Initialization

    init(name: String, folderURLString: String?, displayOrder: Int) {
        self.name = name
        self.folderURLString = folderURLString
        self.displayOrder = displayOrder
    }

    // MARK: - Computed Properties

    /// 按 trackOrder 排序的歌曲列表
    var sortedTracks: [SDTrack] {
        trackEntries
            .sorted { $0.trackOrder < $1.trackOrder }
            .compactMap(\.track)
    }
}

// MARK: - DTO Conversion

extension SDAlbum {
    /// 转换为 Album DTO
    @MainActor
    func toAlbum() -> Album {
        let folderURL: URL? = if let folderURLString {
            URL(string: folderURLString) ?? URL(fileURLWithPath: folderURLString)
        } else {
            nil
        }
        let tracks = sortedTracks.map { $0.toAudioTrack() }
        return Album(
            id: stableUUID,
            name: name,
            folderURL: folderURL,
            tracks: tracks
        )
    }

    /// 基于 name + displayOrder 生成稳定 UUID
    private var stableUUID: UUID {
        let seed = "\(name)-\(displayOrder)"
        let hash = seed.hashValue
        return UUID(uuidString: String(abs(hash), radix: 16).padding(toLength: 32, withPad: "0", startingAt: 0)
            .enumerated().map { offset, char in
                [8, 12, 16, 20].contains(offset) ? "-\(char)" : String(char)
            }.joined()) ?? UUID()
    }
}
