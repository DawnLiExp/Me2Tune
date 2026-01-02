//
//  PlaylistTabView.swift
//  Me2Tune
//
//  播放列表视图 - 歌曲列表 + 拖拽排序 + 文件拖拽添加（优化悬浮性能）
//

import SwiftUI
import UniformTypeIdentifiers

struct PlaylistTabView: View {
    @Binding var selectedTab: PlaylistTab
    let tracks: [AudioTrack]
    let currentIndex: Int?
    let playingSource: PlayerViewModel.PlayingSource
    let onTrackSelected: (Int) -> Void
    let onTrackRemoved: (Int) -> Void
    let onTrackMoved: (IndexSet, Int) -> Void
    let onFilesDrop: ([URL]) -> Void
    
    @State private var draggingIndex: Int?
    @State private var dropTargetIndex: Int?
    @State private var hoveredIndex: Int? // 共享 hover 状态，减少状态更新
    
    var body: some View {
        Group {
            if tracks.isEmpty {
                emptyStateView
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            VStack(spacing: 0) {
                                if dropTargetIndex == index {
                                    dropIndicator
                                }
                                
                                songRow(track: track, index: index)
                            }
                        }
                        
                        if !tracks.isEmpty {
                            VStack(spacing: 0) {
                                if dropTargetIndex == tracks.count {
                                    dropIndicator
                                }
                                
                                Color.clear
                                    .frame(height: 20)
                                    .onDrop(of: [.text, .fileURL], delegate: TrackDropDelegate(
                                        targetIndex: tracks.count,
                                        draggingIndex: $draggingIndex,
                                        dropTargetIndex: $dropTargetIndex,
                                        onDrop: { from, _ in
                                            let fromSet = IndexSet(integer: from)
                                            onTrackMoved(fromSet, tracks.count - 1)
                                        },
                                        onFilesDrop: onFilesDrop
                                    ))
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }
    
    // MARK: - Drop Indicator
    
    private var dropIndicator: some View {
        Rectangle()
            .fill(Color.accent)
            .frame(height: 2)
            .padding(.horizontal, 10)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.emptyStateIcon)
            
            Text("drop_files")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondaryText)
            
            Text("supported_formats")
                .font(.system(size: 12))
                .foregroundColor(.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 80)
    }
    
    // MARK: - Song Row
    
    private func songRow(track: AudioTrack, index: Int) -> some View {
        SongRowView(
            track: track,
            index: index,
            isPlaying: playingSource == .playlist && currentIndex == index,
            isHovered: hoveredIndex == index, // 使用共享状态
            onTap: { onTrackSelected(index) },
            onHoverChange: { isHovered in
                hoveredIndex = isHovered ? index : nil
            }
        )
        .opacity(draggingIndex == index ? 0.5 : 1.0)
        .onDrag {
            draggingIndex = index
            return NSItemProvider(object: "\(index)" as NSString)
        }
        .onDrop(of: [.text, .fileURL], delegate: TrackDropDelegate(
            targetIndex: index,
            draggingIndex: $draggingIndex,
            dropTargetIndex: $dropTargetIndex,
            onDrop: { from, to in
                guard from != to else { return }
                let fromSet = IndexSet(integer: from)
                var destination = to
                if from < to {
                    destination = to - 1
                }
                onTrackMoved(fromSet, destination)
            },
            onFilesDrop: onFilesDrop
        ))
        .contextMenu {
            Button("show_in_finder") {
                NSWorkspace.shared.activateFileViewerSelecting([track.url])
            }
            
            Divider()
            
            Button("remove") {
                onTrackRemoved(index)
            }
        }
    }
}

// MARK: - Track Drop Delegate

struct TrackDropDelegate: DropDelegate {
    let targetIndex: Int
    @Binding var draggingIndex: Int?
    @Binding var dropTargetIndex: Int?
    let onDrop: (Int, Int) -> Void
    let onFilesDrop: ([URL]) -> Void
    
    func dropEntered(info: DropInfo) {
        guard draggingIndex != nil, draggingIndex != targetIndex else { return }
        dropTargetIndex = targetIndex
    }
    
    func dropExited(info: DropInfo) {
        dropTargetIndex = nil
    }
    
    func performDrop(info: DropInfo) -> Bool {
        dropTargetIndex = nil
        
        if info.hasItemsConforming(to: [.fileURL]) {
            return handleFilesDrop(info: info)
        } else if let from = draggingIndex {
            draggingIndex = nil
            guard from != targetIndex else { return false }
            onDrop(from, targetIndex)
            return true
        }
        
        return false
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        if info.hasItemsConforming(to: [.fileURL]) {
            return DropProposal(operation: .copy)
        } else {
            return DropProposal(operation: .move)
        }
    }
    
    private func handleFilesDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        
        Task { @MainActor in
            var urls: [URL] = []
            
            for provider in providers {
                guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                    continue
                }
                
                do {
                    let item = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
                    
                    if let url = item as? URL {
                        urls.append(url)
                    } else if let data = item as? Data,
                              let string = String(data: data, encoding: .utf8)
                    {
                        if let url = URL(string: string) {
                            urls.append(url)
                        } else {
                            let url = URL(fileURLWithPath: string)
                            urls.append(url)
                        }
                    } else if let string = item as? String {
                        if let url = URL(string: string) {
                            urls.append(url)
                        } else {
                            let url = URL(fileURLWithPath: string)
                            urls.append(url)
                        }
                    }
                } catch {
                    continue
                }
            }
            
            onFilesDrop(urls)
        }
        
        return true
    }
}

// MARK: - Tab Enum

enum PlaylistTab {
    case playlist
    case collections
}

#Preview {
    PlaylistTabView(
        selectedTab: .constant(.playlist),
        tracks: [],
        currentIndex: nil,
        playingSource: .playlist,
        onTrackSelected: { _ in },
        onTrackRemoved: { _ in },
        onTrackMoved: { _, _ in },
        onFilesDrop: { _ in }
    )
    .padding()
    .background(Color.black)
}
