//
//  VinylSectionView.swift
//  Me2Tune
//
//  唱片封面区域 - 半圆唱片+旋转动画（优化刷新率）
//

import AppKit
import SwiftUI

// MARK: - Top Half Circle Shape

struct TopHalfCircleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let radius = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)

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

// MARK: - VinylSectionView

struct VinylSectionView: View {
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

    // 优化:将旋转部分独立为 RotatingVinyl,避免整个视图重建
    private var vinylDisc: some View {
        RotatingVinyl(
            rotationAngle: rotationAngle,
            vinylSize: vinylSize,
            artwork: artwork
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
            .font(.system(size: 15, weight: .light, design: .rounded))
            .foregroundColor(.timeDisplayColor)
            .frame(width: 60)
    }

    // MARK: - Rotation Logic

    private func updateRotationTimer() {
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

        // 优化:降低刷新率 0.033 -> 0.05 (从 30fps -> 20fps)
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [self] _ in
            DispatchQueue.main.async { [self] in
                rotationAngle += 0.5 // 调整旋转步长保持视觉流畅度
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

// MARK: - Rotating Vinyl (独立旋转组件)

struct RotatingVinyl: View {
    let rotationAngle: Double
    let vinylSize: CGFloat
    let artwork: NSImage?

    var body: some View {
        ZStack {
            // 唱片底盘
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

            // 封面
            artworkView
                .rotationEffect(.degrees(rotationAngle))
                .mask(
                    TopHalfCircleShape()
                        .frame(width: vinylSize, height: vinylSize)
                )

            // 中心孔
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
}

#Preview {
    VinylSectionView(
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
