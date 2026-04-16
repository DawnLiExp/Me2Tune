//
//  LyricsDisplaySettingsTests.swift
//  Me2TuneTests
//

import CoreGraphics
import Testing
@testable import Me2Tune

@MainActor
@Suite("LyricsDisplaySettings 单元测试")
struct LyricsDisplaySettingsTests {
    @Test("非法 rawValue 回退到默认值")
    func fallsBackToDefaultsForInvalidRawValues() {
        let settings = LyricsDisplaySettings(
            highlightSizeRaw: "999",
            normalSizeRaw: "999",
            translationOffsetRaw: "999",
            highlightIntensityRaw: "unknown",
            lineSpacingRaw: "unknown",
            timeOffsetRaw: "invalid"
        )

        #expect(settings.highlightSize == .s18)
        #expect(settings.normalSize == .s15)
        #expect(settings.translationOffset == .minus1)
        #expect(settings.highlightIntensity == .standard)
        #expect(settings.lineSpacing == .normal)
        #expect(settings.timeOffset == .zero)
    }

    @Test("standard 透明度曲线匹配现有实现")
    func standardOpacityMatchesCurrentBehavior() {
        let settings = LyricsDisplaySettings(
            highlightSizeRaw: LyricsHighlightSize.s18.rawValue,
            normalSizeRaw: LyricsNormalSize.s15.rawValue,
            translationOffsetRaw: LyricsTranslationOffset.minus1.rawValue,
            highlightIntensityRaw: LyricsHighlightIntensity.standard.rawValue,
            lineSpacingRaw: LyricsLineSpacing.normal.rawValue,
            timeOffsetRaw: LyricsTimeOffset.zero.rawValue
        )

        #expect(settings.opacity(distance: 0) == 1.0)
        #expect(settings.opacity(distance: 1) == 0.85)
        #expect(settings.opacity(distance: 2) == 0.85)
        #expect(settings.opacity(distance: 3) == 0.6)
        #expect(settings.opacity(distance: 5) == 0.4)
        #expect(settings.opacity(distance: 7) == 0.25)
        #expect(settings.opacity(distance: 12) == 0.18)
    }

    @Test("主文和译文字号映射正确")
    func resolvesMainAndTranslationFontSizes() {
        let settings = LyricsDisplaySettings(
            highlightSizeRaw: LyricsHighlightSize.s22.rawValue,
            normalSizeRaw: LyricsNormalSize.s13.rawValue,
            translationOffsetRaw: LyricsTranslationOffset.plus1.rawValue,
            highlightIntensityRaw: LyricsHighlightIntensity.gentle.rawValue,
            lineSpacingRaw: LyricsLineSpacing.relaxed.rawValue,
            timeOffsetRaw: LyricsTimeOffset.zero.rawValue
        )

        #expect(settings.mainFontSize(isCurrent: true) == CGFloat(22))
        #expect(settings.mainFontSize(isCurrent: false) == CGFloat(13))
        #expect(settings.translationFontSize(isCurrent: true) == CGFloat(23))
        #expect(settings.translationFontSize(isCurrent: false) == CGFloat(14))
    }

    @Test("译文偏移下限保护生效")
    func translationFontSizeHonorsLowerBound() {
        let settings = LyricsDisplaySettings(
            highlightSizeRaw: LyricsHighlightSize.s14.rawValue,
            normalSizeRaw: LyricsNormalSize.s12.rawValue,
            translationOffsetRaw: LyricsTranslationOffset.minus1.rawValue,
            highlightIntensityRaw: LyricsHighlightIntensity.standard.rawValue,
            lineSpacingRaw: LyricsLineSpacing.compact.rawValue,
            timeOffsetRaw: LyricsTimeOffset.zero.rawValue
        )

        #expect(settings.translationFontSize(isCurrent: false) == CGFloat(11))

        let clampedSettings = LyricsDisplaySettings(
            highlightSizeRaw: LyricsHighlightSize.s14.rawValue,
            normalSizeRaw: LyricsNormalSize.s12.rawValue,
            translationOffsetRaw: "-99",
            highlightIntensityRaw: LyricsHighlightIntensity.standard.rawValue,
            lineSpacingRaw: LyricsLineSpacing.compact.rawValue,
            timeOffsetRaw: LyricsTimeOffset.zero.rawValue
        )

        #expect(clampedSettings.translationFontSize(isCurrent: false) == CGFloat(11))
    }

    // MARK: - LyricsTimeOffset 枚举映射完整性 (属性 1)

    /// **Validates: Requirements 2.2, 2.3**
    @Test("LyricsTimeOffset 枚举包含 7 个档位")
    func timeOffsetAllCasesCountIsSeven() {
        #expect(LyricsTimeOffset.allCases.count == 7)
    }

    /// **Validates: Requirements 2.2, 2.3**
    @Test("LyricsTimeOffset offsetValue 值集合匹配预期")
    func timeOffsetValuesMatchExpected() {
        let expected: [Double] = [-1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5]
        let actual = LyricsTimeOffset.allCases.map(\.offsetValue)
        #expect(actual == expected)
    }

    /// **Validates: Requirements 2.2, 2.3**
    @Test("无效 timeOffsetRaw 回退到 .zero（offsetValue == 0.0）")
    func invalidTimeOffsetRawFallsBackToZero() {
        for invalidRaw in ["abc", "2.0", "", "null", "1.5", "-2.0"] {
            let settings = LyricsDisplaySettings(
                highlightSizeRaw: LyricsHighlightSize.s18.rawValue,
                normalSizeRaw: LyricsNormalSize.s15.rawValue,
                translationOffsetRaw: LyricsTranslationOffset.minus1.rawValue,
                highlightIntensityRaw: LyricsHighlightIntensity.standard.rawValue,
                lineSpacingRaw: LyricsLineSpacing.normal.rawValue,
                timeOffsetRaw: invalidRaw
            )
            #expect(settings.timeOffset == .zero, "rawValue \"\(invalidRaw)\" should fall back to .zero")
            #expect(settings.timeOffset.offsetValue == 0.0, "rawValue \"\(invalidRaw)\" offsetValue should be 0.0")
        }
    }

    @Test("纯文本歌词使用非当前行字号和所选行间距")
    func plainLyricsUsesNormalSizeAndSelectedSpacing() {
        let settings = LyricsDisplaySettings(
            highlightSizeRaw: LyricsHighlightSize.s24.rawValue,
            normalSizeRaw: LyricsNormalSize.s16.rawValue,
            translationOffsetRaw: LyricsTranslationOffset.zero.rawValue,
            highlightIntensityRaw: LyricsHighlightIntensity.dramatic.rawValue,
            lineSpacingRaw: LyricsLineSpacing.relaxed.rawValue,
            timeOffsetRaw: LyricsTimeOffset.zero.rawValue
        )

        #expect(settings.plainTextFontSize == CGFloat(16))
        #expect(settings.plainTextLineSpacing == CGFloat(14))
        #expect(settings.blockVerticalPadding == CGFloat(14))
    }
}
