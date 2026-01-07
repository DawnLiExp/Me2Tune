//
//  LightTheme.swift
//  Me2Tune
//
//  亮色主题（基础框架，待完整设计）
//

import SwiftUI

struct LightTheme: Theme {
    let name = "Light"

    let colors = ThemeColors(
        // MARK: Accent Colors

        accent: Color(hex: "#0099CC"),
        accentGlow: Color(hex: "#0099CC").opacity(0.4),
        accentLight: Color(hex: "#0099CC").opacity(0.1),

        // MARK: Album Glow Colors

        albumGlowColors: [
            Color(hex: "#E20764"),
            Color(hex: "#9D4EDD"),
            Color(hex: "#FF4466"),
            Color(hex: "#D55C10"),
            Color(hex: "#CF9810"),
            Color(hex: "#FF3BA7"),
            Color(hex: "#33CCFF"),
            Color(hex: "#0066E5"),
            Color(hex: "#00FFA3"),
        ],
        defaultAlbumGlow: Color(hex: "#FF4466"),

        // MARK: Background Colors

        mainBackground: Color(white: 0.98),
        gradientTop: Color(white: 0.95),
        containerBackground: Color.white.opacity(0.8),
        controlBackground: Color.white.opacity(0.9),
        infoBackground: Color.black.opacity(0.05),

        // MARK: Interactive States

        hoverBackground: Color.black.opacity(0.05),
        selectedBackground: Color.black.opacity(0.08),

        // MARK: Text Colors

        primaryText: Color(hex: "#1A1A1A"),
        secondaryText: Color.gray,
        tertiaryText: Color.gray.opacity(0.6),
        disabledText: Color.gray.opacity(0.3),

        // MARK: UI Elements

        playButtonBackground: Color(hex: "#333333"),
        emptyStateIcon: Color.gray.opacity(0.4),

        // MARK: Border Colors

        borderGradientStart: Color(hex: "#0099CC").opacity(0.3),
        borderGradientEnd: Color(hex: "#00E5FF").opacity(0.0),

        // MARK: Search Colors

        searchOverlayBackground: Color(hex: "#1A1A1A").opacity(0.95),
        searchOverlayStroke: Color(hex: "#00E5FF").opacity(0.3)
    )
}
