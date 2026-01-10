//
//  LanguageManager.swift
//  Me2Tune
//
//  语言管理器 - 语言切换 + 持久化
//

import Combine
import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "me2.Me2Tune", category: "Language")

@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    
    @Published private(set) var currentLanguage: AppLanguage
    
    enum AppLanguage: String, CaseIterable, Identifiable {
        case english = "en"
        case simplifiedChinese = "zh-Hans"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .english:
                return "English"
            case .simplifiedChinese:
                return "简体中文"
            }
        }
    }
    
    private let userDefaults = UserDefaults.standard
    private let languageKey = "AppLanguage"
    
    private init() {
        // 加载保存的语言设置
        if let savedLanguage = userDefaults.string(forKey: languageKey),
           let language = AppLanguage(rawValue: savedLanguage)
        {
            self.currentLanguage = language
        } else {
            // 默认使用系统语言
            let systemLanguage = Locale.current.language.languageCode?.identifier ?? "en"
            self.currentLanguage = systemLanguage.hasPrefix("zh") ? .simplifiedChinese : .english
        }
        
        logger.info("Language initialized: \(self.currentLanguage.displayName)")
    }
    
    // MARK: - Public Methods
    
    func setLanguage(_ language: AppLanguage) {
        guard language != currentLanguage else { return }
        
        currentLanguage = language
        userDefaults.set(language.rawValue, forKey: languageKey)
        
        // 更新 UserDefaults 的 AppleLanguages
        userDefaults.set([language.rawValue], forKey: "AppleLanguages")
        userDefaults.synchronize()
        
        logger.info("Language changed to: \(language.displayName)")
    }
}
