//
//  ThemeManager.swift
//  Me2Tune
//
//  主题管理器 - 动态切换 + 自动模式 + 持久化
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
    @Published var themeMode: ThemeMode = .auto
    
    enum ThemeMode: String, CaseIterable, Identifiable {
        case auto
        case dark
        case light
        
        var id: String { rawValue }
        
        var displayName: LocalizedStringKey {
            switch self {
            case .auto:
                return "theme_auto"
            case .dark:
                return "theme_dark"
            case .light:
                return "theme_light"
            }
        }
    }
    
    private let userDefaults = UserDefaults.standard
    private let themeModeKey = "ThemeMode"
    private var appearanceObserver: NSKeyValueObservation?
    
    private let availableThemes: [Theme] = [
        DarkTheme(),
        LightTheme()
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
        
        // 根据模式设置初始主题（内联计算，避免使用 self）
        switch savedMode {
        case .auto:
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            self.currentTheme = isDark ? DarkTheme() : LightTheme()
        case .dark:
            self.currentTheme = DarkTheme()
        case .light:
            self.currentTheme = LightTheme()
        }
        
        // 监听主题模式变化
        setupThemeModeObserver()
        
        // 如果是自动模式，监听系统外观
        if themeMode == .auto {
            setupAppearanceObserver()
        }
        
        logger.info("ThemeManager initialized with mode: \(self.themeMode.rawValue), theme: \(self.currentTheme.name)")
    }
    
    // MARK: - Public Methods
    
    func setThemeMode(_ mode: ThemeMode) {
        guard mode != themeMode else { return }
        
        themeMode = mode
        userDefaults.set(mode.rawValue, forKey: themeModeKey)
        
        // 移除旧的外观监听
        appearanceObserver?.invalidate()
        appearanceObserver = nil
        
        // 更新主题
        currentTheme = determineTheme(for: mode)
        
        // 如果是自动模式，设置监听
        if mode == .auto {
            setupAppearanceObserver()
        }
        
        logger.info("Theme mode changed to: \(mode.rawValue), current theme: \(self.currentTheme.name)")
    }
    
    // MARK: - Private Methods
    
    private func setupThemeModeObserver() {
        // 观察 themeMode 变化（用于其他地方直接修改 @Published 属性的情况）
        $themeMode
            .dropFirst() // 跳过初始值
            .sink { [weak self] newMode in
                guard let self else { return }
                self.userDefaults.set(newMode.rawValue, forKey: self.themeModeKey)
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func setupAppearanceObserver() {
        guard let app = NSApplication.shared as NSApplication? else { return }
        
        appearanceObserver = app.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.themeMode == .auto else { return }
                self.currentTheme = self.determineTheme(for: .auto)
                logger.debug("System appearance changed, switched to: \(self.currentTheme.name)")
            }
        }
    }
    
    private func determineTheme(for mode: ThemeMode) -> Theme {
        switch mode {
        case .auto:
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? DarkTheme() : LightTheme()
        case .dark:
            return DarkTheme()
        case .light:
            return LightTheme()
        }
    }
    
    deinit {
        appearanceObserver?.invalidate()
    }
}
