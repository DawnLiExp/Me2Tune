//
//  SearchOverlayView.swift
//  Me2Tune
//
//  搜索覆盖界面 - 当前 Tab 上下文搜索
//

import SwiftUI

struct SearchOverlayView: View {
    @Binding var isPresented: Bool
    @FocusState private var isSearchFocused: Bool
    
    let searchContext: SearchContext
    let onResultSelected: (SearchResult) -> Void
    
    @State private var searchText = ""
    @State private var hoveredIndex: Int?
    
    enum SearchContext {
        case playlist([AudioTrack])
        case albumsList([Album])
        case albumDetail(Album)
        
        var title: String {
            switch self {
            case .playlist:
                return "Search in Playlist"
            case .albumsList:
                return "Search in Collections"
            case .albumDetail(let album):
                return "Search in \(album.name)"
            }
        }
    }
    
    struct SearchResult: Identifiable {
        let id: UUID
        let title: String
        let subtitle: String
        let icon: String
        let action: Action
        
        enum Action {
            case playTrack(Int)
            case openAlbum(Album)
            case playAlbumTrack(Album, Int)
        }
    }
    
    var body: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture {
                    closeSearch()
                }
            
            // 搜索卡片
            VStack(spacing: 0) {
                headerSection
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                searchInputSection
                
                if !searchText.isEmpty {
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
                    resultsSection
                }
            }
            .frame(width: 420, height: searchText.isEmpty ? 140 : 480)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.containerBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.accent.opacity(0.3), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.6), radius: 30)
            )
        }
        .onAppear {
            isSearchFocused = true
        }
        .onKeyPress(.escape) {
            closeSearch()
            return .handled
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack {
            Text(searchContext.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondaryText)
            
            Spacer()
            
            Button(action: closeSearch) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Search Input
    
    private var searchInputSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(.secondaryText)
            
            TextField("Type to search...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundColor(.primaryText)
                .focused($isSearchFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    // MARK: - Results
    
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            let results = performSearch()
            
            if results.isEmpty {
                emptyResultsView
            } else {
                HStack {
                    Text("Results (\(results.count))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.tertiaryText)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            SearchResultRowView(
                                title: result.title,
                                subtitle: result.subtitle,
                                icon: result.icon,
                                isHovered: hoveredIndex == index,
                                onTap: {
                                    onResultSelected(result)
                                    closeSearch()
                                },
                                onHoverChange: { isHovered in
                                    hoveredIndex = isHovered ? index : nil
                                }
                            )
                            .padding(.horizontal, 8)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    private var emptyResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.emptyStateIcon)
            
            Text("No results found")
                .font(.system(size: 14))
                .foregroundColor(.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Search Logic
    
    private func performSearch() -> [SearchResult] {
        let query = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        
        switch searchContext {
        case .playlist(let tracks):
            return searchInTracks(tracks, query: query) { index in
                .playTrack(index)
            }
            
        case .albumsList(let albums):
            return searchInAlbums(albums, query: query)
            
        case .albumDetail(let album):
            return searchInTracks(album.tracks, query: query) { index in
                .playAlbumTrack(album, index)
            }
        }
    }
    
    private func searchInTracks(
        _ tracks: [AudioTrack],
        query: String,
        actionBuilder: (Int) -> SearchResult.Action
    ) -> [SearchResult] {
        tracks.enumerated().compactMap { index, track in
            let matchesTitle = track.title.lowercased().contains(query)
            let matchesArtist = track.artist?.lowercased().contains(query) ?? false
            let matchesAlbum = track.albumTitle?.lowercased().contains(query) ?? false
            
            guard matchesTitle || matchesArtist || matchesAlbum else { return nil }
            
            let subtitle = [
                track.artist ?? "Unknown Artist",
                track.albumTitle
            ]
            .compactMap(\.self)
            .joined(separator: " • ")
            
            return SearchResult(
                id: track.id,
                title: track.title,
                subtitle: subtitle.isEmpty ? "Unknown" : subtitle,
                icon: "music.note",
                action: actionBuilder(index)
            )
        }
    }
    
    private func searchInAlbums(_ albums: [Album], query: String) -> [SearchResult] {
        var results: [SearchResult] = []
        
        for album in albums {
            // 搜索专辑名
            let matchesAlbumName = album.name.lowercased().contains(query)
            
            // 搜索艺术家和歌曲
            let matchesContent = album.tracks.contains { track in
                let matchesTitle = track.title.lowercased().contains(query)
                let matchesArtist = track.artist?.lowercased().contains(query) ?? false
                return matchesTitle || matchesArtist
            }
            
            if matchesAlbumName || matchesContent {
                // 构建副标题
                let subtitle = if matchesAlbumName {
                    "\(album.tracks.count) tracks"
                } else {
                    // 显示匹配的歌曲/艺术家信息
                    if let firstMatch = album.tracks.first(where: { track in
                        track.title.lowercased().contains(query) ||
                            (track.artist?.lowercased().contains(query) ?? false)
                    }) {
                        "in \(firstMatch.title)"
                    } else {
                        "\(album.tracks.count) tracks"
                    }
                }
                
                results.append(SearchResult(
                    id: album.id,
                    title: album.name,
                    subtitle: subtitle,
                    icon: "opticaldisc",
                    action: .openAlbum(album)
                ))
            }
        }
        
        return results
    }
    
    // MARK: - Actions
    
    private func closeSearch() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPresented = false
        }
    }
}

#Preview {
    SearchOverlayView(
        isPresented: .constant(true),
        searchContext: .playlist([]),
        onResultSelected: { _ in }
    )
}
