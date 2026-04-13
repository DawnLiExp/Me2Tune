//
//  PlaylistTabView.swift
//  Me2Tune
//
//  播放列表视图 - 歌曲列表 + 拖拽排序 + 文件拖拽添加 + 失败标记
//

import SwiftUI
import UniformTypeIdentifiers

struct PlaylistTabView: View {
    @Binding var selectedTab: PlaylistTab
    let tracks: [AudioTrack]
    let currentIndex: Int?
    let playingSource: PlayerViewModel.PlayingSource
    let isLoadingTracks: Bool
    let loadingTracksCount: Int
    let onTrackSelected: (Int) -> Void
    let onTrackRemoved: (Int) -> Void
    let onTrackMoved: (IndexSet, Int) -> Void
    let onFilesDrop: ([URL]) -> Void
    
    @State private var draggingIndex: Int?
    @State private var dropTargetIndex: Int?
    
    // 从 environment 获取 PlayerViewModel
    @Environment(PlayerViewModel.self) private var playerViewModel
    
    var body: some View {
        Group {
            if tracks.isEmpty, !isLoadingTracks {
                emptyStateView
            } else {
                ZStack {
                    @Bindable var viewModel = playerViewModel
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
                        .scrollTargetLayout()
                    }
                    .scrollPosition(id: $viewModel.lastScrollTrackId)
                    .frame(maxHeight: .infinity)
                    
                    if isLoadingTracks {
                        loadingOverlay
                    }
                }
            }
        }
        // 外层兜底：fileURL 文件拖拽（内层 track row 的 onDrop 先命中，此处只处理空白区域）
        // SwiftUI NSDragging 遵循视图深度，内层 track row 始终优先
        .onDrop(of: [.fileURL], delegate: FileOnlyDropDelegate(onFilesDrop: onFilesDrop))
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }
    
    // MARK: - Loading Overlay
    
    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.accent)
            
            VStack(spacing: 4) {
                Text("playlist_loading_title")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primaryText)
                
                if loadingTracksCount > 0 {
                    Text(loadingFilesProcessingText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondaryText)
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.containerBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.accent.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 20)
        )
    }

    private var loadingFilesProcessingText: String {
        let format = String(localized: "playlist_loading_files_processing_format")
        return String(format: format, locale: Locale.current, Int64(loadingTracksCount))
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
            isFailed: playerViewModel.isTrackFailed(track.id)
        )
        .equatable()
        .opacity(draggingIndex == index ? 0.5 : 1.0)
        .onTapGesture(count: 2) {
            onTrackSelected(index)
        }
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
                // 移动目标是第 1 位，或被拖曳曲目本身是当前滚动锚点时，必须清除锚点。
                // 否则 SwiftUI .scrollPosition 会将列表自动滚回该曲目，新首位将不可见
                if destination == 0
                    || (from < tracks.count && tracks[from].id == playerViewModel.lastScrollTrackId)
                {
                    playerViewModel.lastScrollTrackId = nil
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

// MARK: - File Only Drop Delegate

/// 仅处理来自 Finder 的 fileURL 拖拽，不响应 track/album 排序（.text 类型）
/// 用于 PlaylistTabView 的全局兜底层，防止被底层不可见专辑 cells 抢占
struct FileOnlyDropDelegate: DropDelegate {
    let onFilesDrop: ([URL]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        // 只接受 fileURL，不接受 .text（track/album 排序），避免意外拦截
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {}
    func dropExited(info: DropInfo) {}

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }

        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
                do {
                    let item = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
                    switch item {
                    case let url as URL: urls.append(url)
                    case let data as Data:
                        if let s = String(data: data, encoding: .utf8) {
                            urls.append(URL(string: s) ?? URL(fileURLWithPath: s))
                        }
                    case let s as String: urls.append(URL(string: s) ?? URL(fileURLWithPath: s))
                    default: break
                    }
                } catch { continue }
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
        isLoadingTracks: false,
        loadingTracksCount: 0,
        onTrackSelected: { _ in },
        onTrackRemoved: { _ in },
        onTrackMoved: { _, _ in },
        onFilesDrop: { _ in }
    )
    .padding()
    .background(Color.black)
}
