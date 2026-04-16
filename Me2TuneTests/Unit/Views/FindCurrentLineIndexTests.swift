//
//  FindCurrentLineIndexTests.swift
//  Me2TuneTests
//
//  属性 2: 歌词行匹配中偏移量的正确应用
//

import Testing
@testable import Me2Tune

/// **Validates: Requirements 4.2**
@MainActor
@Suite("findCurrentLineIndex 偏移应用单元测试")
struct FindCurrentLineIndexTests {

    // MARK: - 测试用歌词行

    /// 构造一组按时间戳升序排列的歌词行: 0s, 3s, 6s, 9s, 12s
    private static var sampleLines: [LyricLine] {
        [
            LyricLine(timestamp: 0.0, text: "Line 0", translation: nil),
            LyricLine(timestamp: 3.0, text: "Line 1", translation: nil),
            LyricLine(timestamp: 6.0, text: "Line 2", translation: nil),
            LyricLine(timestamp: 9.0, text: "Line 3", translation: nil),
            LyricLine(timestamp: 12.0, text: "Line 4", translation: nil),
        ]
    }

    // MARK: - 正偏移使匹配延后

    /// **Validates: Requirements 4.2**
    @Test("正偏移使匹配延后：time=5.0, offset=1.0 → adjustedTime=4.0 → 匹配 Line 1 (index 1)")
    func positiveOffsetDelaysMatching() {
        // adjustedTime = 5.0 - 1.0 = 4.0, 最后一个 timestamp ≤ 4.0 的是 3.0 (index 1)
        let result = LyricsView.findCurrentLineIndex(
            in: Self.sampleLines, at: 5.0, offset: 1.0
        )
        #expect(result == 1)
    }

    /// **Validates: Requirements 4.2**
    @Test("正偏移使匹配延后：time=6.0, offset=1.0 → adjustedTime=5.0 → 仍匹配 Line 1 (index 1)")
    func positiveOffsetDelaysMatchingBoundary() {
        // adjustedTime = 6.0 - 1.0 = 5.0, 最后一个 timestamp ≤ 5.0 的是 3.0 (index 1)
        // 无偏移时 time=6.0 会匹配 index 2，正偏移使匹配延后
        let withOffset = LyricsView.findCurrentLineIndex(
            in: Self.sampleLines, at: 6.0, offset: 1.0
        )
        let withoutOffset = LyricsView.findCurrentLineIndex(
            in: Self.sampleLines, at: 6.0, offset: 0.0
        )
        #expect(withOffset == 1)
        #expect(withoutOffset == 2)
    }

    // MARK: - 负偏移使匹配提前

    /// **Validates: Requirements 4.2**
    @Test("负偏移使匹配提前：time=5.0, offset=-1.0 → adjustedTime=6.0 → 匹配 Line 2 (index 2)")
    func negativeOffsetAdvancesMatching() {
        // adjustedTime = 5.0 - (-1.0) = 6.0, 最后一个 timestamp ≤ 6.0 的是 6.0 (index 2)
        let result = LyricsView.findCurrentLineIndex(
            in: Self.sampleLines, at: 5.0, offset: -1.0
        )
        #expect(result == 2)
    }

    /// **Validates: Requirements 4.2**
    @Test("负偏移使匹配提前：time=2.0, offset=-1.0 → adjustedTime=3.0 → 匹配 Line 1 (index 1)")
    func negativeOffsetAdvancesMatchingBoundary() {
        // adjustedTime = 2.0 - (-1.0) = 3.0, 最后一个 timestamp ≤ 3.0 的是 3.0 (index 1)
        // 无偏移时 time=2.0 只匹配 index 0，负偏移使匹配提前
        let withOffset = LyricsView.findCurrentLineIndex(
            in: Self.sampleLines, at: 2.0, offset: -1.0
        )
        let withoutOffset = LyricsView.findCurrentLineIndex(
            in: Self.sampleLines, at: 2.0, offset: 0.0
        )
        #expect(withOffset == 1)
        #expect(withoutOffset == 0)
    }

    // MARK: - 偏移后时间为负值返回 nil

    /// **Validates: Requirements 4.2**
    @Test("偏移后时间为负值时返回 nil：time=0.5, offset=1.5 → adjustedTime=-1.0")
    func negativeAdjustedTimeReturnsNil() {
        // adjustedTime = 0.5 - 1.5 = -1.0, 所有 timestamp ≥ 0，无匹配
        let result = LyricsView.findCurrentLineIndex(
            in: Self.sampleLines, at: 0.5, offset: 1.5
        )
        #expect(result == nil)
    }

    // MARK: - 空歌词行列表返回 nil

    /// **Validates: Requirements 4.2**
    @Test("空歌词行列表返回 nil")
    func emptyLinesReturnsNil() {
        let result = LyricsView.findCurrentLineIndex(
            in: [], at: 5.0, offset: 0.0
        )
        #expect(result == nil)
    }

    // MARK: - 零偏移正常行为

    /// **Validates: Requirements 4.2**
    @Test("零偏移正常匹配：time=6.0, offset=0.0 → 匹配 Line 2 (index 2)")
    func zeroOffsetBehavesNormally() {
        // adjustedTime = 6.0 - 0.0 = 6.0, 最后一个 timestamp ≤ 6.0 的是 6.0 (index 2)
        let result = LyricsView.findCurrentLineIndex(
            in: Self.sampleLines, at: 6.0, offset: 0.0
        )
        #expect(result == 2)
    }

    /// **Validates: Requirements 4.2**
    @Test("零偏移：time 恰好在第一行之前返回 nil")
    func zeroOffsetBeforeFirstLineReturnsNil() {
        // 构造第一行 timestamp > 0 的歌词
        let lines = [
            LyricLine(timestamp: 2.0, text: "Intro", translation: nil),
            LyricLine(timestamp: 5.0, text: "Verse", translation: nil),
        ]
        let result = LyricsView.findCurrentLineIndex(
            in: lines, at: 1.0, offset: 0.0
        )
        #expect(result == nil)
    }
}
