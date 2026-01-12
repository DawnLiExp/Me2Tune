//
//  ThemeManager.swift
//  Me2Tune
//
//  主题管理器 - 启动时应用主题 + 持久化
//

import Combine
import Foundation
import OSLog
import SwiftUI

private let logger = Logger.theme

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published private(set) var currentTheme: Theme
    @Published var themeMode: ThemeMode = .auto
    
    enum ThemeMode: String, CaseIterable, Identifiable {
        case auto
        case dark
        case slateBlue
        case emerald
        
        var id: String { rawValue }
        
        var displayName: LocalizedStringKey {
            switch self {
            case .auto:
                return "theme_auto"
            case .dark:
                return "theme_dark"
            case .slateBlue:
                return "theme_slate_blue"
            case .emerald:
                return "theme_emerald"
            }
        }
    }
    
    private let userDefaults = UserDefaults.standard
    private let themeModeKey = "ThemeMode"
    
    private let availableThemes: [Theme] = [
        DarkTheme(),
        SlateBlueTheme(),
        EmeraldTheme()
    ]
    
    private init() {
        // 加载保存的主题模式
        let savedMode: ThemeMode = if let modeString = userDefaults.string(forKey: themeModeKey),
                                      let mode = ThemeMode(rawValue: modeString)
        {
            mode
        } else {
            .auto
        }
        
        self.themeMode = savedMode
        
        // 启动时根据模式应用主题
        switch savedMode {
        case .auto:
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            self.currentTheme = isDark ? DarkTheme() : SlateBlueTheme()
        case .dark:
            self.currentTheme = DarkTheme()
        case .slateBlue:
            self.currentTheme = SlateBlueTheme()
        case .emerald:
            self.currentTheme = EmeraldTheme()
        }
        
        logger.info("ThemeManager initialized with mode: \(self.themeMode.rawValue), theme: \(self.currentTheme.name)")
    }
    
    // MARK: - Public Methods
    
    func setThemeMode(_ mode: ThemeMode) {
        themeMode = mode
        userDefaults.set(mode.rawValue, forKey: themeModeKey)
        
        logger.info("Theme mode saved: \(mode.rawValue), will apply on next launch")
    }
}
