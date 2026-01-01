//
//  SongRowView.swift
//  Me2Tune
//
//  播放列表歌曲行组件
//

import SwiftUI

struct SongRowView: View {
    let track: AudioTrack
    let index: Int
    let isPlaying: Bool
    let isHovered: Bool
    let onTap: () -> Void
    let onHoverChange: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Group {
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
            .frame(width: 24)
            
            Text(track.title)
                .font(.system(size: 14, weight: isPlaying ? .semibold : .regular))
                .foregroundColor(isPlaying ? .primaryText : .primaryText.opacity(0.8))
                .lineLimit(1)
            
            Spacer()
            
            Text(track.artist ?? String(localized: "unknown_artist"))
                .font(.system(size: 13))
                .foregroundColor(.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .trailing)
            
            Text(formatTime(track.duration))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.secondaryText)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(backgroundColor)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onTap()
        }
        .onHover { hovering in
            onHoverChange(hovering)
        }
    }
    
    private var backgroundColor: Color {
        if isPlaying {
            return .accentLight
        } else if isHovered {
            return .hoverBackground
        } else {
            return Color.clear
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, !time.isNaN else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    let mockTrack = AudioTrack(
        id: UUID(),
        url: URL(fileURLWithPath: "/test.mp3"),
        title: "Test Song",
        artist: "Test Artist",
        albumTitle: "Test Album",
        duration: 180,
        format: AudioFormat(codec: "AAC", bitrate: 256, sampleRate: 44100, bitDepth: 16, channels: 2),
        bookmark: nil
    )
    
    SongRowView(
        track: mockTrack,
        index: 0,
        isPlaying: false,
        isHovered: false,
        onTap: {},
        onHoverChange: { _ in }
    )
    .padding()
    .background(Color.black)
}
