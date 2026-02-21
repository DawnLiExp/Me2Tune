//
//  Me2TuneSchemaV1.swift
//  Me2Tune
//
//  SwiftData Schema V1 快照 - 对应开源发布初始版本
//

import SwiftData

enum Me2TuneSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0) // var → let
    static var models: [any PersistentModel.Type] {
        [
            SDTrack.self,
            SDAlbum.self,
            SDAlbumTrackEntry.self,
            SDPlaybackState.self,
            SDStatistics.self,
        ]
    }
}
