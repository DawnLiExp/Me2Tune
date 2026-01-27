//
//  LyricsView.swift
//  Me2Tune
//
//  歌词显示视图 - 独立高频刷新,不依赖主窗口状态
//

import SwiftUI

struct LyricsView: View {
    @EnvironmentObject private var playerViewModel: PlayerViewModel
    // ✅ 移除 @ObservedObject themeManager（主题切换重启生效，直接用单例）
    
    @State private var lyrics: Lyrics?
    @State private var lyricLines: [LyricLine] = []
    @State private var currentLineIndex: Int?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    @AppStorage("lyricsAlwaysOnTop") private var alwaysOnTop = false
    
    // ✅ 独立刷新 Timer
    @State private var updateTimer: Timer?
    @State private var currentPlaybackTime: TimeInterval = 0
    
    // ✅ 直接访问主题颜色
    private var themeColors: ThemeColors {
        ThemeManager.shared.currentTheme.colors
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
                
                contentSection
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 440, height: 800)
        .contextMenu {
            Toggle(isOn: $alwaysOnTop) {
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
                            theme: themeColors
                        )
                        .id(index)
                        .padding(.vertical, 8)
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
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(themeColors.primaryText)
                .lineSpacing(8)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
        }
    }
    
    // MARK: - Independent Update Timer
    
    private func startUpdateTimer() {
        stopUpdateTimer()
        
        // ✅ 歌词窗口前台时：0.3s 高频刷新
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak playerViewModel] _ in
            guard let playerViewModel else { return }
            
            Task { @MainActor in
                // ✅ 直接从播放器获取实时进度
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
        switch distanceFromCurrent {
        case 0:
            return 1.0
        case 1, 2:
            return 0.85
        case 3, 4:
            return 0.6
        case 5, 6:
            return 0.4
        case 7, 8:
            return 0.25
        default:
            return 0.18
        }
    }
    
    var body: some View {
        Text(line.text.isEmpty ? "♪" : line.text)
            .font(.system(
                size: isCurrent ? 17 : 15,
                weight: isCurrent ? .semibold : .regular
            ))
            .foregroundColor(textColor)
            .opacity(distanceOpacity)
            .multilineTextAlignment(.center)
            .lineSpacing(6)
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.3), value: isCurrent)
            .animation(.easeOut(duration: 0.3), value: distanceFromCurrent)
    }
    
    private var textColor: Color {
        if isCurrent {
            return theme.accent
        } else if isPassed {
            return theme.primaryText.opacity(0.7)
        } else {
            return theme.secondaryText.opacity(0.8)
        }
    }
}

#Preview {
    LyricsView()
        .environmentObject(PlayerViewModel())
}
