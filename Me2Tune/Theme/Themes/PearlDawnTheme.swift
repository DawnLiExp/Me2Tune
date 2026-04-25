//
//  PearlDawnTheme.swift
//  Me2Tune
//
//  珠光晨曦
//

import SwiftUI

struct PearlDawnTheme: Theme {
    let name = "Pearl Dawn"

    let atmosphere = ThemeAtmosphere.airyLight

    let colors = ThemeColors(
        // MARK: Accent Colors

        accent: Color(hex: "#D95D39"),
        accentGlow: Color(hex: "#D95D39").opacity(0.22),
        accentLight: Color(hex: "#D95D39").opacity(0.12),

        // MARK: Album Glow Colors

        albumGlowColors: [
            Color(hex: "#F26B5E"),
            Color(hex: "#3A9AD9"),
            Color(hex: "#E6A83A"),
            Color(hex: "#8B5CF6"),
            Color(hex: "#00A896"),
            Color(hex: "#E85D75"),
            Color(hex: "#4F46E5"),
            Color(hex: "#2BB673"),
            Color(hex: "#F97316"),
        ],
        defaultAlbumGlow: Color(hex: "#F26B5E"),

        // MARK: Background Colors

        mainBackground: Color(hex: "#F6F7F2"),
        gradientTop: Color(hex: "#F1F4FF"),
        containerBackground: Color.white.opacity(0.68),
        controlBackground: Color.white.opacity(0.82),
        infoBackground: Color(hex: "#EEF4F2").opacity(0.76),

        // MARK: Interactive States

        hoverBackground: Color(hex: "#2F5D62").opacity(0.08),
        selectedBackground: Color(hex: "#D95D39").opacity(0.10),

        // MARK: Text Colors

        primaryText: Color(hex: "#172026"),
        secondaryText: Color(hex: "#52616B"),
        tertiaryText: Color(hex: "#7A8790").opacity(0.88),
        disabledText: Color(hex: "#AEB7BE").opacity(0.72),

        // MARK: UI Elements

        playButtonBackground: Color(hex: "#234E52"),
        playButtonIconColor: Color.white,
        emptyStateIcon: Color(hex: "#8A98A3").opacity(0.62),
        controlButtonColor: Color(hex: "#334155").opacity(0.82),
        timeDisplayColor: Color(hex: "#52616B").opacity(0.88),

        // MARK: Border Colors

        borderGradientStart: Color(hex: "#D95D39").opacity(0.20),
        borderGradientEnd: Color(hex: "#D95D39").opacity(0.0),

        // MARK: Search Colors

        searchOverlayBackground: Color.white.opacity(0.90),
        searchOverlayStroke: Color(hex: "#D95D39").opacity(0.24),
        searchInputText: Color(hex: "#172026"),
        searchPrimaryText: Color(hex: "#172026"),
        searchSecondaryText: Color(hex: "#52616B"),
        searchIconColor: Color(hex: "#D95D39").opacity(0.82)
    )
}
