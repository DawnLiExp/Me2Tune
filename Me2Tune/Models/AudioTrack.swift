//
//  AudioTrack.swift
//  Me2Tune
//
//  音频曲目模型
//

import Foundation
import SFBAudioEngine
import OSLog

private let logger = Logger(subsystem: "com.me2tune.app", category: "AudioTrack")

struct AudioTrack: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let url: URL
    let title: String
    let artist: String?
    let albumTitle: String?
    let duration: TimeInterval
    let bookmark: Data?
    
    private enum CodingKeys: String, CodingKey {
        case id, url, title, artist, albumTitle, duration, bookmark
    }
    
    init(url: URL) async {
        self.id = UUID()
        self.url = url
        
        self.bookmark = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        // 提取元数据
        if let audioFile = try? AudioFile(readingPropertiesAndMetadataFrom: url) {
            let metadata = audioFile.metadata
            
            // 优先使用元数据标题，否则使用文件名
            let metadataTitle = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.title = (metadataTitle?.isEmpty == false) ? metadataTitle! : url.deletingPathExtension().lastPathComponent
            
            // 艺术家信息，保留nil以便UI层显示本地化的"未知艺术家"
            let metadataArtist = metadata.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.artist = (metadataArtist?.isEmpty == false) ? metadataArtist : nil
            
            self.albumTitle = metadata.albumTitle
            self.duration = audioFile.properties.duration ?? 0
            
            let trackTitle = self.title
            let trackArtist = self.artist ?? "Unknown"
            logger.debug("Loaded track: \(trackTitle) - \(trackArtist)")
        } else {
            // 降级处理：无法读取元数据时使用文件名
            self.title = url.deletingPathExtension().lastPathComponent
            self.artist = nil
            self.albumTitle = nil
            self.duration = 0
            
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
        bookmark = try container.decodeIfPresent(Data.self, forKey: .bookmark)
    }
    
    func resolveURL() -> URL? {
        guard let bookmark = bookmark else { return url }
        
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
