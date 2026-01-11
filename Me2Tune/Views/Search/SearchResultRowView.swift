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
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.searchIconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.searchPrimaryText)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.searchSecondaryText)
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
            isHovered = hovering
        }
    }
}

#Preview {
    VStack(spacing: 4) {
        SearchResultRowView(
            title: "Test Song",
            subtitle: "Artist • Album",
            icon: "music.note",
            onTap: {}
        )
        
        SearchResultRowView(
            title: "Another Song",
            subtitle: "Artist • Album",
            icon: "music.note",
            onTap: {}
        )
    }
    .padding()
    .background(Color.black)
}
