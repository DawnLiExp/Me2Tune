//
//  LyricsService.swift
//  Me2Tune
//
//  歌词服务 - LRCLIB API 调用 + 本地 LRC 文件读取 + 缓存集成 + 智能重试
//

import Foundation
import OSLog

private nonisolated let logger = Logger.lyrics

actor LyricsService {
    static let shared = LyricsService()
    
    private let baseURL = "https://lrclib.net/api"
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = [
            "User-Agent": "Me2Tune v0.8.0 (https://github.com/DawnLiExp/Me2Tune)"
        ]
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Unified Entry Point
    
    func getLyricsWithCache(track: AudioTrack) async throws -> Lyrics {
        try Task.checkCancellation()
        
        // 1. 本地LRC文件
        if let local = try? await getLocalLyrics(audioURL: track.url) {
            try Task.checkCancellation()
            logger.info("✅ Local lyrics found")
            return local
        }
        
        // 2. 缓存LRC
        try Task.checkCancellation()
        if let cached = await LyricsCacheService.shared.getCachedLyrics(audioURL: track.url) {
            try Task.checkCancellation()
            logger.info("✅ Cache hit")
            return cached
        }
        
        // 3. 网络API（带智能重试）
        try Task.checkCancellation()
        logger.info("🌐 Fetching from API with retry: \(track.title)")
        let lyrics = try await getLyricsWithRetry(track: track)
        
        try Task.checkCancellation()
        
        Task {
            await LyricsCacheService.shared.saveLyrics(lyrics, audioURL: track.url)
        }
        
        return lyrics
    }
    
    // MARK: - Local LRC File
    
    func getLocalLyrics(audioURL: URL) async throws -> Lyrics {
        let lrcURL = audioURL.deletingPathExtension().appendingPathExtension("lrc")
        
        guard FileManager.default.fileExists(atPath: lrcURL.path) else {
            throw LyricsError.notFound
        }
        
        let content: String
        do {
            content = try String(contentsOf: lrcURL, encoding: .utf8)
        } catch {
            logger.error("Failed to read local LRC: \(error.localizedDescription)")
            throw LyricsError.fileReadError
        }
        
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LyricsError.emptyFile
        }
        
        return Lyrics(
            id: 0,
            trackName: audioURL.deletingPathExtension().lastPathComponent,
            artistName: "Local",
            albumName: nil,
            duration: 0,
            instrumental: false,
            plainLyrics: nil,
            syncedLyrics: content
        )
    }
    
    // MARK: - Retry Logic
    
    private func getLyricsWithRetry(track: AudioTrack) async throws -> Lyrics {
        let artist = track.artist ?? "Unknown Artist"
        let album = track.albumTitle ?? ""
        let duration = Int(track.duration)
        
        // 第一次尝试：使用完整信息
        do {
            let lyrics = try await getLyrics(
                trackName: track.title,
                artistName: artist,
                albumName: album,
                duration: duration
            )
            logger.info("✅ Exact match success")
            return lyrics
        } catch LyricsError.notFound {
            logger.info("⚠️ Exact match failed (404)")
        } catch is DecodingError {
            logger.warning("⚠️ Exact match decode error (invalid response format)")
        } catch {
            logger.error("❌ Exact match error: \(error.localizedDescription)")
            // 仅致命网络错误（超时等）才抛出
            if let urlError = error as? URLError, urlError.code == .timedOut {
                throw error
            }
        }
        
        // 第二次尝试：规范化专辑名
        if !album.isEmpty {
            let normalizedAlbum = normalizeAlbumName(album)
            if normalizedAlbum != album {
                logger.info("🔄 Retrying with normalized album: '\(normalizedAlbum)' (original: '\(album)')")
                do {
                    let lyrics = try await getLyrics(
                        trackName: track.title,
                        artistName: artist,
                        albumName: normalizedAlbum,
                        duration: duration
                    )
                    logger.info("✅ Normalized match success")
                    return lyrics
                } catch LyricsError.notFound {
                    logger.info("⚠️ Normalized match failed (404)")
                } catch is DecodingError {
                    logger.warning("⚠️ Normalized match decode error")
                } catch {
                    logger.error("❌ Normalized match error: \(error.localizedDescription)")
                    if let urlError = error as? URLError, urlError.code == .timedOut {
                        throw error
                    }
                }
            } else {
                logger.info("ℹ️ Album already normalized, skipping second attempt")
            }
        }
        
        // 第三次尝试：忽略专辑名
        if !album.isEmpty {
            logger.info("🔄 Retrying without album name")
            do {
                let lyrics = try await getLyrics(
                    trackName: track.title,
                    artistName: artist,
                    albumName: "",
                    duration: duration
                )
                logger.info("✅ No-album match success")
                return lyrics
            } catch LyricsError.notFound {
                logger.info("⚠️ No-album match failed (404)")
            } catch is DecodingError {
                logger.warning("⚠️ No-album match decode error")
            } catch {
                logger.error("❌ No-album match error: \(error.localizedDescription)")
            }
        }
        
        // 第四次尝试：使用搜索 API
        logger.info("🔍 Falling back to search API")
        do {
            return try await searchLyrics(track: track)
        } catch is DecodingError {
            logger.error("❌ All attempts failed with decode errors - API may be returning problematic data")
            throw LyricsError.invalidResponse
        } catch {
            logger.error("❌ Search API failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Album Name Normalization
    
    private func normalizeAlbumName(_ albumName: String) -> String {
        var normalized = albumName
        
        // 1. 移除括号及其内容：(Deluxe Version), (Remastered) 等
        let parenthesesPattern = "\\s*\\([^)]*\\)\\s*"
        if let regex = try? NSRegularExpression(pattern: parenthesesPattern) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            normalized = regex.stringByReplacingMatches(
                in: normalized,
                range: range,
                withTemplate: ""
            ).trimmingCharacters(in: .whitespaces)
        }
        
        // 2. 移除常见后缀：- EP, - Single, - Deluxe 等
        let suffixPattern = "\\s*-\\s*(EP|Single|Deluxe|Remastered|Deluxe Edition|Bonus Track Version|Live|Acoustic|CD \\d+)\\s*$"
        if let regex = try? NSRegularExpression(pattern: suffixPattern, options: .caseInsensitive) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            normalized = regex.stringByReplacingMatches(
                in: normalized,
                range: range,
                withTemplate: ""
            ).trimmingCharacters(in: .whitespaces)
        }
        
        return normalized.isEmpty ? albumName : normalized
    }
    
    // MARK: - Network API - Exact Match
    
    private func getLyrics(
        trackName: String,
        artistName: String,
        albumName: String,
        duration: Int
    ) async throws -> Lyrics {
        try Task.checkCancellation()
        
        var components = URLComponents(string: "\(baseURL)/get")!
        var queryItems = [
            URLQueryItem(name: "track_name", value: trackName),
            URLQueryItem(name: "artist_name", value: artistName),
            URLQueryItem(name: "duration", value: String(duration))
        ]
        
        if !albumName.isEmpty {
            queryItems.append(URLQueryItem(name: "album_name", value: albumName))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw LyricsError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        try Task.checkCancellation()
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LyricsError.invalidResponse
        }
        
        // 先检查状态码
        switch httpResponse.statusCode {
        case 200:
            break // 继续解析
        case 404:
            throw LyricsError.notFound
        default:
            logger.error("Unexpected API status: \(httpResponse.statusCode)")
            throw LyricsError.apiError(httpResponse.statusCode)
        }
        
        // 尝试解码 JSON
        do {
            return try await decodeLyrics(from: data)
        } catch let error as DecodingError {
            // DecodingError 详细诊断
            if let responseText = String(data: data, encoding: .utf8) {
                let snippet = responseText.prefix(2000)
                logger.error("JSON decode failed: \(error.localizedDescription). Data snippet: \(snippet)")
                
                // 检查是否为明显的截断
                let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.hasSuffix("}"), !trimmed.hasSuffix("]") {
                    logger.warning("⚠️ Response appears truncated (size: \(data.count) bytes)")
                }
            }
            throw error
        } catch {
            throw error
        }
    }
    
    // MARK: - Network API - Search Fallback
    
    private func searchLyrics(track: AudioTrack) async throws -> Lyrics {
        try Task.checkCancellation()
        
        let artist = track.artist ?? "Unknown Artist"
        logger.info("🔎 Searching: track='\(track.title)', artist='\(artist)'")
        
        var components = URLComponents(string: "\(baseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        
        guard let url = components.url else {
            throw LyricsError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        try Task.checkCancellation()
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LyricsError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            logger.error("Search API error: HTTP \(httpResponse.statusCode)")
            throw LyricsError.notFound
        }
        
        // 解析搜索结果数组
        let targetDuration = Int(track.duration)
        let results: [Lyrics]
        do {
            results = try await MainActor.run {
                let decoder = JSONDecoder()
                return try decoder.decode([Lyrics].self, from: data)
            }
        } catch let error as DecodingError {
            if let responseText = String(data: data, encoding: .utf8) {
                let snippet = responseText.prefix(2000)
                logger.error("Search JSON decode failed: \(error.localizedDescription). Data snippet: \(snippet)")
                
                let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.hasSuffix("}"), !trimmed.hasSuffix("]") {
                    logger.warning("⚠️ Search response truncated (size: \(data.count) bytes)")
                }
            }
            throw error
        } catch {
            throw error
        }
        
        logger.info("📊 Search returned \(results.count) result(s)")
        
        guard !results.isEmpty else {
            throw LyricsError.notFound
        }
        
        // 排序逻辑：
        // 优先选择：时长最接近的结果。
        // 如果时长一样，优先选择：艺术家完全正确（忽略大小写）的结果。
        let sortedResults = results.sorted { a, b in
            let diffA = abs(a.duration - Double(targetDuration))
            let diffB = abs(b.duration - Double(targetDuration))
            
            if abs(diffA - diffB) < 0.1 {
                // 如果时长差异极小，检查艺术家匹配度
                let artistMatchA = a.artistName.lowercased() == artist.lowercased()
                let artistMatchB = b.artistName.lowercased() == artist.lowercased()
                if artistMatchA != artistMatchB {
                    return artistMatchA
                }
            }
            return diffA < diffB
        }
        
        let bestMatch = sortedResults[0]
        let bestMatchDiff = abs(bestMatch.duration - Double(targetDuration))
        
        if bestMatchDiff <= 4 { // 允许 4 秒误差
            logger.info("✅ Best match found: \(bestMatch.trackName) - \(bestMatch.albumName ?? "Unknown") (\(bestMatch.duration)s, diff: \(bestMatchDiff)s)")
            return bestMatch
        } else {
            logger.warning("⚠️ No close duration match (target: \(targetDuration)s, best: \(bestMatch.duration)s), using most similar.")
            return bestMatch
        }
    }

    // MARK: - Decoding Helper

    private func decodeLyrics(from data: Data) async throws -> Lyrics {
        try await MainActor.run {
            let decoder = JSONDecoder()
            return try decoder.decode(Lyrics.self, from: data)
        }
    }
}

// MARK: - Error Types

enum LyricsError: LocalizedError {
    case invalidURL
    case invalidResponse
    case notFound
    case apiError(Int)
    case networkError(Error)
    case fileReadError
    case emptyFile
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "invalid_api_url")
        case .invalidResponse:
            return String(localized: "invalid_response")
        case .notFound:
            return String(localized: "lyrics_not_found")
        case .apiError(let code):
            return String(localized: "api_error \(code)")
        case .networkError(let error):
            return String(localized: "network_error \(error.localizedDescription)")
        case .fileReadError:
            return String(localized: "failed_to_load_lyrics")
        case .emptyFile:
            return String(localized: "lyrics_not_found")
        }
    }
}
