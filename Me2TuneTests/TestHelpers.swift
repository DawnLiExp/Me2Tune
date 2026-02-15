//
//  TestHelpers.swift
//  Me2TuneTests
//
//  测试辅助工具 - 提供内存数据库和常用断言扩展
//

import Foundation
import SwiftData
import Testing
@testable import Me2Tune

// MARK: - Test ModelContainer Factory

/// 为每个测试创建独立的内存数据库，测试结束后自动销毁
@MainActor
func createTestModelContainer() throws -> ModelContainer {
    let schema = Schema([
        SDTrack.self,
        SDAlbum.self,
        SDAlbumTrackEntry.self,
        SDPlaybackState.self,
        SDStatistics.self,
    ])
    
    // 关键：使用内存存储，不会影响真实数据库
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    
    return try ModelContainer(for: schema, configurations: [config])
}

// MARK: - Sample Data Builders

extension SDTrack {
    /// 快速创建测试用的歌曲
    static func makeSample(
        title: String = "Test Song",
        artist: String? = "Test Artist",
        albumTitle: String? = nil,
        urlString: String = "file:///test.mp3",
        duration: TimeInterval = 180.0
    ) -> SDTrack {
        SDTrack(
            title: title,
            artist: artist,
            albumTitle: albumTitle,
            duration: duration,
            urlString: urlString,
            bookmark: nil,
            codec: "FLAC",
            bitrate: 1411,
            sampleRate: 44100,
            bitDepth: 16,
            channels: 2
        )
    }
}

extension SDStatistics {
    /// 快速创建测试统计数据
    static func makeSample(
        dateString: String,
        playCount: Int = 1
    ) -> SDStatistics {
        SDStatistics(
            dateString: dateString,
            playCount: playCount
        )
    }
}
