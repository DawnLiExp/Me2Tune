//
//  FileMetadataReaderTests.swift
//  Me2TuneTests
//

import Foundation
import Testing
@testable import Me2Tune

@Suite("FileMetadataReader 单元测试")
struct FileMetadataReaderTests {
    @Test("首次请求封面会读取 metadata 并缓存歌词")
    func firstArtworkRequestLoadsMetadataAndCachesLyrics() async throws {
        let url = try makeTemporaryFile()
        let spy = MetadataLoaderSpy(results: [
            .readable(FileMetadataSnapshot(artworkData: Data([1, 2, 3]), lyricsText: "Lyrics"))
        ])
        let reader = FileMetadataReader(loader: spy.load)

        let result = await reader.metadata(for: url, includingArtworkData: true)

        #expect(result?.artworkData == Data([1, 2, 3]))
        #expect(result?.lyricsText == "Lyrics")
        #expect(await spy.calls.map(\.includingArtworkData) == [true])
    }

    @Test("歌词请求命中 readable 缓存时不重新读取 metadata")
    func lyricsRequestHitsReadableCacheWithoutReloading() async throws {
        let url = try makeTemporaryFile()
        let spy = MetadataLoaderSpy(results: [
            .readable(FileMetadataSnapshot(artworkData: Data([1]), lyricsText: "Lyrics"))
        ])
        let reader = FileMetadataReader(loader: spy.load)

        _ = await reader.metadata(for: url, includingArtworkData: true)
        let result = await reader.metadata(for: url, includingArtworkData: false)

        #expect(result?.artworkData == nil)
        #expect(result?.lyricsText == "Lyrics")
        #expect(await spy.calls.map(\.includingArtworkData) == [true])
    }

    @Test("封面请求命中 readable 缓存时仍重新读取 transient artworkData")
    func artworkRequestReloadsWhenReadableCacheHasNoArtworkData() async throws {
        let url = try makeTemporaryFile()
        let spy = MetadataLoaderSpy(results: [
            .readable(FileMetadataSnapshot(artworkData: nil, lyricsText: "Lyrics")),
            .readable(FileMetadataSnapshot(artworkData: Data([9]), lyricsText: "Lyrics"))
        ])
        let reader = FileMetadataReader(loader: spy.load)

        _ = await reader.metadata(for: url, includingArtworkData: false)
        let result = await reader.metadata(for: url, includingArtworkData: true)

        #expect(result?.artworkData == Data([9]))
        #expect(result?.lyricsText == "Lyrics")
        #expect(await spy.calls.map(\.includingArtworkData) == [false, true])
    }

    @Test("mtime 变化后缓存失效并重新读取")
    func modificationDateChangeInvalidatesCache() async throws {
        let url = try makeTemporaryFile(modificationDate: Date(timeIntervalSince1970: 100))
        let spy = MetadataLoaderSpy(results: [
            .readable(FileMetadataSnapshot(artworkData: nil, lyricsText: "Old")),
            .readable(FileMetadataSnapshot(artworkData: nil, lyricsText: "New"))
        ])
        let reader = FileMetadataReader(loader: spy.load)

        _ = await reader.metadata(for: url, includingArtworkData: false)
        try setModificationDate(Date(timeIntervalSince1970: 200), for: url)
        let result = await reader.metadata(for: url, includingArtworkData: false)

        #expect(result?.lyricsText == "New")
        #expect(await spy.calls.count == 2)
    }

    @Test("不可读文件会缓存 unreadable 结果")
    func unreadableFileCachesNegativeResult() async throws {
        let url = try makeTemporaryFile()
        let spy = MetadataLoaderSpy(results: [.unreadable])
        let reader = FileMetadataReader(loader: spy.load)

        let first = await reader.metadata(for: url, includingArtworkData: true)
        let second = await reader.metadata(for: url, includingArtworkData: false)

        #expect(first == nil)
        #expect(second == nil)
        #expect(await spy.calls.map(\.includingArtworkData) == [true])
    }

    @Test("缓存超过上限会清空旧条目")
    func cacheLimitClearsExistingEntries() async throws {
        let urls = try (0..<3).map { try makeTemporaryFile(name: "track-\($0).mp3") }
        let spy = MetadataLoaderSpy(results: [
            .readable(FileMetadataSnapshot(artworkData: nil, lyricsText: "One")),
            .readable(FileMetadataSnapshot(artworkData: nil, lyricsText: "Two")),
            .readable(FileMetadataSnapshot(artworkData: nil, lyricsText: "Three")),
            .readable(FileMetadataSnapshot(artworkData: nil, lyricsText: "One Reloaded"))
        ])
        let reader = FileMetadataReader(maxCacheEntries: 2, loader: spy.load)

        _ = await reader.metadata(for: urls[0], includingArtworkData: false)
        _ = await reader.metadata(for: urls[1], includingArtworkData: false)
        _ = await reader.metadata(for: urls[2], includingArtworkData: false)
        let reloaded = await reader.metadata(for: urls[0], includingArtworkData: false)

        #expect(reloaded?.lyricsText == "One Reloaded")
        #expect(await spy.calls.count == 4)
    }

    private func makeTemporaryFile(
        name: String = UUID().uuidString + ".mp3",
        modificationDate: Date = Date(timeIntervalSince1970: 100)
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Me2TuneFileMetadataReaderTests", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try Data([0]).write(to: url)
        try setModificationDate(modificationDate, for: url)
        return url
    }

    private func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}

private actor MetadataLoaderSpy {
    struct Call: Sendable {
        let url: URL
        let includingArtworkData: Bool
    }

    private(set) var calls: [Call] = []
    private var results: [FileMetadataReadResult]

    init(results: [FileMetadataReadResult]) {
        self.results = results
    }

    func load(url: URL, includingArtworkData: Bool) async -> FileMetadataReadResult {
        calls.append(Call(url: url, includingArtworkData: includingArtworkData))
        guard !results.isEmpty else {
            return .unreadable
        }
        return results.removeFirst()
    }
}
