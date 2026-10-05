//
//  DetailedAudioMetadata.swift
//  Me2Tune
//
//  音频文件详细元数据与标签模型 - 支持读写与界面编辑
//

import Foundation
import CoreGraphics

public struct DetailedAudioMetadata: Sendable, Equatable {
    // MARK: - File & Audio Properties (Read-only)
    
    public let fileURL: URL
    public let fileSize: Int64
    public let fileFormatName: String
    public let duration: TimeInterval
    public let sampleRate: Double?
    public let bitDepth: Int?
    public let channels: Int?
    public let bitrate: Int?
    
    // MARK: - Editable Metadata Tags
    
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String
    public var composer: String
    public var genre: String
    public var year: String
    public var trackNumber: Int?
    public var trackTotal: Int?
    public var discNumber: Int?
    public var discTotal: Int?
    public var bpm: Int?
    public var comment: String
    public var compilation: Bool
    
    // MARK: - Embedded Lyrics
    
    public var lyrics: String
    
    // MARK: - Embedded Artwork
    
    public var artworkData: Data?
    public var artworkMIMEType: String?
    public var artworkDimensions: CGSize?
    public var isArtworkModified: Bool
    
    public nonisolated init(
        fileURL: URL,
        fileSize: Int64 = 0,
        fileFormatName: String = "",
        duration: TimeInterval = 0,
        sampleRate: Double? = nil,
        bitDepth: Int? = nil,
        channels: Int? = nil,
        bitrate: Int? = nil,
        title: String = "",
        artist: String = "",
        album: String = "",
        albumArtist: String = "",
        composer: String = "",
        genre: String = "",
        year: String = "",
        trackNumber: Int? = nil,
        trackTotal: Int? = nil,
        discNumber: Int? = nil,
        discTotal: Int? = nil,
        bpm: Int? = nil,
        comment: String = "",
        compilation: Bool = false,
        lyrics: String = "",
        artworkData: Data? = nil,
        artworkMIMEType: String? = nil,
        artworkDimensions: CGSize? = nil,
        isArtworkModified: Bool = false
    ) {
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.fileFormatName = fileFormatName
        self.duration = duration
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channels = channels
        self.bitrate = bitrate
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.composer = composer
        self.genre = genre
        self.year = year
        self.trackNumber = trackNumber
        self.trackTotal = trackTotal
        self.discNumber = discNumber
        self.discTotal = discTotal
        self.bpm = bpm
        self.comment = comment
        self.compilation = compilation
        self.lyrics = lyrics
        self.artworkData = artworkData
        self.artworkMIMEType = artworkMIMEType
        self.artworkDimensions = artworkDimensions
        self.isArtworkModified = isArtworkModified
    }
}
