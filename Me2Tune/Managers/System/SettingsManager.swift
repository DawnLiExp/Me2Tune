//
//  SettingsManager.swift
//  Me2Tune
//
//  集中管理窗口级持久化设置 - @Observable 存储属性，didSet 写入，init 读取
//

import Foundation
import Observation

@MainActor
@Observable
final class SettingsManager {
    static let shared = SettingsManager()

    // MARK: - Keys

    private enum Key {
        static let miniAlwaysOnTop = "miniAlwaysOnTop"
        static let lyricsAlwaysOnTop = "lyricsAlwaysOnTop"
    }

    // MARK: - Settings

    var miniAlwaysOnTop: Bool {
        didSet { UserDefaults.standard.set(miniAlwaysOnTop, forKey: Key.miniAlwaysOnTop) }
    }

    var lyricsAlwaysOnTop: Bool {
        didSet { UserDefaults.standard.set(lyricsAlwaysOnTop, forKey: Key.lyricsAlwaysOnTop) }
    }

    // MARK: - Init

    private init() {
        miniAlwaysOnTop = UserDefaults.standard.bool(forKey: Key.miniAlwaysOnTop)
        lyricsAlwaysOnTop = UserDefaults.standard.bool(forKey: Key.lyricsAlwaysOnTop)
    }
}
