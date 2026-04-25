//
//  Theme.swift
//  Me2Tune
//
//  主题协议 + 颜色定义
//

import SwiftUI

// MARK: - Theme Protocol

protocol Theme {
    var name: String { get }
    var colors: ThemeColors { get }
    var atmosphere: ThemeAtmosphere { get }
}

extension Theme {
    var atmosphere: ThemeAtmosphere {
        .standard
    }
}

// MARK: - Theme Colors

struct ThemeColors {
    // MARK: Accent Colors

    let accent: Color
    let accentGlow: Color
    let accentLight: Color

    // MARK: Album Glow Colors

    let albumGlowColors: [Color]
    let defaultAlbumGlow: Color

    // MARK: Background Colors

    let mainBackground: Color
    let gradientTop: Color
    let containerBackground: Color
    let controlBackground: Color
    let infoBackground: Color

    // MARK: Interactive States

    let hoverBackground: Color
    let selectedBackground: Color

    // MARK: Text Colors

    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let disabledText: Color

    // MARK: UI Elements

    let playButtonBackground: Color
    let playButtonIconColor: Color 
    let emptyStateIcon: Color
    let controlButtonColor: Color
    let timeDisplayColor: Color

    // MARK: Border Colors

    let borderGradientStart: Color
    let borderGradientEnd: Color

    // MARK: Search Colors

    let searchOverlayBackground: Color
    let searchOverlayStroke: Color
    let searchInputText: Color
    let searchPrimaryText: Color
    let searchSecondaryText: Color
    let searchIconColor: Color
}

// MARK: - Theme Atmosphere

struct ThemeAtmosphere {
    let legacyVinylGlowOpacityScale: Double
    let legacyPlaylistGlowOpacityScale: Double
    let meshBackgroundOpacityScale: Double
    let meshColorOpacityScale: Double
    let meshPulseScale: Double
    let meshIntensityScale: Double
    let meshBreathingAmplitudeScale: Double
}

extension ThemeAtmosphere {
    static let standard = ThemeAtmosphere(
        legacyVinylGlowOpacityScale: 1.0,
        legacyPlaylistGlowOpacityScale: 1.0,
        meshBackgroundOpacityScale: 1.0,
        meshColorOpacityScale: 1.0,
        meshPulseScale: 1.0,
        meshIntensityScale: 1.0,
        meshBreathingAmplitudeScale: 1.0
    )

    static let airyLight = ThemeAtmosphere(
        legacyVinylGlowOpacityScale: 0.28,
        legacyPlaylistGlowOpacityScale: 0.36,
        meshBackgroundOpacityScale: 0.42,
        meshColorOpacityScale: 0.30,
        meshPulseScale: 0.24,
        meshIntensityScale: 0.58,
        meshBreathingAmplitudeScale: 0.42
    )
}
