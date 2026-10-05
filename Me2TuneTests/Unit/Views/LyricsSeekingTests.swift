//
//  LyricsSeekingTests.swift
//  Me2TuneTests
//
//  歌词行定位跳转时间戳计算与寻道单元测试
//

import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("歌词行定位跳转计算测试")
struct LyricsSeekingTests {
    private let sampleLines: [LyricLine] = [
        LyricLine(timestamp: 0.0, text: "Intro", translation: nil),
        LyricLine(timestamp: 5.2, text: "Line 1: First phrase", translation: "第一句"),
        LyricLine(timestamp: 12.8, text: "Line 2: Second phrase", translation: "第二句"),
        LyricLine(timestamp: 25.4, text: "Line 3: Chorus starts", translation: "副歌开始"),
        LyricLine(timestamp: 45.0, text: "Line 4: Outro", translation: "尾奏")
    ]

    @Test("零偏移量下精准计算跳转时间戳并正向匹配歌词行")
    func testSeekTimeWithZeroOffset() {
        let line = sampleLines[2] // 12.8s
        let seekTime = LyricsView.calculateSeekTime(for: line, offset: 0.0, duration: 60.0)
        
        #expect(seekTime > 12.8)
        #expect(seekTime < 12.81)
        
        let foundIndex = LyricsView.findCurrentLineIndex(in: sampleLines, at: seekTime, offset: 0.0)
        #expect(foundIndex == 2)
    }

    @Test("正向偏移补偿下跳转时间戳正确且能反向匹配目标行")
    func testSeekTimeWithPositiveOffset() {
        let line = sampleLines[3] // 25.4s
        let offset = 0.5
        let seekTime = LyricsView.calculateSeekTime(for: line, offset: offset, duration: 60.0)
        
        #expect(abs(seekTime - (25.4 + offset)) < 0.01)
        
        let foundIndex = LyricsView.findCurrentLineIndex(in: sampleLines, at: seekTime, offset: offset)
        #expect(foundIndex == 3)
    }

    @Test("负向偏移补偿下跳转时间戳正确且能反向匹配目标行")
    func testSeekTimeWithNegativeOffset() {
        let line = sampleLines[1] // 5.2s
        let offset = -0.8
        let seekTime = LyricsView.calculateSeekTime(for: line, offset: offset, duration: 60.0)
        
        #expect(abs(seekTime - (5.2 + offset)) < 0.01)
        
        let foundIndex = LyricsView.findCurrentLineIndex(in: sampleLines, at: seekTime, offset: offset)
        #expect(foundIndex == 1)
    }

    @Test("跳转时间戳不低于 0 且不超过曲目总时长")
    func testSeekTimeBoundaryClamping() {
        let firstLine = sampleLines[0] // 0.0s
        let negativeSeekTime = LyricsView.calculateSeekTime(for: firstLine, offset: -2.0, duration: 60.0)
        #expect(negativeSeekTime == 0.0)

        let lastLine = sampleLines[4] // 45.0s
        let clampedSeekTime = LyricsView.calculateSeekTime(for: lastLine, offset: 20.0, duration: 50.0)
        #expect(clampedSeekTime == 50.0)
    }

    @Test("跳转全部各行均能精确命中对应行索引")
    func testAllLinesSeekHitAccuracy() {
        for (index, line) in sampleLines.enumerated() {
            let seekTime = LyricsView.calculateSeekTime(for: line, offset: 0.0, duration: 100.0)
            let matchedIndex = LyricsView.findCurrentLineIndex(in: sampleLines, at: seekTime, offset: 0.0)
            #expect(matchedIndex == index)
        }
    }
}
