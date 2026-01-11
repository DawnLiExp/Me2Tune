//
//  LightTheme.swift
//  Me2Tune
//
//  暖沙主题 - 温暖舒适的浅色调
//

import SwiftUI

struct LightTheme: Theme {
    let name = "Warm Sand"

    let colors = ThemeColors(
        // MARK: Accent Colors

        accent: Color(hex: "#D84315"),
        accentGlow: Color(hex: "#D84315").opacity(0.4),
        accentLight: Color(hex: "#D84315").opacity(0.08),

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

        mainBackground: Color(hex: "#F5F1EA"),
        gradientTop: Color(hex: "#EDE7DD"),
        containerBackground: Color(hex: "#FFFFFF").opacity(0.75),
        controlBackground: Color(hex: "#FAFAF8").opacity(0.92),
        infoBackground: Color(hex: "#000000").opacity(0.04),

        // MARK: Interactive States

        hoverBackground: Color(hex: "#000000").opacity(0.04),
        selectedBackground: Color(hex: "#000000").opacity(0.06),

        // MARK: Text Colors

        primaryText: Color(hex: "#3E2723"),
        secondaryText: Color(hex: "#6D4C41"),
        tertiaryText: Color(hex: "#8D6E63").opacity(0.75),
        disabledText: Color(hex: "#A1887F").opacity(0.4),

        // MARK: UI Elements

        playButtonBackground: Color(hex: "#D84315"),
        playButtonIconColor: Color(hex: "#FFFFFF"), 
        emptyStateIcon: Color(hex: "#A1887F").opacity(0.45),
        controlButtonColor: Color.black.opacity(0.7),
        timeDisplayColor: Color.black.opacity(0.8),

        // MARK: Border Colors

        borderGradientStart: Color(hex: "#D84315").opacity(0.25),
        borderGradientEnd: Color(hex: "#D84315").opacity(0.0),

        // MARK: Search Colors

        searchOverlayBackground: Color(hex: "#3E2723").opacity(0.88),
        searchOverlayStroke: Color(hex: "#D84315").opacity(0.35),
        searchInputText: Color(hex: "#F5EDE7"),
        searchPrimaryText: Color(hex: "#EDE7DD"),
        searchSecondaryText: Color(hex: "#BCAAA0"),
        searchIconColor: Color(hex: "#D84315").opacity(0.9)
    )
}
