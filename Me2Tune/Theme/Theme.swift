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
