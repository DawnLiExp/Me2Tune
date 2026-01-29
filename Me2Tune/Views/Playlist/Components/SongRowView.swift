//
//  SongRowView.swift
//  Me2Tune
//
//  播放列表歌曲行组件 - (Equatable + 无闭包依赖)
//

import SwiftUI

struct SongRowView: View {
    let track: AudioTrack
    let index: Int
    let isPlaying: Bool
    // ✅ 移除 onTap 闭包参数,避免闭包重建导致的刷新
    
    @State private var isHovered = false
    @AppStorage("CleanMode") private var cleanMode = false
    
    // ✅ 预计算不变内容,避免重复格式化
    private let timeString: String
    private let artistString: String
    
    init(track: AudioTrack, index: Int, isPlaying: Bool) {
        self.track = track
        self.index = index
        self.isPlaying = isPlaying
        self.timeString = Self.formatTime(track.duration)
        self.artistString = track.artist ?? String(localized: "unknown_artist")
    }
    
    var body: some View {
        contentView
            .background(hoverDetector) // ✅ 稳定的 hover 检测
            .contentShape(Rectangle()) // ✅ 交互区域由外层的 onTapGesture 处理
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        HStack(spacing: 12) {
            indexOrWaveform
                .frame(width: 24)
            
            Text(track.title)
                .font(.system(size: 14, weight: isPlaying ? .semibold : .regular))
                .foregroundColor(isPlaying ? .primaryText : .primaryText.opacity(0.8))
                .lineLimit(1)
            
            Spacer(minLength: 0)
            
            Text(artistString)
                .font(.system(size: 13))
                .foregroundColor(.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .trailing)
            
            Text(timeString)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.secondaryText)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background {
            // ✅ 内联 background,避免计算属性重建
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
            // ✅ 条件分支稳定,避免 AnyView
            HoverDetectingView(isHovered: $isHovered)
        }
    }
    
    // MARK: - Index or Waveform
    
    @ViewBuilder
    private var indexOrWaveform: some View {
        if isPlaying {
            Image(systemName: "waveform")
                .foregroundColor(.accent)
                .font(.system(size: 13, weight: .semibold))
        } else {
            Text("\(index + 1)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondaryText)
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
        // ✅ 只在真正影响显示的属性变化时才认为需要更新
        lhs.track.id == rhs.track.id &&
            lhs.index == rhs.index &&
            lhs.isPlaying == rhs.isPlaying
        // 注意: isHovered 和 cleanMode 是 @State/@AppStorage,由 SwiftUI 自动处理
    }
}
