//
//  Album.swift
//  Me2Tune
//
//  专辑模型
//

import Foundation

struct Album: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var name: String
    let folderURL: URL
    var tracks: [AudioTrack]

    init(name: String, folderURL: URL, tracks: [AudioTrack]) {
        self.id = UUID()
        self.name = name
        self.folderURL = folderURL
        self.tracks = tracks
    }
}
