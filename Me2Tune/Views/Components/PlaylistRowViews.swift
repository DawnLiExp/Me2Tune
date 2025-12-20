//
//  PlaylistRowViews.swift
//  Me2Tune
//
//  播放列表行视图组件 - 支持拖动排序 + 列表行接收文件
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Draggable Track Row

struct DraggableTrackRow: View {
    let track: AudioTrack
    let index: Int
    let isPlaying: Bool
    let onSelect: () -> Void
    let onMove: (Int, Int) -> Void
    let onFilesDropped: ([URL]) -> Void
    
    @State private var isDropTarget = false
    
    var body: some View {
        TrackRowView(
            track: track,
            index: index,
            isPlaying: isPlaying,
            onSelect: onSelect,
        )
        .background(
            isDropTarget ? Color.orange.opacity(0.3) : Color.clear,
        )
        .onDrag {
            NSItemProvider(object: String(index) as NSString)
        }
        .onDrop(of: [.text, .fileURL], isTargeted: $isDropTarget) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        // 检查是否是内部排序（text类型）
        if let textProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) }) {
            textProvider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let sourceIndexString = String(data: data, encoding: .utf8),
                      let sourceIndex = Int(sourceIndexString)
                else {
                    return
                }
                
                DispatchQueue.main.async {
                    onMove(sourceIndex, index)
                }
            }
            return true
        }
        
        // 检查是否是文件拖入（fileURL类型）
        if providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
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
                if !urls.isEmpty {
                    onFilesDropped(urls)
                }
            }
            
            return true
        }
        
        return false
    }
}

// MARK: - Album Row View

struct AlbumRowView: View {
    let album: Album
    let artwork: NSImage?
    let isPlaying: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.orange)
                } else {
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 20, alignment: .center)
            
            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary),
                        )
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.system(size: 12, weight: isPlaying ? .semibold : .regular))
                    .lineLimit(1)
                
                Text("\(album.tracks.count) tracks")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isHovered {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            Group {
                if isPlaying {
                    Color.orange.opacity(0.15)
                } else if isHovered {
                    Color.white.opacity(0.05)
                } else {
                    Color.clear
                }
            },
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - Track Row View

struct TrackRowView: View {
    let track: AudioTrack
    let index: Int
    let isPlaying: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    private var trackNumber: Int {
        index + 1
    }
    
    private var trackNumberText: String {
        "\(trackNumber)"
    }
    
    private var numberOffsetX: CGFloat {
        if trackNumber < 10 {
            return 8.5
        } else {
            return 3.5
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.clear
                    .frame(width: 20)
                
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.orange)
                        .frame(width: 20, alignment: .center)
                } else {
                    Text(trackNumberText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, alignment: .leading)
                        .offset(x: numberOffsetX)
                }
            }
            
            Spacer()
                .frame(width: 12)
            
            Text(track.title)
                .font(.system(size: 12, weight: isPlaying ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isPlaying ? .primary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
                .frame(width: 8)
            
            Text(track.artist ?? String(localized: "unknown_artist"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 90, alignment: .leading)
            
            Spacer()
                .frame(width: 8)
            
            Text(formatTime(track.duration))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            Group {
                if isPlaying {
                    Color.orange.opacity(0.2)
                } else if isHovered {
                    Color.white.opacity(0.05)
                } else {
                    Color.clear
                }
            },
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(count: 2) {
            onSelect()
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, !time.isNaN else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
