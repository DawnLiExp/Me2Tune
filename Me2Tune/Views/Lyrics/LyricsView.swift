//
//  LyricsView.swift
//  Me2Tune
//
//  Created by me2 on 2026/1/18.
//


//
//  LyricsView.swift
//  Me2Tune
//
//  歌词显示视图 - 第一步基础功能
//

import SwiftUI

struct LyricsView: View {
    @EnvironmentObject private var playerViewModel: PlayerViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    
    @State private var lyrics: Lyrics?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
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
        .task(id: playerViewModel.currentTrack?.id) {
            await loadLyrics()
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
            lyricsTextView(lyrics: lyrics)
        } else {
            emptyView
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(themeManager.currentTheme.colors.accent)
            
            Text("Loading lyrics...")
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
            
            Text("No lyrics available")
                .font(.system(size: 14))
                .foregroundColor(themeManager.currentTheme.colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func lyricsTextView(lyrics: Lyrics) -> some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                if lyrics.instrumental {
                    Text("🎵 Instrumental Track")
                        .font(.system(size: 16))
                        .foregroundColor(themeManager.currentTheme.colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    Text(lyrics.displayLyrics)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(themeManager.currentTheme.colors.primaryText)
                        .lineSpacing(8)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
    }
    
    // MARK: - Load Lyrics
    
    private func loadLyrics() async {
        guard let track = playerViewModel.currentTrack else {
            lyrics = nil
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
                isLoading = false
            }
        } catch {
            await MainActor.run {
                lyrics = nil
                isLoading = false
                
                if let lyricsError = error as? LyricsError {
                    errorMessage = lyricsError.errorDescription
                } else {
                    errorMessage = "Failed to load lyrics"
                }
            }
        }
    }
}

#Preview {
    LyricsView()
        .environmentObject(PlayerViewModel())
}