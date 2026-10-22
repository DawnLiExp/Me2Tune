//
//  SettingsManager.swift
//  Me2Tune
//
//  集中管理窗口级持久化设置 - @Observable 存储属性，didSet 写入，init 读取
//

import Foundation
import Observation

enum LyricsDockingSpacing: String, CaseIterable, Sendable {
    case spaced
    case flush

    var gap: CGFloat { self == .spaced ? 6 : 0 }
}

@MainActor
@Observable
final class SettingsManager {
    static let shared = SettingsManager()
    @ObservationIgnored private let defaults: UserDefaults

    // MARK: - Keys

    private enum Key {
        static let miniAlwaysOnTop = "miniAlwaysOnTop"
        static let lyricsAlwaysOnTop = "lyricsAlwaysOnTop"
        static let lyricsDockingSpacing = "lyricsDockingSpacing"
    }

    // MARK: - Settings

    var miniAlwaysOnTop: Bool {
        didSet { defaults.set(miniAlwaysOnTop, forKey: Key.miniAlwaysOnTop) }
    }

    var lyricsAlwaysOnTop: Bool {
        didSet { defaults.set(lyricsAlwaysOnTop, forKey: Key.lyricsAlwaysOnTop) }
    }

    var lyricsDockingSpacing: LyricsDockingSpacing {
        didSet { defaults.set(lyricsDockingSpacing.rawValue, forKey: Key.lyricsDockingSpacing) }
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        miniAlwaysOnTop = defaults.bool(forKey: Key.miniAlwaysOnTop)
        lyricsAlwaysOnTop = defaults.bool(forKey: Key.lyricsAlwaysOnTop)
        lyricsDockingSpacing = LyricsDockingSpacing(rawValue: defaults.string(forKey: Key.lyricsDockingSpacing) ?? "") ?? .spaced
    }
}
