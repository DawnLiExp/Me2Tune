//
//  AlbumCardView.swift
//  Me2Tune
//
//  专辑卡片组件 - 使用 NSView 级别的 hover 检测
//

import SwiftUI

struct AlbumCardView: View {
    let album: Album
    let artwork: NSImage?
    let isDragging: Bool
    let onTap: () -> Void
    let onRename: () -> Void
    let onRemove: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        ZStack {
            // 内容层
            contentView
            
            // Hover 检测层（透明覆盖）
            HoverDetectingView(isHovered: $isHovered)
                .allowsHitTesting(false)
        }
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            Button("rename") {
                onRename()
            }
            
            Divider()
            
            Button("remove", role: .destructive) {
                onRemove()
            }
        }
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        VStack(spacing: 8) {
            artworkView
            
            VStack(spacing: 2) {
                Text(album.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                
                Text("\(album.tracks.count) tracks")
                    .font(.system(size: 11))
                    .foregroundColor(.secondaryText)
            }
        }
        .opacity(isDragging ? 0.4 : 1.0)
        .scaleEffect(isHovered && !isDragging ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
    
    // MARK: - Artwork View
    
    private var artworkView: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        Image(systemName: "opticaldisc")
                            .font(.system(size: 40))
                            .foregroundColor(.emptyStateIcon)
                    )
            }
        }
        .frame(width: 135, height: 135)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    Color.accent.opacity(isHovered && !isDragging ? 0.4 : 0),
                    lineWidth: 2
                )
        )
        .shadow(
            color: isHovered && !isDragging ? Color.accent.opacity(0.2) : .clear,
            radius: 8
        )
        .drawingGroup()
    }
}
