//
//  LyricsView.swift
//  Me2Tune
//
//  歌词显示视图 - 独立高频刷新,不依赖主窗口状态
//

import SwiftUI

struct LyricsView: View {
    @Environment(PlayerViewModel.self) private var playerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var windowState = LyricsWindowState()
    var onDetach: () -> Void = {}
    
    @State private var lyricsTrack: AudioTrack?
    @State private var isFollowingPlayback = true
    @State private var playbackCanSeek = false
    @State private var lastScrolledLineIndex: Int?
    @State private var lyrics: Lyrics?
    @State private var lyricLines: [LyricLine] = []
    @State private var currentLineIndex: Int?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showLyricsSettings = false

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

    @AppStorage(LyricsDisplaySettingsKey.timeOffset)
    private var timeOffsetRaw = LyricsTimeOffset.zero.rawValue
    
    private var themeColors: ThemeColors {
        ThemeManager.shared.currentTheme.colors
    }

    private var settingsSliderAppearance: TickedSliderAppearance {
        TickedSliderAppearance(
            labelColor: themeColors.primaryText.opacity(0.72),
            railColor: themeColors.primaryText.opacity(0.18),
            tickColor: themeColors.primaryText.opacity(0.3)
        )
    }

    private var displaySettings: LyricsDisplaySettings {
        LyricsDisplaySettings(
            highlightSizeRaw: highlightSizeRaw,
            normalSizeRaw: normalSizeRaw,
            translationOffsetRaw: translationOffsetRaw,
            highlightIntensityRaw: highlightIntensityRaw,
            lineSpacingRaw: lineSpacingRaw,
            timeOffsetRaw: timeOffsetRaw
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
            Picker(String(localized: "lyrics_docking_spacing"), selection: $settings.lyricsDockingSpacing) {
                Text("lyrics_docking_spaced").tag(LyricsDockingSpacing.spaced)
                Text("lyrics_docking_flush").tag(LyricsDockingSpacing.flush)
            }
            .pickerStyle(.menu)
            Divider()
            if windowState.isDocked {
                Label(String(localized: "lyrics_follow_player_level"), systemImage: "pin.fill")
                    .disabled(true)
                Button(String(localized: "lyrics_detach"), action: onDetach)
            } else {
                Toggle(isOn: $settings.lyricsAlwaysOnTop) {
                    Label(String(localized: "always_on_top"), systemImage: "pin.fill")
                }
            }
        }
        .task(id: playerViewModel.currentTrack?.metadataRevision) {
            await loadLyrics()
        }
        .onAppear {
            if LyricsTimeOffset(rawValue: timeOffsetRaw) == nil {
                timeOffsetRaw = LyricsTimeOffset.zero.rawValue
            }
            startUpdateTimer()
        }
        .onChange(of: playerViewModel.isPlaying) { _, _ in
            startUpdateTimer()
        }
        .onChange(of: windowState.isVisible) { _, _ in
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

                    if !isLoading, lyricsMatchCurrentTrack, playbackCanSeek,
                       lyricLines.contains(where: { $0.seekTime(offset: displaySettings.timeOffset.offsetValue,
                                                               duration: playerViewModel.duration) != nil }) {
                        Text("lyrics_seek_hint")
                            .font(.system(size: 11))
                            .foregroundStyle(themeColors.secondaryText)
                            .accessibilityIdentifier("lyrics.seek.hint")
                    }
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

                    ForEach(Array(lyricLines.enumerated()), id: \.element.id) { index, line in
                        LyricLineView(
                            line: line,
                            lineIndex: index,
                            currentLineIndex: currentLineIndex,
                            displaySettings: displaySettings,
                            theme: themeColors,
                            isBrowsing: !isFollowingPlayback,
                            seekRevision: playerViewModel.playbackProgressState.seekRevision,
                            seekTarget: seekTarget(for: line),
                            onSeek: { seek(to: line) },
                            onFocus: { withoutLyricsAnimation { isFollowingPlayback = false } }
                        )
                        .id(index)
                    }

                    Color.clear
                        .frame(height: 300)
                        .id("bottom-spacer")
                }
                .padding(.horizontal, 20)
            }
            .onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting || phase == .decelerating {
                    withAnimation(returnButtonAnimation) {
                        isFollowingPlayback = false
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if !isFollowingPlayback {
                    NonDraggableView {
                        Button {
                            withoutLyricsAnimation {
                                refreshPlaybackPosition()
                                isFollowingPlayback = true
                                scrollToPlayback(using: proxy, animated: false)
                            }
                        } label: {
                            Label("lyrics_return_to_current", systemImage: "location.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(themeColors.primaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(themeColors.controlBackground, in: Capsule())
                                .background(themeColors.mainBackground, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("lyrics.return")
                    }
                    .padding(.bottom, 16)
                    .transition(.opacity)
                }
            }
            .onAppear {
                scrollToPlayback(using: proxy, animated: false)
            }
            .onChange(of: currentLineIndex) { _, newIndex in
                guard isFollowingPlayback, newIndex != lastScrolledLineIndex else { return }
                scrollToPlayback(using: proxy, animated: !reduceMotion)
            }
            .onChange(of: playerViewModel.playbackProgressState.seekRevision) { _, _ in
                guard lyricsMatchCurrentTrack else { return }
                withoutLyricsAnimation {
                    refreshPlaybackPosition()
                    isFollowingPlayback = true
                    scrollToPlayback(using: proxy, animated: false)
                }
            }
        }
    }

    private var returnButtonAnimation: Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: 0.16)
    }

    private var lyricsMatchCurrentTrack: Bool {
        guard let lyricsTrack, let track = playerViewModel.currentTrack else { return false }
        return lyricsTrack.id == track.id && lyricsTrack.metadataRevision == track.metadataRevision
    }

    private func seekTarget(for line: LyricLine) -> TimeInterval? {
        guard !isLoading, lyricsMatchCurrentTrack, playbackCanSeek else { return nil }
        return line.seekTime(offset: displaySettings.timeOffset.offsetValue, duration: playerViewModel.duration)
    }

    private func seek(to line: LyricLine) {
        guard lyricLines.contains(where: { $0.id == line.id }),
              let track = lyricsTrack, let target = seekTarget(for: line) else { return }
        playerViewModel.seek(to: target, trackID: track.id, metadataRevision: track.metadataRevision)
    }

    private func scrollToPlayback(using proxy: ScrollViewProxy, animated: Bool) {
        let index = currentLineIndex
        lastScrolledLineIndex = index
        let scroll = {
            if let index {
                proxy.scrollTo(index, anchor: UnitPoint(x: 0.5, y: 0.4))
            } else {
                proxy.scrollTo("top-spacer", anchor: .top)
            }
        }
        if animated {
            withAnimation(.easeOut(duration: 0.22), scroll)
        } else {
            withoutLyricsAnimation(scroll)
        }
    }

    private func withoutLyricsAnimation(_ action: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, action)
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
                settingsRow("lyrics_highlight_size", systemImage: "textformat.size.larger") {
                    TickedSlider<LyricsHighlightSize>(
                        selection: $highlightSizeRaw,
                        leftLabel: "lyrics_size_small",
                        rightLabel: "lyrics_size_large",
                        appearance: settingsSliderAppearance
                    )
                }

                settingsRow("lyrics_normal_size", systemImage: "textformat.size.smaller") {
                    TickedSlider<LyricsNormalSize>(
                        selection: $normalSizeRaw,
                        leftLabel: "lyrics_size_small",
                        rightLabel: "lyrics_size_large",
                        appearance: settingsSliderAppearance
                    )
                }

                settingsRow("lyrics_translation_offset", systemImage: "globe") {
                    TickedSlider<LyricsTranslationOffset>(
                        selection: $translationOffsetRaw,
                        leftVerbatimLabel: "-1",
                        rightVerbatimLabel: "+1",
                        appearance: settingsSliderAppearance
                    )
                }

                settingsRow("lyrics_focus_intensity", systemImage: "viewfinder.circle") {
                    TickedSlider<LyricsHighlightIntensity>(
                        selection: $highlightIntensityRaw,
                        leftLabel: "lyrics_intensity_gentle",
                        rightLabel: "lyrics_intensity_dramatic",
                        appearance: settingsSliderAppearance
                    )
                }

                settingsRow("lyrics_line_spacing", systemImage: "line.3.horizontal") {
                    TickedSlider<LyricsLineSpacing>(
                        selection: $lineSpacingRaw,
                        leftLabel: "lyrics_spacing_compact",
                        rightLabel: "lyrics_spacing_relaxed",
                        appearance: settingsSliderAppearance
                    )
                }

                settingsRow("lyrics_time_offset", systemImage: "clock.arrow.2.circlepath") {
                    TickedSlider<LyricsTimeOffset>(
                        selection: $timeOffsetRaw,
                        leftVerbatimLabel: "-1.5s",
                        rightVerbatimLabel: "+1.5s",
                        appearance: settingsSliderAppearance
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
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: 392)
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
        systemImage: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(themeColors.accent.opacity(0.9))
                    .frame(width: 12)

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(themeColors.secondaryText)
                    .multilineTextAlignment(.leading)
            }
            .padding(.leading, 6)
            .frame(width: 112, alignment: .leading)

            content()
        }
    }

    private func resetLyricsSettings() {
        highlightSizeRaw = LyricsHighlightSize.s18.rawValue
        normalSizeRaw = LyricsNormalSize.s15.rawValue
        translationOffsetRaw = LyricsTranslationOffset.minus1.rawValue
        highlightIntensityRaw = LyricsHighlightIntensity.standard.rawValue
        lineSpacingRaw = LyricsLineSpacing.normal.rawValue
        timeOffsetRaw = LyricsTimeOffset.zero.rawValue
    }
    
    // MARK: - Independent Update Timer
    
    private func startUpdateTimer() {
        windowState.refreshDriver.update(isVisible: windowState.isVisible) {
            refreshPlaybackPosition()
        }
    }
    
    private func stopUpdateTimer() {
        windowState.refreshDriver.stop()
    }

    private func refreshPlaybackPosition() {
        playbackCanSeek = playerViewModel.canSeek
        updateCurrentLine(time: playerViewModel.getCurrentPlaybackTime())
    }
    
    // MARK: - Load Lyrics
    
    private func loadLyrics() async {
        lyricsTrack = nil
        isFollowingPlayback = true
        lastScrolledLineIndex = nil
        guard let track = playerViewModel.currentTrack else {
            isLoading = false
            lyrics = nil
            lyricLines = []
            currentLineIndex = nil
            errorMessage = nil
            startUpdateTimer()
            return
        }
        
        let trackID = track.id
        
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await LyricsService.shared.getLyricsWithCache(track: track)
            
            guard !Task.isCancelled, playerViewModel.currentTrack?.id == trackID,
                  playerViewModel.currentTrack?.metadataRevision == track.metadataRevision else {
                return
            }
            
            await MainActor.run {
                guard !Task.isCancelled, playerViewModel.currentTrack?.id == trackID,
                  playerViewModel.currentTrack?.metadataRevision == track.metadataRevision else {
                    return
                }
                
                lyricsTrack = track
                lyrics = result
                lyricLines = result.parseSyncedLyrics()
                currentLineIndex = nil
                isLoading = false
                startUpdateTimer()
                
                if playerViewModel.isPlaying {
                    updateCurrentLine(time: playerViewModel.getCurrentPlaybackTime())
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, playerViewModel.currentTrack?.id == trackID,
                  playerViewModel.currentTrack?.metadataRevision == track.metadataRevision else {
                return
            }
            
            await MainActor.run {
                guard !Task.isCancelled, playerViewModel.currentTrack?.id == trackID,
                  playerViewModel.currentTrack?.metadataRevision == track.metadataRevision else {
                    return
                }
                
                lyrics = nil
                lyricLines = []
                currentLineIndex = nil
                isLoading = false
                startUpdateTimer()
                
                if let lyricsError = error as? LyricsError {
                    errorMessage = lyricsError.errorDescription
                } else {
                    errorMessage = String(localized: "failed_to_load_lyrics")
                }
            }
        }
    }
    
    // MARK: - Update Current Line

    /// 在给定歌词行列表中，找到最后一个 timestamp ≤ adjustedTime 的行索引
    static func findCurrentLineIndex(
        in lines: [LyricLine],
        at time: TimeInterval,
        offset: Double
    ) -> Int? {
        guard !lines.isEmpty else { return nil }
        let adjustedTime = time - offset
        var lowerBound = 0
        var upperBound = lines.count

        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            if lines[midpoint].timestamp <= adjustedTime {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        let foundIndex = lowerBound - 1
        return foundIndex >= 0 ? foundIndex : nil
    }

    private func updateCurrentLine(time: TimeInterval) {
        let newIndex = Self.findCurrentLineIndex(
            in: lyricLines,
            at: time,
            offset: displaySettings.timeOffset.offsetValue
        )
        if newIndex != currentLineIndex {
            currentLineIndex = newIndex
        }
    }
}

#Preview {
    let collectionManager = CollectionManager()
    let coordinator = PlaybackCoordinator(collectionManager: collectionManager)
    let playerViewModel = PlayerViewModel(coordinator: coordinator)

    LyricsView()
        .environment(playerViewModel)
}
