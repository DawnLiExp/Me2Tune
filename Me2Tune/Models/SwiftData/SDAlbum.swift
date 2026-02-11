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

    @Attribute(.unique)
    var stableId: UUID

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade, inverse: \SDAlbumTrackEntry.album)
    var trackEntries: [SDAlbumTrackEntry] = []

    // MARK: - Initialization

    init(name: String, folderURLString: String?, displayOrder: Int, stableId: UUID = UUID()) {
        self.name = name
        self.folderURLString = folderURLString
        self.displayOrder = displayOrder
        self.stableId = stableId
    }

    // MARK: - Computed Properties

    var sortedTracks: [SDTrack] {
        trackEntries
            .sorted { $0.trackOrder < $1.trackOrder }
            .compactMap(\.track)
    }
}

// MARK: - DTO Conversion

extension SDAlbum {
    @MainActor
    func toAlbum() -> Album {
        let folderURL: URL? = if let folderURLString {
            URL(string: folderURLString) ?? URL(fileURLWithPath: folderURLString)
        } else {
            nil
        }
        let tracks = sortedTracks.map { $0.toAudioTrack() }
        return Album(
            id: stableId,
            name: name,
            folderURL: folderURL,
            tracks: tracks
        )
    }
}
