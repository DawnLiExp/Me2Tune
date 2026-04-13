//
//  SongRowView.swift
//  Me2Tune
//
//  播放列表歌曲行组件 - (Equatable + 失败标记)
//

import SwiftUI

struct SongRowView: View {
    let track: AudioTrack
    let index: Int
    let isPlaying: Bool
    let isFailed: Bool // ✅ 新增：失败标记
    
    @State private var isHovered = false
    @AppStorage("CleanMode") private var cleanMode = false
    
    private let timeString: String
    private let artistString: String
    
    init(track: AudioTrack, index: Int, isPlaying: Bool, isFailed: Bool = false) {
        self.track = track
        self.index = index
        self.isPlaying = isPlaying
        self.isFailed = isFailed
        self.timeString = Self.formatTime(track.duration)
        self.artistString = track.artist ?? String(localized: "unknown_artist")
    }
    
    var body: some View {
        contentView
            .background(hoverDetector)
            .contentShape(Rectangle())
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        HStack(spacing: 12) {
            indexOrIndicator
                .frame(width: 24)
            
            Text(track.title)
                .font(.system(size: 14, weight: isPlaying ? .semibold : .regular))
                .foregroundColor(textColor)
                .lineLimit(1)
            
            Spacer(minLength: 0)
            
            Text(artistString)
                .font(.system(size: 13))
                .foregroundColor(.secondaryText.opacity(isFailed ? 0.5 : 1.0))
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .trailing)
            
            Text(timeString)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.secondaryText.opacity(isFailed ? 0.5 : 1.0))
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentLight)
                    .opacity(isPlaying ? 1 : 0)
                
                if !cleanMode {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.hoverBackground)
                        .opacity(!isPlaying && isHovered ? 1 : 0)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
    }
    
    // MARK: - Hover Detector
    
    @ViewBuilder
    private var hoverDetector: some View {
        if cleanMode {
            Color.clear
        } else {
            HoverDetectingView(isHovered: $isHovered)
        }
    }
    
    // MARK: - Index or Indicator
    
    @ViewBuilder
    private var indexOrIndicator: some View {
        if isFailed {
            // ✅ 失败标记：警告图标
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange.opacity(0.8))
                .font(.system(size: 12, weight: .semibold))
        } else if isPlaying {
            Image(systemName: "waveform")
                .foregroundColor(.accent)
                .font(.system(size: 13, weight: .semibold))
        } else {
            Text((index + 1).formatted())
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondaryText)
        }
    }
    
    // MARK: - Text Color
    
    private var textColor: Color {
        if isFailed {
            return .primaryText.opacity(0.4)
        } else if isPlaying {
            return .primaryText
        } else {
            return .primaryText.opacity(0.8)
        }
    }
    
    // MARK: - Helper
    
    private static func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, !time.isNaN else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Equatable

extension SongRowView: Equatable {
    static func == (lhs: SongRowView, rhs: SongRowView) -> Bool {
        lhs.track.id == rhs.track.id &&
            lhs.index == rhs.index &&
            lhs.isPlaying == rhs.isPlaying &&
            lhs.isFailed == rhs.isFailed // ✅ 新增比较
    }
}
