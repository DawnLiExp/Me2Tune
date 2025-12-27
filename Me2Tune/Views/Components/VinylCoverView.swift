//
//  VinylCoverView.swift
//  Me2Tune
//
//  唱片封面视图：半圆唱片+旋转动画
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

        // 不闭合下半圆（直接结束）
        return path
    }
}

// MARK: - VinylCoverView

struct VinylCoverView: View {
    let artwork: NSImage?
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval

    @State private var rotationAngle: Double = 0

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
            startRotation()
        }
        .onChange(of: isPlaying) { _, _ in
            updateRotation()
        }
    }

    // MARK: - Vinyl Disc (真正的上半圆)

    private var vinylDisc: some View {
        ZStack {
            // 主唱片
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

            // 中心底盘
            Circle()
                .fill(Color(white: 0.12))
                .frame(width: 100, height: 100)
                .overlay(
                    Circle()
                        .fill(Color(white: 0.22))
                        .frame(width: 30, height: 30)
                )
                .rotationEffect(.degrees(rotationAngle))
                .mask(
                    TopHalfCircleShape()
                        .frame(width: vinylSize, height: vinylSize)
                )

            // 封面
            artworkView
                .rotationEffect(.degrees(rotationAngle))
                .mask(
                    TopHalfCircleShape()
                        .frame(width: vinylSize, height: vinylSize)
                )
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
                Image(systemName: "music.note")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.gray)
                    .padding(80)
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

    // MARK: - Rotation

    private func startRotation() {
        Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            if isPlaying {
                rotationAngle += 0.15
                if rotationAngle >= 360 {
                    rotationAngle -= 360
                }
            }
        }
    }

    private func updateRotation() {
        if !isPlaying {
            rotationAngle = 0
        }
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
        currentTime: 128,
        duration: 240
    )
    .frame(height: 160)
    .padding()
    .background(Color.black)
}
