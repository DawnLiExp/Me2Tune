//
//  ColorExtensions.swift
//  Me2Tune
//
//  颜色扩展 - 统一配色管理
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

// MARK: - App Color Palette

extension Color {
    // MARK: Accent Colors
    
    /// 主强调色 - 青色 (#00E5FF)
    static let accent = Color(hex: "#00E5FF")
    
    /// 强调色光晕
    static let accentGlow = accent.opacity(0.5)
    
    /// 强调色浅色版（用于背景）
    static let accentLight = accent.opacity(0.08)
    
    // MARK: Album Glow Colors
    
    /// 专辑光晕颜色集合（用于封面切换时的背景光效）
    static let albumGlowColors: [Color] = [
        Color(hex: "#E20764"),
        Color(hex: "#9D4EDD"),
        Color(hex: "#FF4466"),
        Color(hex: "#D55C10"),
        Color(hex: "#CF9810"),
        Color(hex: "#FF3BA7"),
        Color(hex: "#33CCFF"),
        Color(hex: "#0063DC"),
        Color(hex: "#00FFA3"),
    ]
    
    /// 默认专辑光晕色
    static let defaultAlbumGlow = Color(hex: "#FF4466")
    
    // MARK: Background Colors
    
    /// 主背景
    static let mainBackground = Color.black
    
    /// 顶部渐变背景（起始色）
    static let gradientTop = Color(white: 0.02)
    
    /// 容器背景（半透明玻璃态）
    static let containerBackground = Color.white.opacity(0.05)
    
    /// 控制面板背景
    static let controlBackground = Color(white: 0.12).opacity(0.85)
    
    /// 信息栏背景
    static let infoBackground = Color.white.opacity(0.08)
    
    // MARK: Interactive States
    
    /// Hover 背景色
    static let hoverBackground = Color.white.opacity(0.05)
    
    /// 选中背景色（浅色）
    static let selectedBackground = Color.white.opacity(0.03)
    
    // MARK: Text Colors
    
    /// 主文本（白色）
    static let primaryText = Color.white
    
    /// 次要文本（灰色）
    static let secondaryText = Color.gray
    
    /// 三级文本（更浅灰）
    static let tertiaryText = Color.gray.opacity(0.7)
    
    /// 禁用文本
    static let disabledText = Color.gray.opacity(0.3)
    
    // MARK: Icon Colors
    
    /// 空状态图标
    static let emptyStateIcon = Color.gray.opacity(0.5)
    
    // MARK: Border Colors
    
    /// 容器边框渐变（强调色）
    static let borderGradientStart = accent.opacity(0.3)
    static let borderGradientEnd = accent.opacity(0.0)
}
