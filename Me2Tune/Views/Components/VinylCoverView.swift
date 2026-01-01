//
//  VinylCoverView.swift
//  Me2Tune
//
//  唱片封面视图：半圆唱片+旋转动画（窗口不可见时暂停）
//

import AppKit
import SwiftUI

// MARK: - Top Half Circle Shape（尺寸 = 完整圆）

struct TopHalfCircleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let radius = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)

        // 上半圆：180° → 0°
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )

        return path
    }
}

// MARK: - VinylCoverView

struct VinylCoverView: View {
    let artwork: NSImage?
    let isPlaying: Bool
    let isRotationEnabled: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isWindowVisible: Bool

    @State private var rotationAngle: Double = 0
    @State private var rotationTimer: Timer?

    private let vinylSize: CGFloat = 280

    var body: some View {
        ZStack(alignment: .bottom) {
            vinylDisc
            timeOverlay
                .offset(y: -147)
        }
        .frame(height: vinylSize / 2)
        .padding(.top, 165)
        .onAppear {
            updateRotationTimer()
        }
        .onChange(of: isPlaying) { _, _ in
            updateRotationTimer()
        }
        .onChange(of: isRotationEnabled) { _, _ in
            updateRotationTimer()
        }
        .onChange(of: isWindowVisible) { _, _ in
            updateRotationTimer()
        }
        .onDisappear {
            stopRotation()
        }
    }

    // MARK: - Vinyl Disc

    private var vinylDisc: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.16),
                            Color(white: 0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: vinylSize, height: vinylSize)
                .rotationEffect(.degrees(rotationAngle))
                .mask(
                    TopHalfCircleShape()
                        .frame(width: vinylSize, height: vinylSize)
                )
                .shadow(color: .black.opacity(0.6), radius: 20, y: 12)

            artworkView
                .rotationEffect(.degrees(rotationAngle))
                .mask(
                    TopHalfCircleShape()
                        .frame(width: vinylSize, height: vinylSize)
                )

            centerHole
                .rotationEffect(.degrees(rotationAngle))
                .mask(
                    TopHalfCircleShape()
                        .frame(width: vinylSize, height: vinylSize)
                )
        }
    }

    // MARK: - Center Hole

    private var centerHole: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(white: 0.18),
                            Color(white: 0.12)
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 50
                    )
                )
                .frame(width: 100, height: 100)

            Circle()
                .fill(Color.black.opacity(0.9))
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.8), radius: 8, y: 2)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.35, y: 0.35),
                        startRadius: 0,
                        endRadius: 15
                    )
                )
                .frame(width: 30, height: 30)
        }
    }

    // MARK: - Artwork

    private var artworkView: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "guitars.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.gray)
                    .padding(38)
            }
        }
        .frame(width: 255, height: 255)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 2.5)
        )
    }

    // MARK: - Time Overlay

    private var timeOverlay: some View {
        HStack {
            timeLabel(timeString(from: currentTime))
            Spacer()
            timeLabel(timeString(from: duration))
        }
        .padding(.horizontal, 12)
    }

    private func timeLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .light, design: .rounded))
            .foregroundColor(.white.opacity(0.8))
            .frame(width: 60)
    }

    // MARK: - Rotation Logic

    private func updateRotationTimer() {
        // 只有在窗口可见、正在播放、且旋转开启时才旋转
        let shouldRotate = isWindowVisible && isPlaying && isRotationEnabled

        if shouldRotate {
            startRotation()
        } else {
            stopRotation()
            if !isRotationEnabled {
                rotationAngle = 0
            }
        }
    }

    private func startRotation() {
        guard rotationTimer == nil else { return }

        rotationTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [self] _ in
            DispatchQueue.main.async { [self] in
                rotationAngle += 0.15
                if rotationAngle >= 360 {
                    rotationAngle -= 360
                }
            }
        }
    }

    private func stopRotation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
    }

    // MARK: - Utils

    private func timeString(from seconds: TimeInterval) -> String {
        guard seconds.isFinite, !seconds.isNaN else { return "0:00" }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Preview

#Preview {
    VinylCoverView(
        artwork: nil,
        isPlaying: true,
        isRotationEnabled: true,
        currentTime: 128,
        duration: 240,
        isWindowVisible: true
    )
    .frame(height: 160)
    .padding()
    .background(Color.black)
}
