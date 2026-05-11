//
//  LyricsParsingTests.swift
//  Me2TuneTests
//

import Testing
@testable import Me2Tune

@MainActor
@Suite("Lyrics 解析单元测试")
struct LyricsParsingTests {
    @Test("解析多种 LRC 时间戳精度")
    func parsesCommonTimestampPrecisions() {
        let lyrics = makeLyrics("""
        [00:01.23]centiseconds
        [00:02.234]milliseconds
        [00:03.2]tenths
        [00:04]seconds
        [00:05,234]comma milliseconds
        [00:06:234]colon milliseconds
        """)

        let lines = lyrics.parseSyncedLyrics()

        #expect(lines.count == 6)
        #expect(lines.map(\.text) == [
            "centiseconds",
            "milliseconds",
            "tenths",
            "seconds",
            "comma milliseconds",
            "colon milliseconds",
        ])
        expectTimestamps(lines.map(\.timestamp), equalTo: [
            1.23,
            2.234,
            3.2,
            4.0,
            5.234,
            6.234,
        ])
    }

    @Test("忽略元信息标签并解析三位毫秒样本")
    func ignoresMetadataAndParsesMillisecondSample() {
        let lyrics = makeLyrics("""
        [kuwo:034]
        [ver:v1.0]
        [ti:婴儿]
        [ar:陈倩倩]
        [al:异想天开]
        [by:]
        [offset:0]
        [00:00.718]婴儿 - 陈倩倩
        [00:01.824]词：陈涛
        """)

        let lines = lyrics.parseSyncedLyrics()

        #expect(lines.count == 2)
        guard lines.count == 2 else { return }
        expectTimestamp(lines[0].timestamp, equals: 0.718)
        #expect(lines[0].text == "婴儿 - 陈倩倩")
        expectTimestamp(lines[1].timestamp, equals: 1.824)
        #expect(lines[1].text == "词：陈涛")
    }

    @Test("相同时间戳的连续两行合并为双语歌词")
    func mergesConsecutiveLinesWithSameTimestampAsTranslation() {
        let lyrics = makeLyrics("""
        [00:10.123]Main line
        [00:10.123]Translation line
        """)

        let lines = lyrics.parseSyncedLyrics()

        #expect(lines.count == 1)
        guard let line = lines.first else { return }
        expectTimestamp(line.timestamp, equals: 10.123)
        #expect(line.text == "Main line")
        #expect(line.translation == "Translation line")
    }

    @Test("整段多行内容可检测到同步时间戳")
    func detectsTimestampInMultilineContent() {
        let content = """
        [kuwo:034]
        [offset:0]
        [00:00.718]婴儿 - 陈倩倩
        [00:01.824]词：陈涛
        [by:]
        """

        #expect(LRCTimestampParser.containsTimestamp(in: content))
    }

    @Test("offset 正值会整体延后歌词时间")
    func appliesPositiveOffsetToDelayTimestamps() {
        let lyrics = makeLyrics("""
        [offset:+500]
        [00:01.000]Delayed line
        """)

        let lines = lyrics.parseSyncedLyrics()

        #expect(lines.count == 1)
        guard let line = lines.first else { return }
        expectTimestamp(line.timestamp, equals: 1.5)
        #expect(line.text == "Delayed line")
    }

    @Test("offset 负值会整体提前歌词时间")
    func appliesNegativeOffsetToAdvanceTimestamps() {
        let lyrics = makeLyrics("""
        [offset:-250]
        [00:01.000]Advanced line
        """)

        let lines = lyrics.parseSyncedLyrics()

        #expect(lines.count == 1)
        guard let line = lines.first else { return }
        expectTimestamp(line.timestamp, equals: 0.75)
        #expect(line.text == "Advanced line")
    }

    @Test("offset 无符号数按正值处理")
    func appliesUnsignedOffsetAsPositiveDelay() {
        let lyrics = makeLyrics("""
        [offset:250]
        [00:01.000]Unsigned delay
        """)

        let lines = lyrics.parseSyncedLyrics()

        #expect(lines.count == 1)
        guard let line = lines.first else { return }
        expectTimestamp(line.timestamp, equals: 1.25)
        #expect(line.text == "Unsigned delay")
    }

    private func expectTimestamps(_ actual: [Double], equalTo expected: [Double]) {
        #expect(actual.count == expected.count)

        for (actualValue, expectedValue) in zip(actual, expected) {
            expectTimestamp(actualValue, equals: expectedValue)
        }
    }

    private func expectTimestamp(_ actual: Double, equals expected: Double) {
        #expect(abs(actual - expected) < 0.000_001)
    }

    private func makeLyrics(_ syncedLyrics: String) -> Lyrics {
        Lyrics(
            id: 1,
            trackName: "Track",
            artistName: "Artist",
            albumName: nil,
            duration: 0,
            instrumental: false,
            plainLyrics: nil,
            syncedLyrics: syncedLyrics
        )
    }
}
