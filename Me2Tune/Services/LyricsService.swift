//
//  LyricsService.swift
//  Me2Tune
//
//  歌词服务 - LRCLIB API 调用 + 本地 LRC 文件读取 + 缓存集成
//

import Foundation
import OSLog

private nonisolated let logger = Logger(subsystem: "me2.Me2Tune", category: "Lyrics")

actor LyricsService {
    static let shared = LyricsService()
    
    private let baseURL = "https://lrclib.net/api"
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = [
            "User-Agent": "Me2Tune v0.4.0 (https://github.com/DawnLiExp/Me2Tune)"
        ]
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Unified Entry Point
    
    /// 统一的歌词获取入口（优先级：本地 > 缓存 > 网络）
    func getLyricsWithCache(track: AudioTrack) async throws -> Lyrics {
        // 1. 本地LRC文件（优先级最高）
        if let local = try? await getLocalLyrics(audioURL: track.url) {
            logger.info("✅ Local lyrics loaded")
            return local
        }
        
        // 2. 缓存LRC
        if let cached = await LyricsCacheService.shared.getCachedLyrics(
            audioURL: track.url
        ) {
            logger.info("✅ Cached lyrics loaded")
            return cached
        }
        
        // 3. 网络API
        logger.info("🌐 Fetching lyrics from API...")
        let lyrics = try await getLyrics(
            trackName: track.title,
            artistName: track.artist ?? "Unknown Artist",
            albumName: track.albumTitle ?? "",
            duration: Int(track.duration)
        )
        
        // 保存到缓存（异步，不阻塞返回）
        Task {
            await LyricsCacheService.shared.saveLyrics(lyrics, audioURL: track.url)
        }
        
        return lyrics
    }
    
    // MARK: - Local LRC File
    
    /// 从本地读取 LRC 歌词文件（精确文件名匹配，同目录）
    func getLocalLyrics(audioURL: URL) async throws -> Lyrics {
        let lrcURL = audioURL.deletingPathExtension().appendingPathExtension("lrc")
        
        logger.debug("Looking for local lyrics: \(lrcURL.lastPathComponent)")
        
        guard FileManager.default.fileExists(atPath: lrcURL.path) else {
            logger.debug("Local lyrics file not found")
            throw LyricsError.notFound
        }
        
        let content: String
        do {
            content = try String(contentsOf: lrcURL, encoding: .utf8)
        } catch {
            logger.error("Failed to read local lyrics: \(error.localizedDescription)")
            throw LyricsError.fileReadError
        }
        
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.warning("Local lyrics file is empty")
            throw LyricsError.emptyFile
        }
        
        let lyrics = Lyrics(
            id: 0,
            trackName: audioURL.deletingPathExtension().lastPathComponent,
            artistName: "Local",
            albumName: nil,
            duration: 0,
            instrumental: false,
            plainLyrics: nil,
            syncedLyrics: content
        )
        
        logger.info("✅ Local lyrics loaded: \(lrcURL.lastPathComponent)")
        return lyrics
    }
    
    // MARK: - Network API
    
    /// 根据曲目签名获取歌词（会尝试外部源）
    func getLyrics(
        trackName: String,
        artistName: String,
        albumName: String,
        duration: Int
    ) async throws -> Lyrics {
        var components = URLComponents(string: "\(baseURL)/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: trackName),
            URLQueryItem(name: "artist_name", value: artistName),
            URLQueryItem(name: "album_name", value: albumName),
            URLQueryItem(name: "duration", value: String(duration))
        ]
        
        guard let url = components.url else {
            throw LyricsError.invalidURL
        }
        
        logger.info("Fetching lyrics from API: \(trackName) - \(artistName)")
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LyricsError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            let lyrics = try await decodeLyrics(from: data)
            logger.info("✅ API lyrics found: \(lyrics.id)")
            return lyrics
            
        case 404:
            logger.notice("❌ API lyrics not found")
            throw LyricsError.notFound
            
        default:
            logger.error("API error: \(httpResponse.statusCode)")
            throw LyricsError.apiError(httpResponse.statusCode)
        }
    }
}

// MARK: - Decoding Helper (Global)

private func decodeLyrics(from data: Data) throws -> Lyrics {
    let decoder = JSONDecoder()
    return try decoder.decode(Lyrics.self, from: data)
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
