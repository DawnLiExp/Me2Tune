//
//  LyricsService.swift
//  Me2Tune
//
//  歌词服务 - LRCLIB API 调用
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
    
    // MARK: - Public Methods
    
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
        
        logger.info("Fetching lyrics for: \(trackName) - \(artistName)")
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LyricsError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            let lyrics = try await decodeLyrics(from: data)
            logger.info("✅ Lyrics found: \(lyrics.id)")
            return lyrics
            
        case 404:
            logger.notice("❌ Lyrics not found")
            throw LyricsError.notFound
            
        default:
            logger.error("API error: \(httpResponse.statusCode)")
            throw LyricsError.apiError(httpResponse.statusCode)
        }
    }
    
    /// 仅从缓存获取歌词（不访问外部源）
    func getCachedLyrics(
        trackName: String,
        artistName: String,
        albumName: String,
        duration: Int
    ) async throws -> Lyrics {
        var components = URLComponents(string: "\(baseURL)/get-cached")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: trackName),
            URLQueryItem(name: "artist_name", value: artistName),
            URLQueryItem(name: "album_name", value: albumName),
            URLQueryItem(name: "duration", value: String(duration))
        ]
        
        guard let url = components.url else {
            throw LyricsError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LyricsError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            return try await decodeLyrics(from: data)
        case 404:
            throw LyricsError.notFound
        default:
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
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .notFound:
            return "Lyrics not found"
        case .apiError(let code):
            return "API error: \(code)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
