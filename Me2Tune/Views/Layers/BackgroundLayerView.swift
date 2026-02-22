//
//  BackgroundLayerView.swift
//  Me2Tune
//
//  背景光晕层 - 支持传统光晕和 MeshGradient 模式切换
//

import SwiftUI

struct BackgroundLayerView: View {
    let albumGlowColor: Color
    
    @AppStorage("CleanMode") private var cleanMode = false
    @AppStorage("backgroundGlowMode") private var glowMode = BackgroundGlowMode.legacy.rawValue
    @AppStorage("glowBreathingRate") private var breathingRate = GlowBreathingRate.medium.rawValue
    @AppStorage("glowBreathingIntensity") private var breathingIntensity = GlowBreathingIntensity.medium.rawValue
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.gradientTop, .mainBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // 简洁模式下隐藏光晕
            if !cleanMode {
                glowView
                    .drawingGroup()
            }
        }
    }
    
    // MARK: - Glow View
    
    @ViewBuilder
    private var glowView: some View {
        if let mode = BackgroundGlowMode(rawValue: glowMode) {
            switch mode {
            case .legacy:
                LegacyGlowView(albumGlowColor: albumGlowColor)
            case .meshGradient:
                if #available(macOS 15.0, *) {
                    MeshGradientGlowView(albumGlowColor: albumGlowColor)
                } else {
                    // Fallback to legacy for macOS < 15
                    LegacyGlowView(albumGlowColor: albumGlowColor)
                }
            }
        } else {
            LegacyGlowView(albumGlowColor: albumGlowColor)
        }
    }
}

// MARK: - Background Glow Mode

enum BackgroundGlowMode: String, CaseIterable, Identifiable {
    case legacy
    case meshGradient
    
    var id: String {
        rawValue
    }
    
    var displayName: LocalizedStringKey {
        switch self {
        case .legacy:
            return "glow_mode_legacy"
        case .meshGradient:
            return "glow_mode_mesh"
        }
    }
}

// MARK: - Glow Breathing Rate

enum GlowBreathingRate: String, CaseIterable, Identifiable {
    case verySlow
    case slow
    case medium
    case fast
    case veryFast
    
    var id: String {
        rawValue
    }
    
    var displayName: LocalizedStringKey {
        switch self {
        case .verySlow:
            return "glow_rate_very_slow"
        case .slow:
            return "glow_rate_slow"
        case .medium:
            return "glow_rate_medium"
        case .fast:
            return "glow_rate_fast"
        case .veryFast:
            return "glow_rate_very_fast"
        }
    }
    
    var frequency: Double {
        switch self {
        case .verySlow: return 0.4
        case .slow: return 0.6
        case .medium: return 0.785
        case .fast: return 1.0
        case .veryFast: return 1.3
        }
    }
}

// MARK: - Glow Breathing Intensity

enum GlowBreathingIntensity: String, CaseIterable, Identifiable {
    case gentle
    case medium
    case strong
    
    var id: String {
        rawValue
    }
    
    var displayName: LocalizedStringKey {
        switch self {
        case .gentle:
            return "glow_intensity_gentle"
        case .medium:
            return "glow_intensity_medium"
        case .strong:
            return "glow_intensity_strong"
        }
    }
    
    var amplitude: Double {
        switch self {
        case .gentle: return 0.06
        case .medium: return 0.12
        case .strong: return 0.20
        }
    }
    
    var baseOpacity: Double {
        switch self {
        case .gentle: return 0.75
        case .medium: return 0.72
        case .strong: return 0.70
        }
    }
}

// MARK: - Legacy Glow View

private struct LegacyGlowView: View {
    let albumGlowColor: Color
    
    var body: some View {
        Group {
            vinylGlowLayer
            playlistGlowLayer
        }
    }
    
    // MARK: - Vinyl Glow
    
    private var vinylGlowLayer: some View {
        VStack {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                albumGlowColor.opacity(0.58),
                                albumGlowColor.opacity(0.31),
                                albumGlowColor.opacity(0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 60,
                            endRadius: 250
                        )
                    )
                    .frame(width: 480, height: 320)
                    .blur(radius: 30)
            }
            .offset(y: 66)
            
            Spacer()
        }
        .allowsHitTesting(false)
    }
    
    // MARK: - Playlist Glow
    
    private var playlistGlowLayer: some View {
        VStack {
            Spacer()
            
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.accent.opacity(0.16),
                            Color.accent.opacity(0.08),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 80,
                        endRadius: 220
                    )
                )
                .frame(width: 480, height: 150)
                .blur(radius: 30)
                .padding(.bottom, 40)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - MeshGradient Glow View (macOS 15+)

@available(macOS 15.0, *)
private struct MeshGradientGlowView: View {
    let albumGlowColor: Color
    
    @AppStorage("glowBreathingRate") private var breathingRateRaw = GlowBreathingRate.medium.rawValue
    @AppStorage("glowBreathingIntensity") private var breathingIntensityRaw = GlowBreathingIntensity.medium.rawValue
    
    private var breathingRate: GlowBreathingRate {
        GlowBreathingRate(rawValue: breathingRateRaw) ?? .medium
    }
    
    private var breathingIntensity: GlowBreathingIntensity {
        GlowBreathingIntensity(rawValue: breathingIntensityRaw) ?? .medium
    }
    
    @State private var phase: Double = 0
    @State private var intensity: Double = 0.8
    @State private var accumulatedPhase: Double = 0
    @State private var lastUpdateTime: Date = .init()
    
    // 窗口最小化状态 - 用于暂停动画循环，避免 Dock 后持续 CPU 占用
    @State private var isMiniaturized = false
    
    var body: some View {
        vinylGlowMesh
            .allowsHitTesting(false)
            .task(id: "\(breathingRateRaw)-\(breathingIntensityRaw)-\(isMiniaturized)") {
                await startBreathingEffect()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)
            ) { _ in
                isMiniaturized = true
            }
            .onReceive(
                NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)
            ) { _ in
                isMiniaturized = false
            }
    }
    
    // MARK: - Vinyl Glow Mesh
    
    private var vinylGlowMesh: some View {
        MeshGradient(
            width: 5,
            height: 5,
            points: meshPoints,
            colors: meshColors
        )
        .opacity(intensity)
    }
    
    // MARK: - Animation Logic
    
    @MainActor
    private func startBreathingEffect() async {
        // 窗口已最小化 → 不启动循环，直接退出
        guard !isMiniaturized else { return }
        
        lastUpdateTime = Date()
        let sleepMs = 120
        
        while !Task.isCancelled {
            let now = Date()
            let delta = now.timeIntervalSince(lastUpdateTime)
            lastUpdateTime = now
            
            let frequency = breathingRate.frequency
            accumulatedPhase += delta * frequency
            
            let rawSin = sin(accumulatedPhase)
            let smoothPhase = pow((rawSin + 1.0) / 2.0, 2.5) * 2.0 - 1.0
   
            let subtleWave = sin(accumulatedPhase * 2.5) * 0.05
            
            // 使用用户设置的强度
            let amplitude = breathingIntensity.amplitude
            let baseOpacity = breathingIntensity.baseOpacity
            let newIntensity = baseOpacity + (amplitude * (smoothPhase * 0.9 + subtleWave * 0.1))
            
            if abs(intensity - newIntensity) > 0.002 || abs(phase - smoothPhase) > 0.005 {
                phase = smoothPhase
                intensity = newIntensity
            }
            
            try? await Task.sleep(for: .milliseconds(sleepMs))
        }
    }
    
    // MARK: - Mesh Definition
    
    private var meshPoints: [SIMD2<Float>] {
        let offset = Float(phase) * 0.012
        
        return [
            // Row 0 - 顶部边缘
            SIMD2(0.0, 0.0), SIMD2(0.25, 0.0), SIMD2(0.5, 0.0), SIMD2(0.75, 0.0), SIMD2(1.0, 0.0),
            
            // Row 1 - 唱片上方区域
            SIMD2(0.0, 0.1525),
            SIMD2(0.25, 0.1225 + offset),
            SIMD2(0.5, 0.1025 + offset * 1.2),
            SIMD2(0.75, 0.1225 + offset),
            SIMD2(1.0, 0.1525),
            
            // Row 2 - 唱片中心区域
            SIMD2(0.0, 0.3025),
            SIMD2(0.25, 0.2825 + offset * 0.4),
            SIMD2(0.5, 0.2625 + offset * 0.8),
            SIMD2(0.75, 0.2825 + offset * 0.4),
            SIMD2(1.0, 0.3025),
            
            // Row 3 - 播放控件区域
            SIMD2(0.0, 0.50), SIMD2(0.25, 0.50), SIMD2(0.5, 0.50), SIMD2(0.75, 0.50), SIMD2(1.0, 0.50),
            
            // Row 4 - 底部区域
            SIMD2(0.0, 1.0), SIMD2(0.25, 1.0), SIMD2(0.5, 1.0), SIMD2(0.75, 1.0), SIMD2(1.0, 1.0)
        ]
    }
    
    private var meshColors: [Color] {
        let normalizedPhase = (phase + 1.0) / 2.0
        let pulse = normalizedPhase * breathingIntensity.amplitude
        
        return [
            // Row 0
            .gradientTop.opacity(0.3),
            .gradientTop.opacity(0.5),
            .gradientTop.opacity(0.6),
            .gradientTop.opacity(0.5),
            .gradientTop.opacity(0.3),
            
            // Row 1
            albumGlowColor.opacity(0.06 + pulse * 0.4),
            albumGlowColor.opacity(0.26 + pulse * 1.1),
            albumGlowColor.opacity(0.44 + pulse),
            albumGlowColor.opacity(0.26 + pulse * 1.1),
            albumGlowColor.opacity(0.06 + pulse * 0.4),
            
            // Row 2
            albumGlowColor.opacity(0.12 + pulse * 0.4),
            albumGlowColor.opacity(0.52 + pulse * 0.8),
            albumGlowColor.opacity(0.62 + pulse),
            albumGlowColor.opacity(0.52 + pulse * 0.8),
            albumGlowColor.opacity(0.12 + pulse * 0.4),
            
            // Row 3
            .mainBackground.opacity(0.2),
            albumGlowColor.opacity(0.10 + pulse * 0.2),
            albumGlowColor.opacity(0.22 + pulse * 0.4),
            albumGlowColor.opacity(0.10 + pulse * 0.2),
            .mainBackground.opacity(0.2),
            
            // Row 4
            .mainBackground,
            .mainBackground,
            .mainBackground,
            .mainBackground,
            .mainBackground
        ]
    }
}

#Preview {
    BackgroundLayerView(albumGlowColor: .green)
        .ignoresSafeArea()
        .frame(width: 495, height: 800)
}
