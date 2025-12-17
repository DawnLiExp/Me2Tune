//
//  AudioTrack.swift
//  Me2Tune
//
//  音频曲目模型
//

import Foundation
import SFBAudioEngine

struct AudioTrack: Identifiable, Equatable, Codable {
    let id: UUID
    let url: URL
    let title: String
    let duration: TimeInterval
    let bookmark: Data?
    
    private enum CodingKeys: String, CodingKey {
        case id, url, title, duration, bookmark
    }
    
    init(url: URL) async {
        self.id = UUID()
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
        
        self.bookmark = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        if let audioFile = try? AudioFile(readingPropertiesAndMetadataFrom: url),
           let duration = audioFile.properties.duration
        {
            self.duration = duration
        } else {
            self.duration = 0
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
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
