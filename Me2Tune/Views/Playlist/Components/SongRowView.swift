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
    let onTap: () -> Void
    
    @State private var isHovered = false
    @AppStorage("CleanMode") private var cleanMode = false // 新增：简洁模式设置
    
    // 预计算不变的内容
    private let timeString: String
    private let artistString: String
    
    init(track: AudioTrack, index: Int, isPlaying: Bool, onTap: @escaping () -> Void) {
        self.track = track
        self.index = index
        self.isPlaying = isPlaying
        self.onTap = onTap
        
        // 构造时计算，避免每次 body 执行时重新格式化
        self.timeString = Self.formatTime(track.duration)
        self.artistString = track.artist ?? String(localized: "unknown_artist")
    }
    
    var body: some View {
        contentView
            // 简洁模式下跳过 hover 检测
            .background(cleanMode ? AnyView(Color.clear) : AnyView(HoverDetector(isHovered: $isHovered)))
            .onTapGesture(count: 2) {
                onTap()
            }
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
        .background(backgroundView) // 独立背景视图
        .contentShape(Rectangle())
    }
    
    // 用 opacity 替代 if-else，避免条件分支
    private var backgroundView: some View {
        ZStack {
            // Playing 状态背景（始终存在，用透明度控制）
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.accentLight)
                .opacity(isPlaying ? 1 : 0)
            
            // 简洁模式下禁用 hover 背景
            if !cleanMode {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.hoverBackground)
                    .opacity(!isPlaying && isHovered ? 1 : 0)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
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

// MARK: - Hover Detector (轻量级版本)

private struct HoverDetector: NSViewRepresentable {
    @Binding var isHovered: Bool
    
    func makeNSView(context: Context) -> HoverView {
        let view = HoverView()
        view.onHoverChange = { [weak view] hovering in
            guard view != nil else { return }
            // 去掉 DispatchQueue.main.async，直接更新
            self.isHovered = hovering
        }
        return view
    }
    
    func updateNSView(_ nsView: HoverView, context: Context) {}
    
    final class HoverView: NSView {
        var onHoverChange: ((Bool) -> Void)?
        private var isCurrentlyHovered = false
        
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach { removeTrackingArea($0) }
            
            let trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            
            // 简化位置检查
            updateHoverState()
        }
        
        override func mouseEntered(with event: NSEvent) {
            updateHoverState(true)
        }
        
        override func mouseExited(with event: NSEvent) {
            updateHoverState(false)
        }
        
        private func updateHoverState(_ newState: Bool? = nil) {
            let shouldBeHovered: Bool
            
            if let newState {
                shouldBeHovered = newState
            } else if let window {
                let mouseLocation = window.mouseLocationOutsideOfEventStream
                let locationInView = convert(mouseLocation, from: nil)
                shouldBeHovered = bounds.contains(locationInView)
            } else {
                shouldBeHovered = false
            }
            
            guard shouldBeHovered != isCurrentlyHovered else { return }
            isCurrentlyHovered = shouldBeHovered
            onHoverChange?(shouldBeHovered)
        }
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateHoverState()
        }
    }
}
