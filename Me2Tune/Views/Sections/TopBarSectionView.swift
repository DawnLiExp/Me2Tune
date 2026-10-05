//
//  TopBarSectionView.swift
//  Me2Tune
//
//  顶部信息栏区域 - 应用信息和旋转开关
//

import SwiftUI

struct TopBarSectionView: View {
    var currentTrack: AudioTrack? = nil
    @Binding var isRotationEnabled: Bool
    let audioFormat: AudioFormat
    let onSearchTapped: () -> Void
    var onShowTagEditor: ((AudioTrack) -> Void)? = nil
        
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
                .offset(y: -10)
                .padding(.trailing, 8)
                
            rotationToggle
                .offset(y: -10)
                .padding(.trailing, 12)
        }
        .frame(height: 50)
    }
    
    // MARK: - Info Section
    
    private var infoSection: some View {
        HStack(spacing: 10) {
            Image(systemName: currentTrack != nil ? "music.note" : "headphones")
                .foregroundColor(.secondaryText)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(trackTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Text(trackSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.infoBackground)
        )
        .contextMenu {
            if let currentTrack {
                Button {
                    onShowTagEditor?(currentTrack)
                } label: {
                    Label(String(localized: "show_track_info", defaultValue: "显示简介"), systemImage: "info.circle")
                }
            }
        }
        .help(fullTooltipText)
    }

    private var trackTitle: String {
        if let track = currentTrack, !track.title.isEmpty {
            return track.title
        }
        return "Me2Tune"
    }

    private var trackSubtitle: String {
        guard let track = currentTrack else {
            let format = audioFormat.formattedString
            return format.isEmpty ? String(localized: "ready_to_play") : format
        }
        
        let artist = track.artist ?? ""
        let format = audioFormat.formattedString
        
        if !artist.isEmpty && !format.isEmpty {
            return "\(artist) • \(format)"
        } else if !artist.isEmpty {
            return artist
        } else if !format.isEmpty {
            return format
        } else {
            return String(localized: "ready_to_play")
        }
    }

    private var fullTooltipText: String {
        guard let track = currentTrack else { return "Me2Tune" }
        var parts: [String] = [track.title]
        if let artist = track.artist, !artist.isEmpty {
            parts.append(artist)
        }
        if let album = track.albumTitle, !album.isEmpty {
            parts.append(album)
        }
        let format = audioFormat.formattedString
        if !format.isEmpty {
            parts.append(format)
        }
        return parts.joined(separator: " • ")
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
