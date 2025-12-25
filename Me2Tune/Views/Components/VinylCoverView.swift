//
//  VinylCoverView.swift
//  Me2Tune
//
//  唱片封面视图：半圆唱片+旋转动画
//

import AppKit
import SwiftUI

struct VinylCoverView: View {
    let artwork: NSImage?
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        ZStack(alignment: .bottom) {
            vinylCover
            
            HStack {
                timeLabel(timeString(from: currentTime))
                Spacer()
                timeLabel(timeString(from: duration))
            }
            .offset(y: -8)
        }
        .onAppear {
            startRotation()
        }
        .onChange(of: isPlaying) { _, _ in
            updateRotation()
        }
    }
    
    // MARK: - Time Labels
    
    private func timeLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .light, design: .rounded))
            .foregroundColor(.white.opacity(0.8))
            .frame(width: 60)
    }
    
    // MARK: - Vinyl Cover
    
    private var vinylCover: some View {
        ZStack {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.15), Color(white: 0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 280, height: 280)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
                    )
                    .rotationEffect(.degrees(rotationAngle))
                    .shadow(color: .black.opacity(0.6), radius: 20, y: 12)
                
                Circle()
                    .fill(Color(white: 0.12))
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .fill(Color(white: 0.2))
                            .frame(width: 30, height: 30)
                    )
                    .rotationEffect(.degrees(rotationAngle))
                
                Group {
                    if let artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .scaledToFit()
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
                .rotationEffect(.degrees(rotationAngle))
            }
            .offset(y: 80)
        }
        .frame(height: 160)
        .clipped()
    }
    
    // MARK: - Rotation Animation
    
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
    
    private func timeString(from seconds: TimeInterval) -> String {
        guard seconds.isFinite, !seconds.isNaN else { return "0:00" }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

#Preview {
    VinylCoverView(
        artwork: nil,
        isPlaying: true,
        currentTime: 130,
        duration: 240
    )
    .frame(height: 160)
    .padding()
    .background(Color.black)
}
