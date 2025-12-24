//
//  ContentView.swift
//  Me2Tune
//
//  主界面视图
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var playerManager: AudioPlayerManager
    @EnvironmentObject private var collectionManager: CollectionManager
    
    @State private var rotationAngle: Double = 0
    @State private var isPlaylistCollapsed = false
    @State private var albumGlowColor = Color(hex: "#FF4466")
    @State private var isSeekingManually = false
    @State private var manualSeekValue: TimeInterval = 0
    @State private var isDragging = false
    
    private var isRotating: Bool {
        playerManager.isPlaying
    }
    
    var body: some View {
        ZStack {
            baseBackground
            vinylGlowLayer
            playlistGlowLayer
            
            VStack(spacing: 0) {
                topBar
                    .frame(height: 70)
                    .padding(.horizontal, 12)
                
                Spacer()
                    .frame(height: 18)
                
                albumCoverSection
                    .frame(height: 160)
                    .padding(.horizontal, 12)
                
                playbackControlPanel
                    .fixedSize(horizontal: false, vertical: true)

                songListSection
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 495, maxWidth: .infinity, minHeight: 775, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .onAppear {
            startRotation()
        }
        .onChange(of: playerManager.isPlaying) { _, _ in
            updateRotation()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers: providers)
        }
    }
    
    // MARK: - Background Layers
    
    private var baseBackground: some View {
        LinearGradient(
            colors: [
                Color(white: 0.02),
                Color.black
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    private var vinylGlowLayer: some View {
        VStack {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                albumGlowColor.opacity(0.6),
                                albumGlowColor.opacity(0.35),
                                albumGlowColor.opacity(0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 60,
                            endRadius: 280
                        )
                    )
                    .frame(width: 400, height: 400)
                    .blur(radius: 40)
                
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                albumGlowColor.opacity(0.25),
                                albumGlowColor.opacity(0.1),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 460, height: 280)
                    .blur(radius: 35)
                    .offset(y: 80)
            }
            .offset(y: 0)
            
            Spacer()
        }
    }
    
    private var playlistGlowLayer: some View {
        VStack {
            Spacer()
            
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "#00E5FF").opacity(0.25),
                            Color(hex: "#00E5FF").opacity(0.12),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 80,
                        endRadius: 320
                    )
                )
                .frame(width: 460, height: 180)
                .blur(radius: 35)
                .padding(.bottom, 40)
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .foregroundColor(.gray)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Me2Tune")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Text("AAC | 264 kbps | 16 bit | 44.1 kHz | Stereo")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.08))
            )
            
            Spacer()
            
            rotationButton
                .offset(y: -18)
                .padding(.trailing, 12)
        }
        .frame(height: 50)
    }
    
    private var rotationButton: some View {
        Button(action: {
            playerManager.togglePlayPause()
        }) {
            Circle()
                .fill(isRotating ? Color(hex: "#00E5FF").opacity(0.9) : Color.white.opacity(0.15))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "record.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isRotating ? .black : .gray)
                )
                .shadow(color: isRotating ? Color(hex: "#00E5FF").opacity(0.6) : .clear, radius: 10)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Album Cover Section
    
    private var albumCoverSection: some View {
        ZStack(alignment: .bottom) {
            vinylCover
            
            HStack {
                timeLabel(timeString(from: playerManager.currentTime))
                Spacer()
                timeLabel(timeString(from: playerManager.duration))
            }
            .offset(y: -8)
        }
    }
    
    private func timeLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .light, design: .rounded))
            .foregroundColor(.white.opacity(0.8))
            .frame(width: 60)
    }
    
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
                    if let artwork = playerManager.currentArtwork {
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

    // MARK: - Playback Control Panel
    
    private var playbackControlPanel: some View {
        VStack(spacing: 0) {
            progressBar
                .frame(height: 3)
                .padding(.horizontal, 28)
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(playerManager.currentTrack?.title ?? "No Track")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(hex: "#00E5FF"))
                        .lineLimit(1)
                    
                    Text(trackSubtitle)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                
                Spacer()
                
                HStack(spacing: 26) {
                    controlButton(
                        icon: "backward.fill",
                        size: 18,
                        enabled: canGoPrevious,
                        action: { playerManager.previous() }
                    )
                    
                    customPlayButton
                    
                    controlButton(
                        icon: "forward.fill",
                        size: 18,
                        enabled: canGoNext,
                        action: { playerManager.next() }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(white: 0.12).opacity(0.85))
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            )
            .padding(.horizontal, 12)
        }
    }
    
    private var trackSubtitle: String {
        guard let track = playerManager.currentTrack else {
            return "Ready to play"
        }
        
        let artist = track.artist ?? "Unknown Artist"
        let album = track.albumTitle ?? ""
        
        if album.isEmpty {
            return artist
        } else {
            return "\(artist) • \(album)"
        }
    }
    
    private var canGoPrevious: Bool {
        guard let index = playerManager.currentTrackIndex else { return false }
        return index > 0
    }
    
    private var canGoNext: Bool {
        guard let index = playerManager.currentTrackIndex else { return false }
        return index < playerManager.currentTracks.count - 1
    }
    
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#00E5FF"), Color(hex: "#00E5FF").opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * progress)
                    .shadow(color: Color(hex: "#00E5FF").opacity(0.5), radius: 4)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isSeekingManually {
                            isSeekingManually = true
                        }
                        let newProgress = min(max(0, value.location.x / geometry.size.width), 1)
                        manualSeekValue = newProgress * max(playerManager.duration, 0.1)
                    }
                    .onEnded { value in
                        let newProgress = min(max(0, value.location.x / geometry.size.width), 1)
                        let seekTime = newProgress * max(playerManager.duration, 0.1)
                        playerManager.seek(to: seekTime)
                        isSeekingManually = false
                    }
            )
        }
    }
    
    private var progress: CGFloat {
        let time = isSeekingManually ? manualSeekValue : playerManager.currentTime
        let total = max(playerManager.duration, 0.1)
        return CGFloat(min(max(time / total, 0), 1))
    }
    
    private var customPlayButton: some View {
        Button(action: {
            playerManager.togglePlayPause()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.3), radius: 6)
                
                Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(playerManager.currentTrack == nil)
        .opacity(playerManager.currentTrack == nil ? 0.5 : 1.0)
    }
    
    private func controlButton(icon: String, size: CGFloat, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(enabled ? .white.opacity(0.7) : .white.opacity(0.3))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!enabled)
    }
    
    // MARK: - Song List Section
    
    private var songListSection: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if playerManager.playlist.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(Array(playerManager.playlist.enumerated()), id: \.element.id) { index, track in
                            songRow(track: track, index: index)
                                .contextMenu {
                                    Button("Show in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([track.url])
                                    }
                                    
                                    Divider()
                                    
                                    Button("Remove") {
                                        playerManager.removeTrack(at: index)
                                    }
                                }
                            
                            if index < playerManager.playlist.count - 1 {
                                Divider()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 48)
            }
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(hex: "#00E5FF").opacity(0.3),
                                        Color(hex: "#00E5FF").opacity(0.0)
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                ),
                                lineWidth: 1.5
                            )
                    )
            )
            
            collapseButton
                .offset(y: 8)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("Drop Audio Files Here")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.gray)
            
            Text("Supports MP3, AAC, WAV, AIFF, FLAC, APE, and more")
                .font(.system(size: 12))
                .foregroundColor(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
    
    private func songRow(track: AudioTrack, index: Int) -> some View {
        let isPlaying = playerManager.playingSource == .playlist && playerManager.currentTrackIndex == index
        
        return HStack(spacing: 12) {
            Group {
                if isPlaying {
                    Image(systemName: "waveform")
                        .foregroundColor(Color(hex: "#00E5FF"))
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 24)
            
            Text(track.title)
                .font(.system(size: 14, weight: isPlaying ? .semibold : .regular))
                .foregroundColor(isPlaying ? .white : .white.opacity(0.8))
                .lineLimit(1)
            
            Spacer()
            
            Text(track.artist ?? "Unknown Artist")
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .trailing)
            
            Text(formatTime(track.duration))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isPlaying ? Color(hex: "#00E5FF").opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            playerManager.playTrack(at: index)
        }
    }
    
    private var collapseButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4)) {
                isPlaylistCollapsed.toggle()
            }
        }) {
            ZStack {
                Capsule()
                    .fill(Color(hex: "#00E5FF").opacity(0.2))
                    .frame(width: 64, height: 6)
                    .shadow(color: Color(hex: "#00E5FF").opacity(0.4), radius: 6)
                
                Image(systemName: isPlaylistCollapsed ? "chevron.compact.up" : "chevron.compact.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "#00E5FF"))
                    .offset(y: isPlaylistCollapsed ? -12 : 12)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Drag & Drop
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                continue
            }
            
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                defer { group.leave() }
                if let url {
                    urls.append(url)
                }
            }
        }
        
        group.notify(queue: .main) {
            let allURLs = expandFolders(urls)
            playerManager.addTracks(urls: allURLs)
        }
        
        return true
    }
    
    private func expandFolders(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        let fileManager = FileManager.default
        let supportedExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ape", "wv", "tta", "mpc"]
        
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }
            
            if isDirectory.boolValue {
                if let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for case let fileURL as URL in enumerator {
                        if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                            result.append(fileURL)
                        }
                    }
                }
            } else {
                if supportedExtensions.contains(url.pathExtension.lowercased()) {
                    result.append(url)
                }
            }
        }
        
        return result
    }
    
    // MARK: - Helper Functions
    
    private func startRotation() {
        Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            if isRotating {
                rotationAngle += 0.15
                if rotationAngle >= 360 {
                    rotationAngle -= 360
                }
            }
        }
    }
    
    private func updateRotation() {
        if !isRotating {
            rotationAngle = 0
        }
    }
    
    private func timeString(from seconds: TimeInterval) -> String {
        guard seconds.isFinite, !seconds.isNaN else { return "0:00" }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, !time.isNaN else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AudioPlayerManager())
        .environmentObject(CollectionManager())
}
