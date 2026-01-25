//
//  VinylSectionView.swift
//  Me2Tune
//
//  唱片封面区域 - 半圆唱片+旋转动画（GPU加速优化版）
//

import AppKit
import SwiftUI

// MARK: - VinylSectionView

struct VinylSectionView: View {
    let artwork: NSImage?
    let isPlaying: Bool
    let isRotationEnabled: Bool
    let duration: TimeInterval
    let isWindowVisible: Bool

    @EnvironmentObject private var playbackProgressState: PlaybackProgressState

    private let vinylSize: CGFloat = 280

    var body: some View {
        ZStack(alignment: .bottom) {
            vinylDisc
            timeOverlay
                .offset(y: -147)
        }
        .frame(height: vinylSize / 2)
        .padding(.top, 165)
    }

    // MARK: - Vinyl Disc (GPU加速)

    private var vinylDisc: some View {
        RotatingVinylLayer(
            artwork: artwork,
            isRotating: isPlaying && isWindowVisible,
            isRotationEnabled: isRotationEnabled,
            vinylSize: vinylSize
        )
        .frame(width: vinylSize, height: vinylSize)
    }

    // MARK: - Time Overlay

    private var timeOverlay: some View {
        HStack {
            timeLabel(timeString(from: playbackProgressState.currentTime))
            Spacer()
            timeLabel(timeString(from: duration))
        }
        .padding(.horizontal, 12)
    }

    private func timeLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .light, design: .rounded))
            .foregroundColor(.timeDisplayColor)
            .frame(width: 60)
    }

    // MARK: - Utils

    private func timeString(from seconds: TimeInterval) -> String {
        guard seconds.isFinite, !seconds.isNaN else { return "0:00" }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

#Preview {
    VinylSectionView(
        artwork: nil,
        isPlaying: true,
        isRotationEnabled: true,
        duration: 240,
        isWindowVisible: true
    )
    .frame(height: 160)
    .padding()
    .background(Color.black)
}
