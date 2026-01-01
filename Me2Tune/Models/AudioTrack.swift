//
//  AudioTrack.swift
//  Me2Tune
//
//  音频曲目模型 + 格式信息
//

import Foundation
import OSLog
import SFBAudioEngine

private let logger = Logger.audio

// MARK: - Audio Format

struct AudioFormat: Codable, Sendable {
    let codec: String?
    let bitrate: Int?
    let sampleRate: Double?
    let bitDepth: Int?
    let channels: Int?
    
    var formattedString: String {
        var components: [String] = []
        
        if let codec {
            components.append(codec.uppercased())
        }
        
        if let bitrate, bitrate > 0 {
            components.append("\(bitrate) kbps")
        }
        
        if let bitDepth, bitDepth > 0 {
            components.append("\(bitDepth) bit")
        }
        
        if let sampleRate, sampleRate > 0 {
            let khz = sampleRate / 1000.0
            components.append(String(format: "%.1f kHz", khz))
        }
        
        if let channels, channels > 0 {
            let channelName = channels == 1 ? "Mono" : (channels == 2 ? "Stereo" : "\(channels)ch")
            components.append(channelName)
        }
        
        return components.isEmpty ? "Unknown Format" : components.joined(separator: " | ")
    }
    
    static let unknown = AudioFormat(
        codec: nil,
        bitrate: nil,
        sampleRate: nil,
        bitDepth: nil,
        channels: nil
    )
}

// MARK: - Audio Track

struct AudioTrack: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let url: URL
    let title: String
    let artist: String?
    let albumTitle: String?
    let duration: TimeInterval
    let format: AudioFormat
    let bookmark: Data?
    
    private enum CodingKeys: String, CodingKey {
        case id, url, title, artist, albumTitle, duration, format, bookmark
    }
    
    init(url: URL) async {
        self.id = UUID()
        self.url = url
        
        self.bookmark = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        // 提取元数据和格式信息
        if let audioFile = try? AudioFile(readingPropertiesAndMetadataFrom: url) {
            let metadata = audioFile.metadata
            let properties = audioFile.properties
            
            // 标题
            let metadataTitle = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.title = (metadataTitle?.isEmpty == false) ? metadataTitle! : url.deletingPathExtension().lastPathComponent
            
            // 艺术家
            let metadataArtist = metadata.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.artist = (metadataArtist?.isEmpty == false) ? metadataArtist : nil
            
            self.albumTitle = metadata.albumTitle
            self.duration = properties.duration ?? 0
            
            // 提取音频格式信息
            let codec = properties.formatName
            let bitrate = estimateBitrate(url: url, duration: properties.duration ?? 0)
            let sampleRate = properties.sampleRate
            let channels = properties.channelCount.map(Int.init)
            
            self.format = AudioFormat(
                codec: codec,
                bitrate: bitrate,
                sampleRate: sampleRate,
                bitDepth: nil,
                channels: channels
            )
            
            let trackTitle = self.title
            let trackArtist = self.artist ?? "Unknown"
            logger.debug("Loaded track: \(trackTitle) - \(trackArtist)")
        } else {
            // 降级处理
            self.title = url.deletingPathExtension().lastPathComponent
            self.artist = nil
            self.albumTitle = nil
            self.duration = 0
            self.format = .unknown
            
            let filename = url.lastPathComponent
            logger.warning("Failed to read metadata for: \(filename)")
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        albumTitle = try container.decodeIfPresent(String.self, forKey: .albumTitle)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        format = try container.decodeIfPresent(AudioFormat.self, forKey: .format) ?? .unknown
        bookmark = try container.decodeIfPresent(Data.self, forKey: .bookmark)
    }
    
    // MARK: - Internal Initializer (for testing/preview)

    init(
        id: UUID,
        url: URL,
        title: String,
        artist: String?,
        albumTitle: String?,
        duration: TimeInterval,
        format: AudioFormat,
        bookmark: Data?
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.duration = duration
        self.format = format
        self.bookmark = bookmark
    }

    func resolveURL() -> URL? {
        guard let bookmark else { return url }
        
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        
        return resolved
    }
    
    static func == (lhs: AudioTrack, rhs: AudioTrack) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Format Extraction Helpers

private func estimateBitrate(url: URL, duration: TimeInterval) -> Int? {
    guard duration > 0 else { return nil }
    
    guard let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 else {
        return nil
    }
    
    // bitrate (kbps) = 文件大小 (bytes) * 8 / 时长 (seconds) / 1000
    let bitrateKbps = Int(Double(fileSize) * 8 / duration / 1000)
    return bitrateKbps > 0 ? bitrateKbps : nil
}
