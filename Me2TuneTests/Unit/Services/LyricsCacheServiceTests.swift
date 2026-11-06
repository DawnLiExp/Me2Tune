import CryptoKit
import Foundation
import Testing
@testable import Me2Tune

@Suite("Isolated lyrics cache reads")
@MainActor
struct LyricsCacheServiceTests {
    @Test("A hit preserves lyrics and metadata, and persists only the first matching access time",
          arguments: ["[00:01.00] 第一行\n[00:02.00] Second line", "第一行\nSecond line"])
    func hitPersistsAccessTime(_ text: String) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("track.mp3")
        let target = entry(for: url, name: "target")
        let original = LyricsCacheService.CacheMetadata(version: 1, entries: [
            entry(for: root.appendingPathComponent("other.mp3"), name: "other"),
            target, entry(for: url, name: "duplicate")
        ])
        let metadataURL = root.appendingPathComponent("cache_metadata.json")
        try encoded(original).write(to: metadataURL)
        try text.write(to: root.appendingPathComponent("target.lrc"), atomically: true, encoding: .utf8)
        let cache = LyricsCacheService(cacheDirectory: root)
        let before = Date()
        let lyrics = try #require(await cache.getCachedLyrics(audioURL: url))
        let after = Date()
        #expect(lyrics.trackName == target.trackName && lyrics.artistName == target.artistName)
        #expect(lyrics.albumName == nil && lyrics.duration == 0 && !lyrics.instrumental)
        if text.hasPrefix("[00:") {
            #expect(lyrics.syncedLyrics == text && lyrics.plainLyrics == nil)
        } else {
            #expect(lyrics.plainLyrics == text && lyrics.syncedLyrics == nil)
        }
        var saved = try JSONDecoder().decode(LyricsCacheService.CacheMetadata.self,
                                             from: Data(contentsOf: metadataURL))
        #expect(saved.entries[1].lastAccess >= before && saved.entries[1].lastAccess <= after)
        saved.entries[1].lastAccess = target.lastAccess
        #expect(try encoded(saved) == encoded(original))
        let reopened = LyricsCacheService(cacheDirectory: root)
        let persisted = try #require(await reopened.getCachedLyrics(audioURL: url))
        #expect(persisted.syncedLyrics == lyrics.syncedLyrics && persisted.plainLyrics == lyrics.plainLyrics)
        #expect(persisted.trackName == target.trackName && persisted.artistName == target.artistName)
    }

    @Test("Missing, empty, whitespace and invalid UTF-8 files leave the index untouched",
          arguments: ["missing", "empty", "whitespace", "invalidUTF8"])
    func invalidFileDoesNotWrite(_ kind: String) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("track.mp3")
        let metadataURL = root.appendingPathComponent("cache_metadata.json")
        let original = try encoded(LyricsCacheService.CacheMetadata(version: 1,
            entries: [entry(for: url, name: "target")]))
        try original.write(to: metadataURL)
        let oldDate = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: metadataURL.path)
        let fileURL = root.appendingPathComponent("target.lrc")
        switch kind {
        case "empty": try Data().write(to: fileURL)
        case "whitespace": try Data(" \n\t ".utf8).write(to: fileURL)
        case "invalidUTF8": try Data([0xff, 0xfe, 0xff]).write(to: fileURL)
        default: break
        }
        let cache = LyricsCacheService(cacheDirectory: root)
        #expect(await cache.getCachedLyrics(audioURL: url) == nil)
        #expect(await cache.getCachedLyrics(audioURL: root.appendingPathComponent("unknown.mp3")) == nil)
        #expect(try Data(contentsOf: metadataURL) == original)
        let attributes = try FileManager.default.attributesOfItem(atPath: metadataURL.path)
        #expect(attributes[.modificationDate] as? Date == oldDate)
    }

    @Test("The same instance observes a repaired disk index")
    func brokenIndexRecovers() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("track.mp3")
        let metadataURL = root.appendingPathComponent("cache_metadata.json")
        let broken = Data("{broken".utf8)
        try broken.write(to: metadataURL)
        let cache = LyricsCacheService(cacheDirectory: root)
        #expect(await cache.getCachedLyrics(audioURL: url) == nil)
        #expect(try Data(contentsOf: metadataURL) == broken)
        try encoded(LyricsCacheService.CacheMetadata(version: 1,
            entries: [entry(for: url, name: "target")])).write(to: metadataURL)
        try Data("recovered lyrics".utf8).write(to: root.appendingPathComponent("target.lrc"))
        let recovered = try #require(await cache.getCachedLyrics(audioURL: url))
        #expect(recovered.plainLyrics == "recovered lyrics")
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lyrics-cache-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func entry(for url: URL, name: String) -> LyricsCacheService.CacheEntry {
        let hash = Insecure.MD5.hash(data: Data(url.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(urlHash: hash, fileName: name, trackName: "歌曲 \(name)", artistName: "Artist \(name)",
                     lastAccess: Date(timeIntervalSince1970: 1_600_000_000), fileSize: 123,
                     createdAt: Date(timeIntervalSince1970: 1_500_000_000))
    }

    private func encoded(_ metadata: LyricsCacheService.CacheMetadata) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(metadata)
    }
}
