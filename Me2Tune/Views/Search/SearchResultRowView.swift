//
//  SearchResultRowView.swift
//  Me2Tune
//
//  搜索结果行组件
//

import SwiftUI

struct SearchResultRowView: View {
    let title: String
    let subtitle: String
    let icon: String
    let isHovered: Bool
    let onTap: () -> Void
    let onHoverChange: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.accent)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.hoverBackground : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onHover { hovering in
            onHoverChange(hovering)
        }
    }
}

#Preview {
    VStack(spacing: 4) {
        SearchResultRowView(
            title: "Test Song",
            subtitle: "Artist • Album",
            icon: "music.note",
            isHovered: false,
            onTap: {},
            onHoverChange: { _ in }
        )
        
        SearchResultRowView(
            title: "Another Song",
            subtitle: "Artist • Album",
            icon: "music.note",
            isHovered: true,
            onTap: {},
            onHoverChange: { _ in }
        )
    }
    .padding()
    .background(Color.black)
}
