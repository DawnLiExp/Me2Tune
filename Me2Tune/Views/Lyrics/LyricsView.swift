//
//  LyricsView.swift
//  Me2Tune
//
//  歌词显示视图 - 独立高频刷新,不依赖主窗口状态
//

import SwiftUI

struct LyricsView: View {
    @Environment(PlayerViewModel.self) private var playerViewModel
    
    @State private var lyrics: Lyrics?
    @State private var lyricLines: [LyricLine] = []
    @State private var currentLineIndex: Int?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showLyricsSettings = false
    
    @State private var updateTimer: Timer?
    @State private var currentPlaybackTime: TimeInterval = 0

    @AppStorage(LyricsDisplaySettingsKey.highlightSize)
    private var highlightSizeRaw = LyricsHighlightSize.s18.rawValue

    @AppStorage(LyricsDisplaySettingsKey.normalSize)
    private var normalSizeRaw = LyricsNormalSize.s15.rawValue

    @AppStorage(LyricsDisplaySettingsKey.translationOffset)
    private var translationOffsetRaw = LyricsTranslationOffset.minus1.rawValue

    @AppStorage(LyricsDisplaySettingsKey.highlightIntensity)
    private var highlightIntensityRaw = LyricsHighlightIntensity.standard.rawValue

    @AppStorage(LyricsDisplaySettingsKey.lineSpacing)
    private var lineSpacingRaw = LyricsLineSpacing.normal.rawValue
    
    private var themeColors: ThemeColors {
        ThemeManager.shared.currentTheme.colors
    }

    private var displaySettings: LyricsDisplaySettings {
        LyricsDisplaySettings(
            highlightSizeRaw: highlightSizeRaw,
            normalSizeRaw: normalSizeRaw,
            translationOffsetRaw: translationOffsetRaw,
            highlightIntensityRaw: highlightIntensityRaw,
            lineSpacingRaw: lineSpacingRaw
        )
    }
    
    var body: some View {
        ZStack {
            themeColors.mainBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerSection
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                
                Divider()
                    .frame(width: 360)
                    .background(themeColors.borderGradientStart.opacity(0.3))
                    .padding(.top, 18)
                    .padding(.bottom, 20)

                if showLyricsSettings {
                    settingsPanel
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                contentSection
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 440, height: 800)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showLyricsSettings)
        .contextMenu {
            @Bindable var settings = SettingsManager.shared
            Toggle(isOn: $settings.lyricsAlwaysOnTop) {
                Label(String(localized: "always_on_top"), systemImage: "pin.fill")
            }
        }
        .task(id: playerViewModel.currentTrack?.id) {
            await loadLyrics()
        }
        .onAppear {
            startUpdateTimer()
        }
        .onDisappear {
            stopUpdateTimer()
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            Color.clear
                .frame(width: 28, height: 28)

            VStack(spacing: 8) {
                if let track = playerViewModel.currentTrack {
                    Text(track.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(themeColors.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    
                    Text(track.artist ?? String(localized: "unknown_artist"))
                        .font(.system(size: 14))
                        .foregroundColor(themeColors.secondaryText)
                        .lineLimit(1)
                } else {
                    Text(String(localized: "no_track"))
                        .font(.system(size: 16))
                        .foregroundColor(themeColors.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)

            NonDraggableView {
                Button {
                    showLyricsSettings.toggle()
                } label: {
                    Image(systemName: showLyricsSettings ? "xmark.circle.fill" : "slider.horizontal.3")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(showLyricsSettings ? themeColors.accent : themeColors.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(themeColors.controlBackground.opacity(showLyricsSettings ? 0.95 : 0.65))
                        )
                }
                .buttonStyle(.plain)
                .help(Text("lyrics_display_settings"))
                .accessibilityLabel(Text("lyrics_display_settings"))
            }
        }
    }
    
    // MARK: - Content Section
    
    @ViewBuilder
    private var contentSection: some View {
        if isLoading {
            loadingView
        } else if let errorMessage {
            errorView(message: errorMessage)
        } else if let lyrics {
            if lyrics.instrumental {
                instrumentalView
            } else if !lyricLines.isEmpty {
                syncedLyricsView
            } else if lyrics.plainLyrics != nil {
                plainLyricsView(text: lyrics.plainLyrics!)
            } else {
                emptyView
            }
        } else {
            emptyView
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(themeColors.accent)
            
            Text("loading_lyrics")
                .font(.system(size: 14))
                .foregroundColor(themeColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "text.badge.xmark")
                .font(.system(size: 48))
                .foregroundColor(themeColors.emptyStateIcon)
            
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(themeColors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
    
    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 48))
                .foregroundColor(themeColors.emptyStateIcon)
            
            Text("no_lyrics")
                .font(.system(size: 14))
                .foregroundColor(themeColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var instrumentalView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundColor(themeColors.accent.opacity(0.6))
            
            Text("instrumental_track")
                .font(.system(size: 16))
                .foregroundColor(themeColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Synced Lyrics View
    
    private var syncedLyricsView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 300)
                        .id("top-spacer")
                    
                    ForEach(Array(lyricLines.enumerated()), id: \.offset) { index, line in
                        LyricLineView(
                            line: line,
                            lineIndex: index,
                            currentLineIndex: currentLineIndex,
                            displaySettings: displaySettings,
                            theme: themeColors
                        )
                        .id(index)
                        .padding(.vertical, displaySettings.blockVerticalPadding)
                    }
                    
                    Color.clear
                        .frame(height: 300)
                        .id("bottom-spacer")
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: currentLineIndex) { _, newIndex in
                guard let newIndex else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(newIndex, anchor: UnitPoint(x: 0.5, y: 0.4))
                }
            }
        }
    }
    
    // MARK: - Plain Lyrics View
    
    private func plainLyricsView(text: String) -> some View {
        ScrollView(showsIndicators: false) {
            Text(text)
                .font(.system(size: displaySettings.plainTextFontSize, weight: .regular))
                .foregroundColor(themeColors.primaryText)
                .lineSpacing(displaySettings.plainTextLineSpacing)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
        }
    }

    private var settingsPanel: some View {
        NonDraggableView {
            VStack(spacing: 12) {
                settingsRow("lyrics_highlight_size") {
                    TickedSlider<LyricsHighlightSize>(
                        selection: $highlightSizeRaw,
                        leftLabel: "lyrics_size_small",
                        rightLabel: "lyrics_size_large"
                    )
                }

                settingsRow("lyrics_normal_size") {
                    TickedSlider<LyricsNormalSize>(
                        selection: $normalSizeRaw,
                        leftLabel: "lyrics_size_small",
                        rightLabel: "lyrics_size_large"
                    )
                }

                settingsRow("lyrics_translation_offset") {
                    TickedSlider<LyricsTranslationOffset>(
                        selection: $translationOffsetRaw,
                        leftLabel: "-1",
                        rightLabel: "+1"
                    )
                }

                settingsRow("lyrics_focus_intensity") {
                    TickedSlider<LyricsHighlightIntensity>(
                        selection: $highlightIntensityRaw,
                        leftLabel: "lyrics_intensity_gentle",
                        rightLabel: "lyrics_intensity_dramatic"
                    )
                }

                settingsRow("lyrics_line_spacing") {
                    TickedSlider<LyricsLineSpacing>(
                        selection: $lineSpacingRaw,
                        leftLabel: "lyrics_spacing_compact",
                        rightLabel: "lyrics_spacing_relaxed"
                    )
                }

                HStack {
                    Spacer()

                    Button("lyrics_reset_defaults") {
                        resetLyricsSettings()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(themeColors.secondaryText)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(themeColors.controlBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(themeColors.borderGradientStart.opacity(0.25), lineWidth: 1)
                    )
            )
        }
    }

    private func settingsRow(
        _ label: LocalizedStringKey,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(themeColors.secondaryText)
                .frame(width: 86, alignment: .trailing)

            content()
        }
    }

    private func resetLyricsSettings() {
        highlightSizeRaw = LyricsHighlightSize.s18.rawValue
        normalSizeRaw = LyricsNormalSize.s15.rawValue
        translationOffsetRaw = LyricsTranslationOffset.minus1.rawValue
        highlightIntensityRaw = LyricsHighlightIntensity.standard.rawValue
        lineSpacingRaw = LyricsLineSpacing.normal.rawValue
    }
    
    // MARK: - Independent Update Timer
    
    private func startUpdateTimer() {
        stopUpdateTimer()
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak playerViewModel] _ in
            guard let playerViewModel else { return }
            
            Task { @MainActor in
                currentPlaybackTime = playerViewModel.getCurrentPlaybackTime()
                updateCurrentLine(time: currentPlaybackTime)
            }
        }
    }
    
    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    // MARK: - Load Lyrics
    
    private func loadLyrics() async {
        guard let track = playerViewModel.currentTrack else {
            lyrics = nil
            lyricLines = []
            currentLineIndex = nil
            errorMessage = nil
            return
        }
        
        let trackID = track.id
        
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await LyricsService.shared.getLyricsWithCache(track: track)
            
            guard playerViewModel.currentTrack?.id == trackID else {
                return
            }
            
            await MainActor.run {
                guard playerViewModel.currentTrack?.id == trackID else {
                    return
                }
                
                lyrics = result
                lyricLines = result.parseSyncedLyrics()
                currentLineIndex = nil
                isLoading = false
                
                if playerViewModel.isPlaying {
                    currentPlaybackTime = playerViewModel.getCurrentPlaybackTime()
                    updateCurrentLine(time: currentPlaybackTime)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard playerViewModel.currentTrack?.id == trackID else {
                return
            }
            
            await MainActor.run {
                guard playerViewModel.currentTrack?.id == trackID else {
                    return
                }
                
                lyrics = nil
                lyricLines = []
                currentLineIndex = nil
                isLoading = false
                
                if let lyricsError = error as? LyricsError {
                    errorMessage = lyricsError.errorDescription
                } else {
                    errorMessage = String(localized: "failed_to_load_lyrics")
                }
            }
        }
    }
    
    // MARK: - Update Current Line
    
    private func updateCurrentLine(time: TimeInterval) {
        guard !lyricLines.isEmpty else {
            currentLineIndex = nil
            return
        }
        
        var foundIndex: Int?
        for (index, line) in lyricLines.enumerated() {
            if line.timestamp <= time {
                foundIndex = index
            } else {
                break
            }
        }
        
        if foundIndex != currentLineIndex {
            currentLineIndex = foundIndex
        }
    }
}

// MARK: - Lyric Line View

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
            // 译文比主文本稍微收敛，保持层次感
            return theme.accent.opacity(0.75)
        } else if isPassed {
            return theme.primaryText.opacity(0.55)
        } else {
            return theme.secondaryText.opacity(0.65)
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text(line.text.isEmpty ? "♪" : line.text)
                .font(.system(
                    size: displaySettings.mainFontSize(isCurrent: isCurrent),
                    weight: isCurrent ? .semibold : .regular
                ))
                .foregroundColor(primaryTextColor)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: .infinity)
            
            if let translation = line.translation, !translation.isEmpty {
                Text(translation)
                    .font(.system(
                        size: displaySettings.translationFontSize(isCurrent: isCurrent),
                        weight: .regular
                    ))
                    .foregroundColor(translationTextColor)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity)
            }
        }
        .opacity(distanceOpacity)
        .animation(.easeOut(duration: 0.3), value: isCurrent)
        .animation(.easeOut(duration: 0.3), value: distanceFromCurrent)
    }
}

#Preview {
    let collectionManager = CollectionManager()
    let coordinator = PlaybackCoordinator(collectionManager: collectionManager)
    let playerViewModel = PlayerViewModel(coordinator: coordinator)

    LyricsView()
        .environment(playerViewModel)
}
