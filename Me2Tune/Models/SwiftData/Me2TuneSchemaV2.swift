//
//  Me2TuneSchemaV2.swift
//  Me2Tune
//
//  SwiftData Schema V2 快照 - 移除 SDPlaybackState
//

import SwiftData

enum Me2TuneSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            SDTrack.self,
            SDAlbum.self,
            SDAlbumTrackEntry.self,
            SDStatistics.self,
        ]
    }
}
