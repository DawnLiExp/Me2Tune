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
    let duration: Int
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
}

extension Lyrics {
    /// 解析同步歌词为时间轴数组
    func parseSyncedLyrics() -> [LyricLine] {
        guard let syncedLyrics, !syncedLyrics.isEmpty else {
            return []
        }

        var lines: [LyricLine] = []
        let pattern = #"\[(\d{2}):(\d{2})\.(\d{2})\]\s*(.*)$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])

        syncedLyrics.enumerateLines { line, _ in
            guard let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
                return
            }

            guard match.numberOfRanges == 5,
                  let minutesRange = Range(match.range(at: 1), in: line),
                  let secondsRange = Range(match.range(at: 2), in: line),
                  let centisecondsRange = Range(match.range(at: 3), in: line),
                  let textRange = Range(match.range(at: 4), in: line),
                  let minutes = Int(line[minutesRange]),
                  let seconds = Int(line[secondsRange]),
                  let centiseconds = Int(line[centisecondsRange])
            else {
                return
            }

            let timestamp = TimeInterval(minutes * 60) + TimeInterval(seconds) + TimeInterval(centiseconds) / 100.0
            let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)

            lines.append(LyricLine(timestamp: timestamp, text: text))
        }

        return lines.sorted { $0.timestamp < $1.timestamp }
    }
}
