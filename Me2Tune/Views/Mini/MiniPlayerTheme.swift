//
//  MiniPlayerTheme.swift
//  Me2Tune
//
//  Mini 模式专用配色 - 深色紧凑主题
//

import SwiftUI

struct MiniPlayerTheme: Theme {
    let name = "Mini Player"
    
    let colors = ThemeColors(
        // MARK: Accent Colors
        
        accent: Color(hex: "#00E5FF").opacity(0.9),
        accentGlow: Color(hex: "#00E5FF").opacity(0.5),
        accentLight: Color(hex: "#00E5FF").opacity(0.08),
        
        // MARK: Album Glow Colors (未使用)
        
        albumGlowColors: [],
        defaultAlbumGlow: .clear,
        
        // MARK: Background Colors
        
        mainBackground: Color(hex: "#0A0A0A"),
        gradientTop: Color(hex: "#121212"),
        containerBackground: Color(hex: "#1A1A1A").opacity(0.95),
        controlBackground: Color(hex: "#1F1F1F").opacity(0.9),
        infoBackground: .clear,
        
        // MARK: Interactive States
        
        hoverBackground: Color.white.opacity(0.08),
        selectedBackground: .clear,
        
        // MARK: Text Colors
        
        primaryText: Color(hex: "#DEDEDE"),
        secondaryText: Color(hex: "#838383"),
        tertiaryText: Color.gray.opacity(0.8),
        disabledText: Color.gray.opacity(0.3),
        
        // MARK: UI Elements
        
        playButtonBackground: Color(hex: "#EBEBEB"),
        playButtonIconColor: Color(hex: "#0A0A0A"),
        emptyStateIcon: .clear,
        controlButtonColor: Color.white.opacity(0.65),
        timeDisplayColor: Color.white.opacity(0.6),
        
        // MARK: Border Colors
        
        borderGradientStart: .clear,
        borderGradientEnd: .clear,
        
        // MARK: Search Colors (未使用)
        
        searchOverlayBackground: .clear,
        searchOverlayStroke: .clear,
        searchInputText: .clear,
        searchPrimaryText: .clear,
        searchSecondaryText: .clear,
        searchIconColor: .clear
    )
}
