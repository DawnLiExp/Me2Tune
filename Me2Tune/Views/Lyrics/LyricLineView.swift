//
//  LyricLineView.swift
//  Me2Tune
//
//  Single synced lyric line rendering.
//

import SwiftUI

struct LyricLineView: View {
    let line: LyricLine
    let lineIndex: Int
    let currentLineIndex: Int?
    let displaySettings: LyricsDisplaySettings
    let theme: ThemeColors
    
    private var isCurrent: Bool {
        guard let current = currentLineIndex else { return false }
        return lineIndex == current
    }
    
    private var isPassed: Bool {
        guard let current = currentLineIndex else { return false }
        return lineIndex < current
    }
    
    private var distanceFromCurrent: Int {
        guard let current = currentLineIndex else { return 0 }
        return abs(lineIndex - current)
    }
    
    private var distanceOpacity: Double {
        displaySettings.opacity(distance: distanceFromCurrent)
    }
    
    private var primaryTextColor: Color {
        if isCurrent {
            return theme.accent
        } else if isPassed {
            return theme.primaryText.opacity(0.7)
        } else {
            return theme.secondaryText.opacity(0.8)
        }
    }
    
    private var translationTextColor: Color {
        if isCurrent {
            return theme.accent.opacity(0.75)
        } else if isPassed {
            return theme.primaryText.opacity(0.55)
        } else {
            return theme.secondaryText.opacity(0.65)
        }
    }

    private var hasTranslation: Bool {
        guard let translation = line.translation else { return false }
        return !translation.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text(line.text.isEmpty ? "♪" : line.text)
                .font(.system(
                    size: displaySettings.reservedMainFontSize,
                    weight: isCurrent ? .semibold : .regular
                ))
                .foregroundColor(primaryTextColor)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .scaleEffect(displaySettings.mainTextScale(isCurrent: isCurrent), anchor: .center)
                .frame(maxWidth: .infinity)
            
            if let translation = line.translation, !translation.isEmpty {
                Text(translation)
                    .font(.system(
                        size: displaySettings.reservedTranslationFontSize,
                        weight: .regular
                    ))
                    .foregroundColor(translationTextColor)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .scaleEffect(displaySettings.translationTextScale(isCurrent: isCurrent), anchor: .center)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(minHeight: displaySettings.lineBlockMinHeight(hasTranslation: hasTranslation))
        .opacity(distanceOpacity)
        .animation(.easeOut(duration: 0.22), value: isCurrent)
        .animation(.easeOut(duration: 0.22), value: distanceFromCurrent)
    }
}

#Preview {
    let settings = LyricsDisplaySettings(
        highlightSizeRaw: LyricsHighlightSize.s20.rawValue,
        normalSizeRaw: LyricsNormalSize.s16.rawValue,
        translationOffsetRaw: LyricsTranslationOffset.minus1.rawValue,
        highlightIntensityRaw: LyricsHighlightIntensity.standard.rawValue,
        lineSpacingRaw: LyricsLineSpacing.normal.rawValue,
        timeOffsetRaw: LyricsTimeOffset.zero.rawValue
    )

    VStack(spacing: 8) {
        LyricLineView(
            line: LyricLine(timestamp: 0, text: "The current line stays visually stable", translation: "Highlighted line preview"),
            lineIndex: 1,
            currentLineIndex: 1,
            displaySettings: settings,
            theme: DarkTheme().colors
        )

        LyricLineView(
            line: LyricLine(timestamp: 3, text: "A previous line scales down without relayout", translation: "Previous line preview"),
            lineIndex: 0,
            currentLineIndex: 1,
            displaySettings: settings,
            theme: DarkTheme().colors
        )
    }
    .padding(32)
    .background(DarkTheme().colors.mainBackground)
}
