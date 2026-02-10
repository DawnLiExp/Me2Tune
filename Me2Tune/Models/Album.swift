//
//  Album.swift
//  Me2Tune
//
//  专辑模型 - DTO，用于视图层数据传递
//

import Foundation

struct Album: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    let folderURL: URL?
    var tracks: [AudioTrack]

    init(name: String, folderURL: URL, tracks: [AudioTrack]) {
        self.id = UUID()
        self.name = name
        self.folderURL = folderURL
        self.tracks = tracks
    }

    /// 支持指定 ID 的初始化（用于 SwiftData DTO 转换）
    init(id: UUID, name: String, folderURL: URL?, tracks: [AudioTrack]) {
        self.id = id
        self.name = name
        self.folderURL = folderURL
        self.tracks = tracks
    }
}
