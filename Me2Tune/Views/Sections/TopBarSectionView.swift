//
//  TopBarSectionView.swift
//  Me2Tune
//
//  顶部信息栏区域 - 应用信息和旋转开关
//

import SwiftUI

struct TopBarSectionView: View {
    @Binding var isRotationEnabled: Bool
    let audioFormat: AudioFormat
    let onSearchTapped: () -> Void
        
    var body: some View {
        HStack {
            infoSection
                
            Spacer()
                
            #if DEBUG
            Button(action: {
                print("Current format: \(audioFormat.formattedString)")
                print("Codec: \(audioFormat.codec ?? "nil")")
                print("Bitrate: \(audioFormat.bitrate?.description ?? "nil")")
                print("SampleRate: \(audioFormat.sampleRate?.description ?? "nil")")
                print("BitDepth: \(audioFormat.bitDepth?.description ?? "nil")")
                print("Channels: \(audioFormat.channels?.description ?? "nil")")
            }) {
                Image(systemName: "ladybug")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            #endif
                
            searchButton
                .offset(y: -14)
                .padding(.trailing, 8)
                
            rotationToggle
                .offset(y: -14)
                .padding(.trailing, 12)
        }
        .frame(height: 50)
    }
    
    // MARK: - Info Section
    
    private var infoSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "headphones")
                .foregroundColor(.secondaryText)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Me2Tune")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primaryText)
                Text(audioFormat.formattedString)
                    .font(.system(size: 11))
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.infoBackground)
        )
    }
    
    // MARK: - Rotation Toggle

    private var searchButton: some View {
        Button(action: onSearchTapped) {
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondaryText)
                )
        }
        .buttonStyle(.plain)
    }

    private var rotationToggle: some View {
        Button(action: {
            isRotationEnabled.toggle()
        }) {
            Circle()
                .fill(isRotationEnabled ? Color.accent.opacity(0.8) : Color.white.opacity(0.15))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "record.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isRotationEnabled ? .black : .secondaryText)
                )
                .shadow(color: isRotationEnabled ? .accentGlow : .clear, radius: 10)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TopBarSectionView(
        isRotationEnabled: .constant(true),
        audioFormat: AudioFormat(
            codec: "AAC",
            bitrate: 256,
            sampleRate: 44100,
            bitDepth: 16,
            channels: 2
        ),
        onSearchTapped: {}
    )
    .frame(height: 170)
    .padding(.horizontal, 12)
    .background(Color.black)
}
