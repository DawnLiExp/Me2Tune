//
//  ColorExtensions.swift
//  Me2Tune
//
//  颜色扩展 - 统一配色管理（从 ThemeManager 动态读取）
//

import SwiftUI

// MARK: - Color Initialization

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

// MARK: - App Color Palette (动态读取 ThemeManager)

extension Color {
    // MARK: Accent Colors
    
    static var accent: Color {
        ThemeManager.shared.currentTheme.colors.accent
    }
    
    static var accentGlow: Color {
        ThemeManager.shared.currentTheme.colors.accentGlow
    }
    
    static var accentLight: Color {
        ThemeManager.shared.currentTheme.colors.accentLight
    }
    
    // MARK: Album Glow Colors
    
    static var albumGlowColors: [Color] {
        ThemeManager.shared.currentTheme.colors.albumGlowColors
    }
    
    static var defaultAlbumGlow: Color {
        ThemeManager.shared.currentTheme.colors.defaultAlbumGlow
    }
    
    // MARK: Background Colors
    
    static var mainBackground: Color {
        ThemeManager.shared.currentTheme.colors.mainBackground
    }
    
    static var gradientTop: Color {
        ThemeManager.shared.currentTheme.colors.gradientTop
    }
    
    static var containerBackground: Color {
        ThemeManager.shared.currentTheme.colors.containerBackground
    }
    
    static var controlBackground: Color {
        ThemeManager.shared.currentTheme.colors.controlBackground
    }
    
    static var infoBackground: Color {
        ThemeManager.shared.currentTheme.colors.infoBackground
    }
    
    // MARK: Interactive States
    
    static var hoverBackground: Color {
        ThemeManager.shared.currentTheme.colors.hoverBackground
    }
    
    static var selectedBackground: Color {
        ThemeManager.shared.currentTheme.colors.selectedBackground
    }
    
    // MARK: Text Colors
    
    static var primaryText: Color {
        ThemeManager.shared.currentTheme.colors.primaryText
    }
    
    static var secondaryText: Color {
        ThemeManager.shared.currentTheme.colors.secondaryText
    }
    
    static var tertiaryText: Color {
        ThemeManager.shared.currentTheme.colors.tertiaryText
    }
    
    static var disabledText: Color {
        ThemeManager.shared.currentTheme.colors.disabledText
    }
    
    static var playButtonBackground: Color {
        ThemeManager.shared.currentTheme.colors.playButtonBackground
    }
    
    // MARK: Icon Colors
    
    static var emptyStateIcon: Color {
        ThemeManager.shared.currentTheme.colors.emptyStateIcon
    }
    
    // MARK: Border Colors
    
    static var borderGradientStart: Color {
        ThemeManager.shared.currentTheme.colors.borderGradientStart
    }
    
    static var borderGradientEnd: Color {
        ThemeManager.shared.currentTheme.colors.borderGradientEnd
    }
}
