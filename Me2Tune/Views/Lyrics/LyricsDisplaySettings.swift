//
//  LyricsDisplaySettings.swift
//  Me2Tune
//
//  Lyrics display preferences and derived rendering values.
//

import CoreGraphics

enum LyricsDisplaySettingsKey {
    static let highlightSize = "lyricsHighlightSize"
    static let normalSize = "lyricsNormalSize"
    static let translationOffset = "lyricsTranslationOffset"
    static let highlightIntensity = "lyricsHighlightIntensity"
    static let lineSpacing = "lyricsLineSpacing"
    static let timeOffset = "lyricsTimeOffset"
}

enum LyricsHighlightSize: String, CaseIterable, Identifiable {
    case s14 = "14"
    case s16 = "16"
    case s18 = "18"
    case s20 = "20"
    case s22 = "22"
    case s24 = "24"

    var id: String {
        rawValue
    }

    var fontSize: CGFloat {
        switch self {
        case .s14: 14
        case .s16: 16
        case .s18: 18
        case .s20: 20
        case .s22: 22
        case .s24: 24
        }
    }
}

enum LyricsNormalSize: String, CaseIterable, Identifiable {
    case s12 = "12"
    case s13 = "13"
    case s14 = "14"
    case s15 = "15"
    case s16 = "16"
    case s17 = "17"

    var id: String {
        rawValue
    }

    var fontSize: CGFloat {
        switch self {
        case .s12: 12
        case .s13: 13
        case .s14: 14
        case .s15: 15
        case .s16: 16
        case .s17: 17
        }
    }
}

enum LyricsTranslationOffset: String, CaseIterable, Identifiable {
    case minus1 = "-1"
    case zero = "0"
    case plus1 = "+1"

    var id: String {
        rawValue
    }

    var fontOffset: CGFloat {
        switch self {
        case .minus1: -1
        case .zero: 0
        case .plus1: 1
        }
    }
}

enum LyricsHighlightIntensity: String, CaseIterable, Identifiable {
    case gentle
    case standard
    case dramatic

    var id: String {
        rawValue
    }

    func opacity(for distance: Int) -> Double {
        switch (self, distance) {
        case (_, 0):
            1.0
        case (.gentle, 1 ... 2):
            0.9
        case (.gentle, 3 ... 4):
            0.75
        case (.gentle, 5 ... 6):
            0.58
        case (.gentle, 7 ... 8):
            0.43
        case (.gentle, _):
            0.33
        case (.standard, 1 ... 2):
            0.85
        case (.standard, 3 ... 4):
            0.6
        case (.standard, 5 ... 6):
            0.4
        case (.standard, 7 ... 8):
            0.25
        case (.standard, _):
            0.18
        case (.dramatic, 1 ... 2):
            0.65
        case (.dramatic, 3 ... 4):
            0.28
        case (.dramatic, 5 ... 6):
            0.13
        case (.dramatic, 7 ... 8):
            0.07
        case (.dramatic, _):
            0.05
        }
    }
}

enum LyricsTimeOffset: String, CaseIterable, Identifiable {
    case minus1_5 = "-1.5"
    case minus1_0 = "-1.0"
    case minus0_5 = "-0.5"
    case zero = "0.0"
    case plus0_5 = "+0.5"
    case plus1_0 = "+1.0"
    case plus1_5 = "+1.5"

    var id: String {
        rawValue
    }

    var offsetValue: Double {
        switch self {
        case .minus1_5: -1.5
        case .minus1_0: -1.0
        case .minus0_5: -0.5
        case .zero: 0.0
        case .plus0_5: 0.5
        case .plus1_0: 1.0
        case .plus1_5: 1.5
        }
    }
}

enum LyricsLineSpacing: String, CaseIterable, Identifiable {
    case compact
    case normal
    case relaxed

    var id: String {
        rawValue
    }

    var spacingValue: CGFloat {
        switch self {
        case .compact: 4
        case .normal: 8
        case .relaxed: 14
        }
    }
}

struct LyricsDisplaySettings {
    let highlightSize: LyricsHighlightSize
    let normalSize: LyricsNormalSize
    let translationOffset: LyricsTranslationOffset
    let highlightIntensity: LyricsHighlightIntensity
    let lineSpacing: LyricsLineSpacing
    let timeOffset: LyricsTimeOffset

    init(
        highlightSizeRaw: String,
        normalSizeRaw: String,
        translationOffsetRaw: String,
        highlightIntensityRaw: String,
        lineSpacingRaw: String,
        timeOffsetRaw: String
    ) {
        highlightSize = LyricsHighlightSize(rawValue: highlightSizeRaw) ?? .s18
        normalSize = LyricsNormalSize(rawValue: normalSizeRaw) ?? .s15
        translationOffset = LyricsTranslationOffset(rawValue: translationOffsetRaw) ?? .minus1
        highlightIntensity = LyricsHighlightIntensity(rawValue: highlightIntensityRaw) ?? .standard
        lineSpacing = LyricsLineSpacing(rawValue: lineSpacingRaw) ?? .normal
        timeOffset = LyricsTimeOffset(rawValue: timeOffsetRaw) ?? .zero
    }

    func mainFontSize(isCurrent: Bool) -> CGFloat {
        if isCurrent {
            highlightSize.fontSize
        } else {
            normalSize.fontSize
        }
    }

    func translationFontSize(isCurrent: Bool) -> CGFloat {
        let baseSize = mainFontSize(isCurrent: isCurrent)
        return max(baseSize + translationOffset.fontOffset, 10)
    }

    func opacity(distance: Int) -> Double {
        highlightIntensity.opacity(for: distance)
    }

    var blockVerticalPadding: CGFloat {
        lineSpacing.spacingValue
    }

    var plainTextFontSize: CGFloat {
        normalSize.fontSize
    }

    var plainTextLineSpacing: CGFloat {
        lineSpacing.spacingValue
    }
}
