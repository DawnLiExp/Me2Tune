//
//  SlateBlueTheme.swift
//  Me2Tune
//
//  石板蓝主题 - 适合白天使用的舒适灰蓝色调
//

import SwiftUI

struct SlateBlueTheme: Theme {
    let name = "Slate Blue"

    let colors = ThemeColors(
        // MARK: Accent Colors

        accent: Color(hex: "#4A9EFF"),
        accentGlow: Color(hex: "#4A9EFF").opacity(0.45),
        accentLight: Color(hex: "#4A9EFF").opacity(0.09),

        // MARK: Album Glow Colors

        albumGlowColors: [
            Color(hex: "#5FA7FF"),
            Color(hex: "#DB8DE1"),
            Color(hex: "#46EAFE"),
            Color(hex: "#A78BFA"),
            Color(hex: "#00C88D"),
            Color(hex: "#BFDBFE"),
            Color(hex: "#F0DBFF"),
            Color(hex: "#E44154"),
        ],
        defaultAlbumGlow: Color(hex: "#DB8DE1"),

        // MARK: Background Colors

        mainBackground: Color(hex: "#16171E"),
        gradientTop: Color(hex: "#111318"),
        containerBackground: Color.white.opacity(0.06),
        controlBackground: Color(hex: "#2A2D3A").opacity(0.88),
        infoBackground: Color.white.opacity(0.07),

        // MARK: Interactive States

        hoverBackground: Color.white.opacity(0.06),
        selectedBackground: Color.white.opacity(0.04),

        // MARK: Text Colors

        primaryText: Color(hex: "#E8EAED"),
        secondaryText: Color(hex: "#9BA3AF"),
        tertiaryText: Color(hex: "#6B7280").opacity(0.8),
        disabledText: Color(hex: "#4B5563").opacity(0.5),

        // MARK: UI Elements

        playButtonBackground: Color(hex: "#4A9EFF"),
        playButtonIconColor: Color.white,
        emptyStateIcon: Color(hex: "#6B7280").opacity(0.5),
        controlButtonColor: Color(hex: "#D1D5DB").opacity(0.75),
        timeDisplayColor: Color(hex: "#D1D5DB").opacity(0.85),

        // MARK: Border Colors

        borderGradientStart: Color(hex: "#4A9EFF").opacity(0.28),
        borderGradientEnd: Color(hex: "#4A9EFF").opacity(0.0),

        // MARK: Search Colors

        searchOverlayBackground: Color(hex: "#242731").opacity(0.92),
        searchOverlayStroke: Color(hex: "#4A9EFF").opacity(0.38),
        searchInputText: Color(hex: "#E8EAED"),
        searchPrimaryText: Color(hex: "#E8EAED"),
        searchSecondaryText: Color(hex: "#9BA3AF"),
        searchIconColor: Color(hex: "#4A9EFF").opacity(0.88)
    )
}
