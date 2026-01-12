//
//  EmeraldTheme.swift
//  Me2Tune
//
//  明亮主题 - 清新明亮的浅色调配绿色强调
//

import SwiftUI

struct EmeraldTheme: Theme {
    let name = "Emerald"

    let colors = ThemeColors(
        // MARK: Accent Colors

        accent: Color(hex: "#10B981"),
        accentGlow: Color(hex: "#10B981").opacity(0.48),
        accentLight: Color(hex: "#10B981").opacity(0.09),

        // MARK: Album Glow Colors

        albumGlowColors: [
            Color(hex: "#FF6B6B"),
            Color(hex: "#FF9F43"),
            Color(hex: "#FECA57"),
            Color(hex: "#48DBFB"),
            Color(hex: "#2E86DE"),
            Color(hex: "#9B59B6"),
            Color(hex: "#FF3366"),
            Color(hex: "#00D2D3"),
            Color(hex: "#5F27CD"),
        ],
        defaultAlbumGlow: Color(hex: "#FF9F43"),

        // MARK: Background Colors

        mainBackground: Color(hex: "#111827"),
        gradientTop: Color(hex: "#0B0F19"),
        containerBackground: Color(hex: "#131C1A").opacity(0.1),
        controlBackground: Color(hex: "#1F2937").opacity(0.9),
        infoBackground: Color(hex: "#FFFFFF").opacity(0.06),

        // MARK: Interactive States

        hoverBackground: Color(hex: "#FFFFFF").opacity(0.05),
        selectedBackground: Color(hex: "#FFFFFF").opacity(0.04),

        // MARK: Text Colors

        primaryText: Color(hex: "#E5E7EB"),
        secondaryText: Color(hex: "#9CA3AF"),
        tertiaryText: Color(hex: "#6B7280").opacity(0.78),
        disabledText: Color(hex: "#4B5563").opacity(0.48),

        // MARK: UI Elements

        playButtonBackground: Color(hex: "#F48A13"),
        playButtonIconColor: Color(hex: "#FFFFFF"),
        emptyStateIcon: Color(hex: "#6B7280").opacity(0.5),
        controlButtonColor: Color(hex: "#D1D5DB").opacity(0.74),
        timeDisplayColor: Color(hex: "#D1D5DB").opacity(0.84),

        // MARK: Border Colors

        borderGradientStart: Color(hex: "#10B981").opacity(0.3),
        borderGradientEnd: Color(hex: "#10B981").opacity(0.0),

        // MARK: Search Colors

        searchOverlayBackground: Color(hex: "#1A202C").opacity(0.93),
        searchOverlayStroke: Color(hex: "#10B981").opacity(0.4),
        searchInputText: Color(hex: "#E5E7EB"),
        searchPrimaryText: Color(hex: "#E5E7EB"),
        searchSecondaryText: Color(hex: "#9CA3AF"),
        searchIconColor: Color(hex: "#10B981").opacity(0.87)
    )
}
