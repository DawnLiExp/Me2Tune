//
//  FileMetadataReader.swift
//  Me2Tune
//
//  播放期文件 metadata 读取器 - 共享封面和内嵌歌词读取
//

import Foundation
import OSLog
import SFBAudioEngine

private nonisolated let metadataLogger = Logger.metadata

nonisolated struct FileMetadataSnapshot: Sendable {
    let artworkData: Data?
    let lyricsText: String?
}

nonisolated enum FileMetadataReadResult: Sendable {
    case readable(FileMetadataSnapshot)
    case unreadable
}

actor FileMetadataReader {
    static let shared = FileMetadataReader()

    private enum CachedResult {
        case readable(lyricsText: String?, modDate: Date)
        case unreadable(modDate: Date)
    }

    private var cache: [String: CachedResult] = [:]
    private var revisions: [String: UUID] = [:]

    func invalidate(url: URL) {
        revisions[url.path] = UUID()
        cache[url.path] = nil
    }
    private let maxCacheEntries: Int
    private let loader: @Sendable (URL, Bool) async -> FileMetadataReadResult

    init(
        maxCacheEntries: Int = 200,
        loader: @escaping @Sendable (URL, Bool) async -> FileMetadataReadResult = FileMetadataReader.loadFromAudioFile
    ) {
        self.maxCacheEntries = maxCacheEntries
        self.loader = loader
    }

    func metadata(for url: URL, includingArtworkData: Bool) async -> FileMetadataSnapshot? {
        let key = url.path
        let modDate = modificationDate(for: url)
        let revision = revisions[key]

        if let cached = cache[key] {
            switch cached {
            case .readable(let lyricsText, let cachedModDate) where cachedModDate == modDate:
                if !includingArtworkData {
                    return FileMetadataSnapshot(artworkData: nil, lyricsText: lyricsText)
                }
            case .unreadable(let cachedModDate) where cachedModDate == modDate:
                return nil
            default:
                break
            }
        }

        evictIfNeeded()

        let result = await loader(url, includingArtworkData)
        guard revisions[key] == revision else { return nil }
        switch result {
        case .readable(let snapshot):
            cache[key] = .readable(lyricsText: snapshot.lyricsText, modDate: modDate)
            return snapshot
        case .unreadable:
            cache[key] = .unreadable(modDate: modDate)
            return nil
        }
    }

    private func modificationDate(for url: URL) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date ?? .distantPast
    }

    private func evictIfNeeded() {
        guard cache.count >= maxCacheEntries else { return }
        cache.removeAll()
        metadataLogger.debug("FileMetadataReader cache cleared at cap \(self.maxCacheEntries)")
    }

    private nonisolated static func loadFromAudioFile(
        url: URL,
        includingArtworkData: Bool
    ) async -> FileMetadataReadResult {
        if ["mp3", "flac", "m4a"].contains(url.pathExtension.lowercased()),
           let snapshot = try? await TrackTagService.shared.read(url: url) {
            let lyrics = snapshot.values(.lyrics).first.flatMap { $0.isEmpty ? nil : $0 }
            return .readable(FileMetadataSnapshot(artworkData: includingArtworkData ? snapshot.artwork : nil,
                                                 lyricsText: lyrics))
        }
        let task = Task.detached(priority: .utility) { () -> FileMetadataReadResult in
            let startTime = CFAbsoluteTimeGetCurrent()
            defer {
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                metadataLogger.logPerformance("File metadata read", duration: elapsed)
            }

            guard let audioFile = try? SFBAudioEngine.AudioFile(readingPropertiesAndMetadataFrom: url) else {
                return .unreadable
            }

            let artworkData: Data?
            if includingArtworkData {
                artworkData = audioFile.metadata.attachedPictures.first?.imageData
            } else {
                artworkData = nil
            }

            let lyricsText = audioFile.metadata.lyrics.flatMap { rawText in
                let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

            return .readable(FileMetadataSnapshot(
                artworkData: artworkData,
                lyricsText: lyricsText
            ))
        }

        return await task.value
    }
}
