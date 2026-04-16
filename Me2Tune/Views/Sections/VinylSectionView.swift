//
//  VinylSectionView.swift
//  Me2Tune
//
//  唱片封面区域 - 半圆唱片+旋转动画（GPU加速优化版）
//

import AppKit
import SwiftUI

struct VinylSectionView: View {
    let artwork: NSImage?
    let isPlaying: Bool
    let isRotationEnabled: Bool
    let duration: TimeInterval
    let isWindowVisible: Bool
    var isRestoring: Bool = false

    @Environment(\.playbackProgressState) private var playbackProgressState

    private let vinylSize: CGFloat = 280

    var body: some View {
        ZStack(alignment: .bottom) {
            vinylDisc
            timeOverlay
                .offset(y: -147)
        }
        .frame(height: vinylSize / 2)
        .padding(.top, 166)
    }

    // MARK: - Vinyl Disc

    /// 恢复期间且无封面时，不渲染 RotatingVinylLayer，避免显示灰色吉他默认图标
    private var isRestoringWithNoArtwork: Bool {
        isRestoring && artwork == nil
    }

    @ViewBuilder
    private var vinylDisc: some View {
        if isRestoringWithNoArtwork {
            Color.clear
                .frame(width: vinylSize, height: vinylSize)
        } else {
            RotatingVinylLayer(
                artwork: artwork,
                shouldRotate: isPlaying && isRotationEnabled && isWindowVisible,
                vinylSize: vinylSize
            )
            .frame(width: vinylSize, height: vinylSize)
        }
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

#Preview("Normal - No Artwork") {
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

#Preview("Restoring - Blank") {
    VinylSectionView(
        artwork: nil,
        isPlaying: false,
        isRotationEnabled: true,
        duration: 0,
        isWindowVisible: true,
        isRestoring: true
    )
    .frame(height: 160)
    .padding()
    .background(Color.black)
}
