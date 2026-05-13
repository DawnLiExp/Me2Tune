//
//  LyricLineView.swift
//  Me2Tune
//
//  Single synced lyric line rendering.
//

import SwiftUI

struct LyricLineView: View {
    @Environment(PlayerViewModel.self) private var playerViewModel

    let line: LyricLine
    let lineIndex: Int
    let currentLineIndex: Int?
    let displaySettings: LyricsDisplaySettings
    let theme: ThemeColors

    @State private var highlightedSegmentCount = 0
    @State private var wordHighlightTimer: Timer?

    private let wordHighlightSyncInterval: TimeInterval = 0.5
    
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

    private var pendingWordTextColor: Color {
        theme.primaryText.opacity(0.78)
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

    private var primaryLyricText: Text {
        if isCurrent, !line.segments.isEmpty {
            let highlightedText = line.segments
                .prefix(highlightedSegmentCount)
                .map(\.text)
                .joined()
            let pendingText = line.segments
                .dropFirst(highlightedSegmentCount)
                .map(\.text)
                .joined()

            return Text(highlightedText).foregroundColor(theme.accent)
                + Text(pendingText).foregroundColor(pendingWordTextColor)
        }

        return Text(line.text.isEmpty ? "♪" : line.text)
            .foregroundColor(primaryTextColor)
    }
    
    var body: some View {
        VStack(spacing: 4) {
            primaryLyricText
                .font(.system(
                    size: displaySettings.reservedMainFontSize,
                    weight: isCurrent ? .semibold : .regular
                ))
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
        .onAppear {
            refreshWordHighlight()
        }
        .onChange(of: isCurrent) { _, _ in
            refreshWordHighlight()
        }
        .onChange(of: playerViewModel.isPlaying) { _, _ in
            refreshWordHighlight()
        }
        .onChange(of: displaySettings.timeOffset.offsetValue) { _, _ in
            refreshWordHighlight()
        }
        .onChange(of: line.id) { _, _ in
            refreshWordHighlight()
        }
        .onDisappear {
            stopWordHighlightTimer()
        }
    }

    private func refreshWordHighlight() {
        stopWordHighlightTimer()

        guard isCurrent, !line.segments.isEmpty else {
            highlightedSegmentCount = 0
            return
        }

        updateHighlightedSegmentCount()

        guard playerViewModel.isPlaying else { return }
        scheduleWordHighlightTimer()
    }

    private func updateHighlightedSegmentCount() {
        highlightedSegmentCount = line.highlightedSegmentCount(
            at: playerViewModel.getCurrentPlaybackTime(),
            offset: displaySettings.timeOffset.offsetValue
        )
    }

    private func scheduleWordHighlightTimer() {
        let playbackTime = playerViewModel.getCurrentPlaybackTime()
        let nextActivationDelay = line.nextSegmentActivationTime(
            after: playbackTime,
            offset: displaySettings.timeOffset.offsetValue
        ).map { activationTime in
            max(0.005, activationTime - playbackTime)
        }
        let delay = min(nextActivationDelay ?? wordHighlightSyncInterval, wordHighlightSyncInterval)
        wordHighlightTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak playerViewModel] _ in
            guard let playerViewModel else { return }

            Task { @MainActor in
                guard playerViewModel.isPlaying else { return }

                highlightedSegmentCount = line.highlightedSegmentCount(
                    at: playerViewModel.getCurrentPlaybackTime(),
                    offset: displaySettings.timeOffset.offsetValue
                )
                scheduleWordHighlightTimer()
            }
        }
        wordHighlightTimer?.tolerance = min(0.01, delay * 0.1)
    }

    private func stopWordHighlightTimer() {
        wordHighlightTimer?.invalidate()
        wordHighlightTimer = nil
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
    let collectionManager = CollectionManager()
    let coordinator = PlaybackCoordinator(collectionManager: collectionManager)
    let playerViewModel = PlayerViewModel(coordinator: coordinator)

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
    .environment(playerViewModel)
}
