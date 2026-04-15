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
            lineSpacingRaw: "unknown"
        )

        #expect(settings.highlightSize == .s18)
        #expect(settings.normalSize == .s15)
        #expect(settings.translationOffset == .minus1)
        #expect(settings.highlightIntensity == .standard)
        #expect(settings.lineSpacing == .normal)
    }

    @Test("standard 透明度曲线匹配现有实现")
    func standardOpacityMatchesCurrentBehavior() {
        let settings = LyricsDisplaySettings(
            highlightSizeRaw: LyricsHighlightSize.s18.rawValue,
            normalSizeRaw: LyricsNormalSize.s15.rawValue,
            translationOffsetRaw: LyricsTranslationOffset.minus1.rawValue,
            highlightIntensityRaw: LyricsHighlightIntensity.standard.rawValue,
            lineSpacingRaw: LyricsLineSpacing.normal.rawValue
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
            lineSpacingRaw: LyricsLineSpacing.relaxed.rawValue
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
            lineSpacingRaw: LyricsLineSpacing.compact.rawValue
        )

        #expect(settings.translationFontSize(isCurrent: false) == CGFloat(11))

        let clampedSettings = LyricsDisplaySettings(
            highlightSizeRaw: LyricsHighlightSize.s14.rawValue,
            normalSizeRaw: LyricsNormalSize.s12.rawValue,
            translationOffsetRaw: "-99",
            highlightIntensityRaw: LyricsHighlightIntensity.standard.rawValue,
            lineSpacingRaw: LyricsLineSpacing.compact.rawValue
        )

        #expect(clampedSettings.translationFontSize(isCurrent: false) == CGFloat(11))
    }

    @Test("纯文本歌词使用非当前行字号和所选行间距")
    func plainLyricsUsesNormalSizeAndSelectedSpacing() {
        let settings = LyricsDisplaySettings(
            highlightSizeRaw: LyricsHighlightSize.s24.rawValue,
            normalSizeRaw: LyricsNormalSize.s16.rawValue,
            translationOffsetRaw: LyricsTranslationOffset.zero.rawValue,
            highlightIntensityRaw: LyricsHighlightIntensity.dramatic.rawValue,
            lineSpacingRaw: LyricsLineSpacing.relaxed.rawValue
        )

        #expect(settings.plainTextFontSize == CGFloat(16))
        #expect(settings.plainTextLineSpacing == CGFloat(14))
        #expect(settings.blockVerticalPadding == CGFloat(14))
    }
}
