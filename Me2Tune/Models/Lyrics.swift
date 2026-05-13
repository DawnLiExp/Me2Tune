//
//  Lyrics.swift
//  Me2Tune
//
//  歌词模型 - LRCLIB 数据结构
//

import Foundation

struct Lyrics: Codable, Sendable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Double
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?

    var hasLyrics: Bool {
        if instrumental {
            return false
        }
        return plainLyrics != nil || syncedLyrics != nil
    }

    var displayLyrics: String {
        if instrumental {
            return String(localized: "instrumental_track")
        }
        return syncedLyrics ?? plainLyrics ?? String(localized: "no_lyrics")
    }

    nonisolated static func fromText(
        _ text: String,
        trackName: String,
        artistName: String,
        albumName: String?,
        duration: TimeInterval
    ) -> Lyrics {
        let hasSyncedTags = LRCTimestampParser.containsTimestamp(in: text)

        return Lyrics(
            id: 0,
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            duration: duration,
            instrumental: false,
            plainLyrics: hasSyncedTags ? nil : text,
            syncedLyrics: hasSyncedTags ? text : nil
        )
    }
}

// MARK: - LRC 解析

struct LyricSegment: Equatable, Sendable {
    let timestamp: TimeInterval
    let text: String
}

struct LyricLine: Identifiable, Sendable {
    let id = UUID()
    let timestamp: TimeInterval
    let text: String
    let segments: [LyricSegment]
    /// 译文行（相同时间戳的第二行），nil 表示无双语
    let translation: String?

    init(
        timestamp: TimeInterval,
        text: String,
        translation: String?,
        segments: [LyricSegment] = []
    ) {
        self.timestamp = timestamp
        self.text = text
        self.translation = translation
        self.segments = segments
    }
}

extension LyricLine {
    func highlightedSegmentCount(
        at playbackTime: TimeInterval,
        offset: TimeInterval
    ) -> Int {
        guard !segments.isEmpty else { return 0 }

        let adjustedTime = playbackTime - offset
        var lowerBound = 0
        var upperBound = segments.count

        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            if segments[midpoint].timestamp <= adjustedTime {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        return lowerBound
    }

    func nextSegmentActivationTime(
        after playbackTime: TimeInterval,
        offset: TimeInterval
    ) -> TimeInterval? {
        let nextIndex = highlightedSegmentCount(at: playbackTime, offset: offset)
        guard nextIndex < segments.count else { return nil }
        return segments[nextIndex].timestamp + offset
    }
}

enum LRCTimestampParser {
    nonisolated private static var timestampDetectionRegex: NSRegularExpression? {
        try? NSRegularExpression(
            pattern: #"\[\d+:[0-5]\d(?:[.:,]\d{1,3})?\]"#,
            options: []
        )
    }

    nonisolated private static var timestampTokenRegex: NSRegularExpression? {
        try? NSRegularExpression(
            pattern: #"\[(\d+):([0-5]\d)(?:[.:,](\d{1,3}))?\]"#,
            options: []
        )
    }

    nonisolated private static var offsetRegex: NSRegularExpression? {
        try? NSRegularExpression(
            pattern: #"^\s*\[offset:\s*([+-]?\d+)\s*\]\s*$"#,
            options: [.caseInsensitive]
        )
    }

    nonisolated static func containsTimestamp(in content: String) -> Bool {
        guard let timestampDetectionRegex else { return false }

        return timestampDetectionRegex.firstMatch(
            in: content,
            range: NSRange(content.startIndex..., in: content)
        ) != nil
    }

    nonisolated static func parseLine(_ line: String) -> (
        timestamp: TimeInterval,
        text: String,
        segments: [LyricSegment]
    )? {
        guard let timestampTokenRegex else { return nil }

        let matches = timestampTokenRegex.matches(in: line, range: NSRange(line.startIndex..., in: line))
        guard let firstMatch = matches.first,
              let firstTimestamp = parseTimestamp(from: firstMatch, in: line)
        else {
            return nil
        }

        var timedTextSegments: [LyricSegment] = []

        for (index, match) in matches.enumerated() {
            guard let timestamp = parseTimestamp(from: match, in: line),
                  let matchRange = Range(match.range, in: line)
            else {
                continue
            }

            let textStart = matchRange.upperBound
            let textEnd: String.Index
            if index + 1 < matches.count,
               let nextRange = Range(matches[index + 1].range, in: line)
            {
                textEnd = nextRange.lowerBound
            } else {
                textEnd = line.endIndex
            }

            let text = String(line[textStart..<textEnd])
            if !text.isEmpty {
                timedTextSegments.append(LyricSegment(timestamp: timestamp, text: text))
            }
        }

        let text = timedTextSegments
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let segments = timedTextSegments.count > 1 ? timedTextSegments : []

        return (firstTimestamp, text, segments)
    }

    nonisolated private static func parseTimestamp(
        from match: NSTextCheckingResult,
        in line: String
    ) -> TimeInterval? {
        guard match.numberOfRanges == 4,
              let minutesRange = Range(match.range(at: 1), in: line),
              let secondsRange = Range(match.range(at: 2), in: line),
              let minutes = Int(line[minutesRange]),
              let seconds = Int(line[secondsRange])
        else {
            return nil
        }

        let fraction: TimeInterval
        if let fractionRange = Range(match.range(at: 3), in: line),
           let fractionValue = TimeInterval("0.\(line[fractionRange])")
        {
            fraction = fractionValue
        } else {
            fraction = 0
        }

        return TimeInterval(minutes * 60) + TimeInterval(seconds) + fraction
    }

    nonisolated static func parseOffset(in content: String) -> TimeInterval {
        guard let offsetRegex else { return 0 }

        var offset: TimeInterval = 0
        content.enumerateLines { line, stop in
            guard let match = offsetRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  match.numberOfRanges == 2,
                  let valueRange = Range(match.range(at: 1), in: line),
                  let milliseconds = Int(line[valueRange])
            else {
                return
            }

            offset = TimeInterval(milliseconds) / 1000.0
            stop = true
        }
        return offset
    }
}

extension Lyrics {
    /// 解析同步歌词为时间轴数组
    /// 支持双语：相同时间戳的连续两行自动合并为 text + translation
    func parseSyncedLyrics() -> [LyricLine] {
        guard let syncedLyrics, !syncedLyrics.isEmpty else {
            return []
        }

        struct RawLine {
            let timestamp: TimeInterval
            let text: String
            let segments: [LyricSegment]
            let sourceOrder: Int
        }

        var rawLines: [RawLine] = []
        let globalOffset = LRCTimestampParser.parseOffset(in: syncedLyrics)

        syncedLyrics.enumerateLines { line, _ in
            guard let parsedLine = LRCTimestampParser.parseLine(line) else {
                return
            }

            let segments = parsedLine.segments.map { segment in
                LyricSegment(timestamp: segment.timestamp + globalOffset, text: segment.text)
            }
            rawLines.append(RawLine(
                timestamp: parsedLine.timestamp + globalOffset,
                text: parsedLine.text,
                segments: segments,
                sourceOrder: rawLines.count
            ))
        }

        rawLines.sort { lhs, rhs in
            if abs(lhs.timestamp - rhs.timestamp) < 0.000_001 {
                return lhs.sourceOrder < rhs.sourceOrder
            }
            return lhs.timestamp < rhs.timestamp
        }

        var result: [LyricLine] = []
        var i = 0

        while i < rawLines.count {
            let current = rawLines[i]

            // 检查下一行是否时间戳相同（双语配对）
            if i + 1 < rawLines.count {
                let next = rawLines[i + 1]
                if abs(next.timestamp - current.timestamp) < 0.000_001 {
                    // 合并：当前行为主文本，下一行为译文
                    result.append(LyricLine(
                        timestamp: current.timestamp,
                        text: current.text,
                        translation: next.text.isEmpty ? nil : next.text,
                        segments: current.segments
                    ))
                    i += 2
                    continue
                }
            }

            result.append(LyricLine(
                timestamp: current.timestamp,
                text: current.text,
                translation: nil,
                segments: current.segments
            ))
            i += 1
        }

        return result
    }
}
