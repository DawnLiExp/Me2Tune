//
//  ThemeManager.swift
//  Me2Tune
//
//  主题管理器 - 动态切换 + 持久化（预留 auto 模式）
//

import Combine
import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "me2.Me2Tune", category: "Theme")

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published private(set) var currentTheme: Theme
    
    private let persistenceService = PersistenceService()
    
    // MARK: - Available Themes
    
    private let availableThemes: [Theme] = [
        DarkTheme(),
        LightTheme()
    ]
    
    // MARK: - Initialization
    
    private init() {
        // 默认暗色主题
        self.currentTheme = DarkTheme()
        
        // TODO: 从持久化加载用户选择
        // TODO: 支持 auto 模式（跟随系统外观）
        
        logger.info("ThemeManager initialized with theme: \(self.currentTheme.name)")
    }
    
    // MARK: - Public Methods
    
    func switchTheme(to themeName: String) {
        guard let theme = availableThemes.first(where: { $0.name == themeName }) else {
            logger.warning("Theme not found: \(themeName)")
            return
        }
        
        currentTheme = theme
        
        // TODO: 保存用户选择到持久化
        
        logger.info("Switched to theme: \(theme.name)")
    }
    
    func getAvailableThemeNames() -> [String] {
        availableThemes.map(\.name)
    }
    
    // MARK: - TODO: Auto Mode
    
    // func enableAutoMode() {
    //     // 监听系统外观变化
    //     // NSApp.effectiveAppearance
    // }
}
