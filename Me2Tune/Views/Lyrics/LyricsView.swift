//
//  LyricsView.swift
//  Me2Tune
//
//  歌词显示视图 - 滚动和高亮功能
//

import SwiftUI

struct LyricsView: View {
    @EnvironmentObject private var playerViewModel: PlayerViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    
    @State private var lyrics: Lyrics?
    @State private var lyricLines: [LyricLine] = []
    @State private var currentLineIndex: Int?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    @AppStorage("lyricsAlwaysOnTop") private var alwaysOnTop = false
    
    var body: some View {
        ZStack {
            // 背景
            themeManager.currentTheme.colors.mainBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 头部信息
                headerSection
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                
                Divider()
                    .background(themeManager.currentTheme.colors.borderGradientStart.opacity(0.3))
                    .padding(.vertical, 12)
                
                // 歌词内容
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
        .onChange(of: playerViewModel.currentTime) { _, newTime in
            updateCurrentLine(time: newTime)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            if let track = playerViewModel.currentTrack {
                Text(track.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(themeManager.currentTheme.colors.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                Text(track.artist ?? String(localized: "unknown_artist"))
                    .font(.system(size: 14))
                    .foregroundColor(themeManager.currentTheme.colors.secondaryText)
                    .lineLimit(1)
            } else {
                Text(String(localized: "no_track"))
                    .font(.system(size: 16))
                    .foregroundColor(themeManager.currentTheme.colors.secondaryText)
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
                .tint(themeManager.currentTheme.colors.accent)
            
            Text("loading_lyrics")
                .font(.system(size: 14))
                .foregroundColor(themeManager.currentTheme.colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "text.badge.xmark")
                .font(.system(size: 48))
                .foregroundColor(themeManager.currentTheme.colors.emptyStateIcon)
            
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(themeManager.currentTheme.colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
    
    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 48))
                .foregroundColor(themeManager.currentTheme.colors.emptyStateIcon)
            
            Text("no_lyrics")
                .font(.system(size: 14))
                .foregroundColor(themeManager.currentTheme.colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var instrumentalView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundColor(themeManager.currentTheme.colors.accent.opacity(0.6))
            
            Text("instrumental_track")
                .font(.system(size: 16))
                .foregroundColor(themeManager.currentTheme.colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Synced Lyrics View (滚动 + 高亮)
    
    private var syncedLyricsView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // 顶部间距
                    Color.clear
                        .frame(height: 300)
                        .id("top-spacer")
                    
                    // 歌词行
                    ForEach(Array(lyricLines.enumerated()), id: \.offset) { index, line in
                        LyricLineView(
                            line: line,
                            lineIndex: index,
                            currentLineIndex: currentLineIndex,
                            theme: themeManager.currentTheme.colors
                        )
                        .id(index)
                        .padding(.vertical, 8)
                    }
                    
                    // 底部间距
                    Color.clear
                        .frame(height: 300)
                        .id("bottom-spacer")
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: currentLineIndex) { _, newIndex in
                guard let newIndex else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
    
    // MARK: - Plain Lyrics View (纯文本)
    
    private func plainLyricsView(text: String) -> some View {
        ScrollView(showsIndicators: false) {
            Text(text)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(themeManager.currentTheme.colors.primaryText)
                .lineSpacing(8)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
        }
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
        
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await LyricsService.shared.getLyrics(
                trackName: track.title,
                artistName: track.artist ?? "Unknown Artist",
                albumName: track.albumTitle ?? "",
                duration: Int(track.duration)
            )
            
            await MainActor.run {
                lyrics = result
                lyricLines = result.parseSyncedLyrics()
                currentLineIndex = nil
                isLoading = false
                
                // 立即更新当前行(如果正在播放)
                if playerViewModel.isPlaying {
                    updateCurrentLine(time: playerViewModel.currentTime)
                }
            }
        } catch {
            await MainActor.run {
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
        
        // 找到当前时间对应的歌词行(最后一个时间戳 <= 当前时间的行)
        var foundIndex: Int?
        for (index, line) in lyricLines.enumerated() {
            if line.timestamp <= time {
                foundIndex = index
            } else {
                break
            }
        }
        
        // 只在索引变化时更新(避免频繁触发动画)
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
    
    // 计算距离当前行的距离(用于渐变效果)
    private var distanceFromCurrent: Int {
        guard let current = currentLineIndex else { return 0 }
        return abs(lineIndex - current)
    }
    
    // 根据距离计算透明度(距离越远越淡)
    private var distanceOpacity: Double {
        switch distanceFromCurrent {
        case 0:
            return 1.0 // 当前行:完全不透明
        case 1:
            return 0.85 // 相邻行:稍微淡一点
        case 2:
            return 0.6 // 第二邻居:更淡
        case 3:
            return 0.4 // 第三邻居:很淡
        case 4:
            return 0.25 // 第四邻居:非常淡
        default:
            return 0.15 // 更远的行:几乎透明
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
