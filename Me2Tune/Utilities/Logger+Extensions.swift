//
//  Logger+Extensions.swift
//  Me2Tune
//
//  日志工具扩展 - 统一日志格式
//

import Foundation
import OSLog

nonisolated extension Logger {
    private static let subsystem = "me2.Me2Tune"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let player = Logger(subsystem: subsystem, category: "Player")
    static let viewModel = Logger(subsystem: subsystem, category: "ViewModel")
    static let collection = Logger(subsystem: subsystem, category: "Collection")
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    static let artwork = Logger(subsystem: subsystem, category: "Artwork")
    static let audio = Logger(subsystem: subsystem, category: "Audio")
    static let nowPlaying = Logger(subsystem: subsystem, category: "NowPlaying")
    static let remoteCommand = Logger(subsystem: subsystem, category: "RemoteCommand")
    static let theme = Logger(subsystem: subsystem, category: "Theme")
    static let language = Logger(subsystem: subsystem, category: "Language")
    static let lyrics = Logger(subsystem: subsystem, category: "Lyrics")
    static let cache = Logger(subsystem: subsystem, category: "Cache")
}

extension Logger {
    func logError(_ error: Error, context: String = "") {
        if let appError = error as? AppError {
            self.error("[\(context)] \(appError.localizedDescription)")
            if let suggestion = appError.recoverySuggestion {
                self.notice("Suggestion: \(suggestion)")
            }
        } else {
            self.error("[\(context)] \(error.localizedDescription)")
        }
    }

    func logPerformance(_ operation: String, duration: TimeInterval) {
        if duration > 0.1 {
            self.warning("⚠️ \(operation) took \(String(format: "%.2f", duration))s")
        } else {
            self.debug("✓ \(operation) completed in \(String(format: "%.3f", duration))s")
        }
    }
}
