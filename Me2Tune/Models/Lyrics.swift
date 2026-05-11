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
}

// MARK: - LRC 解析

struct LyricLine: Identifiable, Sendable {
    let id = UUID()
    let timestamp: TimeInterval
    let text: String
    /// 译文行（相同时间戳的第二行），nil 表示无双语
    let translation: String?
}

enum LRCTimestampParser {
    nonisolated private static var timestampDetectionRegex: NSRegularExpression? {
        try? NSRegularExpression(
            pattern: #"\[\d+:[0-5]\d(?:[.:,]\d{1,3})?\]"#,
            options: []
        )
    }

    nonisolated private static var timestampRegex: NSRegularExpression? {
        try? NSRegularExpression(
            pattern: #"\[(\d+):([0-5]\d)(?:[.:,](\d{1,3}))?\]\s*(.*)$"#,
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

    nonisolated static func parseLine(_ line: String) -> (timestamp: TimeInterval, text: String)? {
        guard let timestampRegex,
              let match = timestampRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 5,
              let minutesRange = Range(match.range(at: 1), in: line),
              let secondsRange = Range(match.range(at: 2), in: line),
              let textRange = Range(match.range(at: 4), in: line),
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

        let timestamp = TimeInterval(minutes * 60) + TimeInterval(seconds) + fraction
        let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)
        return (timestamp, text)
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

        // MARK: Step 1 - 原始解析为 (timestamp, text) 对
        struct RawLine {
            let timestamp: TimeInterval
            let text: String
        }

        var rawLines: [RawLine] = []
        let globalOffset = LRCTimestampParser.parseOffset(in: syncedLyrics)

        syncedLyrics.enumerateLines { line, _ in
            guard let parsedLine = LRCTimestampParser.parseLine(line) else {
                return
            }

            rawLines.append(RawLine(timestamp: parsedLine.timestamp + globalOffset, text: parsedLine.text))
        }

        rawLines.sort { $0.timestamp < $1.timestamp }

        // MARK: Step 2 - 合并相同时间戳的双语行
        var result: [LyricLine] = []
        var i = 0

        while i < rawLines.count {
            let current = rawLines[i]

            // 检查下一行是否时间戳相同（双语配对）
            if i + 1 < rawLines.count {
                let next = rawLines[i + 1]
                if next.timestamp == current.timestamp {
                    // 合并：当前行为主文本，下一行为译文
                    result.append(LyricLine(
                        timestamp: current.timestamp,
                        text: current.text,
                        translation: next.text.isEmpty ? nil : next.text
                    ))
                    i += 2
                    continue
                }
            }

            result.append(LyricLine(
                timestamp: current.timestamp,
                text: current.text,
                translation: nil
            ))
            i += 1
        }

        return result
    }
}
