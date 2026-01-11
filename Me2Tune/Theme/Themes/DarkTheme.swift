//
//  DarkTheme.swift
//  Me2Tune
//
//  暗色主题（当前默认配色）
//

import SwiftUI

struct DarkTheme: Theme {
    let name = "Dark"

    let colors = ThemeColors(
        // MARK: Accent Colors

        accent: Color(hex: "#00E5FF"),
        accentGlow: Color(hex: "#00E5FF").opacity(0.5),
        accentLight: Color(hex: "#00E5FF").opacity(0.08),

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

        mainBackground: .black,
        gradientTop: Color(white: 0.02),
        containerBackground: Color.white.opacity(0.05),
        controlBackground: Color(white: 0.12).opacity(0.85),
        infoBackground: Color.white.opacity(0.08),

        // MARK: Interactive States

        hoverBackground: Color.white.opacity(0.05),
        selectedBackground: Color.white.opacity(0.03),

        // MARK: Text Colors

        primaryText: Color(hex: "#E0E0E0"),
        secondaryText: .gray,
        tertiaryText: Color.gray.opacity(0.7),
        disabledText: Color.gray.opacity(0.3),

        // MARK: UI Elements

        playButtonBackground: Color(hex: "#EBEBEB"),
        emptyStateIcon: Color.gray.opacity(0.5),
        controlButtonColor: Color.white.opacity(0.7), // 暗色主题：浅色按钮
        timeDisplayColor: Color.white.opacity(0.8), // 暗色主题：浅色时间

        // MARK: Border Colors

        borderGradientStart: Color(hex: "#00E5FF").opacity(0.3),
        borderGradientEnd: Color(hex: "#00E5FF").opacity(0.0),

        // MARK: Search Colors

        searchOverlayBackground: Color(hex: "#1A1B1F").opacity(0.85),
        searchOverlayStroke: Color(hex: "#00E5FF").opacity(0.4)
    )
}
