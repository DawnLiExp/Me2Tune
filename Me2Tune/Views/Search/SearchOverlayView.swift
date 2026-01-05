//
//  SearchOverlayView.swift
//  Me2Tune
//
//  搜索覆盖界面 - 当前 Tab 上下文搜索 + 结果分类（性能优化）
//

import SwiftUI

struct SearchOverlayView: View {
    @Binding var isPresented: Bool
    @FocusState private var isSearchFocused: Bool
    
    let searchContext: SearchContext
    let onResultSelected: (SearchResult) -> Void
    
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var hoveredResultId: UUID?
    @State private var debounceTask: Task<Void, Never>?
    
    enum SearchContext {
        case playlist([AudioTrack])
        case albumsList([Album])
        case albumDetail(Album)
        
        var title: LocalizedStringKey {
            switch self {
            case .playlist:
                return "search_in_playlist"
            case .albumsList:
                return "search_in_collections"
            case .albumDetail(let album):
                return LocalizedStringKey("search_in_album \(album.name)")
            }
        }
    }
    
    struct SearchResult: Identifiable {
        let id: UUID
        let title: String
        let subtitle: String
        let icon: String
        let action: Action
        let category: Category
        
        enum Action {
            case playTrack(Int)
            case openAlbum(Album)
            case playAlbumTrack(Album, Int)
        }
        
        enum Category: String, Comparable {
            case album
            case song
            
            var displayName: LocalizedStringKey {
                switch self {
                case .album: return "category_albums"
                case .song: return "category_songs"
                }
            }
            
            static func < (lhs: Category, rhs: Category) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }
    }
    
    var body: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.8)
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
                
                if !debouncedSearchText.isEmpty {
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
                    resultsSection
                }
            }
            .frame(width: 420, height: debouncedSearchText.isEmpty ? 140 : 480)
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
        .onChange(of: searchText) { _, newValue in
            debounceSearch(newValue)
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
            
            TextField("search_placeholder", text: $searchText)
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
                let groupedResults = Dictionary(grouping: results, by: { $0.category })
                
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(groupedResults.keys.sorted(), id: \.self) { category in
                            if let categoryResults = groupedResults[category], !categoryResults.isEmpty {
                                categorySection(
                                    category: category,
                                    results: categoryResults
                                )
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    private func categorySection(category: SearchResult.Category, results: [SearchResult]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(category.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accent)
                
                Text("(\(results.count))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.tertiaryText)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            
            LazyVStack(spacing: 2) {
                ForEach(results) { result in
                    SearchResultRowView(
                        title: result.title,
                        subtitle: result.subtitle,
                        icon: result.icon,
                        isHovered: hoveredResultId == result.id,
                        onTap: {
                            onResultSelected(result)
                            closeSearch()
                        },
                        onHoverChange: { isHovered in
                            hoveredResultId = isHovered ? result.id : nil
                        }
                    )
                    .padding(.horizontal, 8)
                }
            }
        }
    }
    
    private var emptyResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.emptyStateIcon)
            
            Text("no_results")
                .font(.system(size: 14))
                .foregroundColor(.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Debounce
    
    private func debounceSearch(_ text: String) {
        debounceTask?.cancel()
        
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                debouncedSearchText = text
            }
        }
    }
    
    // MARK: - Search Logic
    
    private func performSearch() -> [SearchResult] {
        let query = debouncedSearchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
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
                track.artist ?? String(localized: "unknown_artist"),
                track.albumTitle
            ]
            .compactMap { $0 }
            .joined(separator: " • ")
            
            return SearchResult(
                id: track.id,
                title: track.title,
                subtitle: subtitle.isEmpty ? String(localized: "unknown") : subtitle,
                icon: "music.note",
                action: actionBuilder(index),
                category: .song
            )
        }
    }
    
    private func searchInAlbums(_ albums: [Album], query: String) -> [SearchResult] {
        var results: [SearchResult] = []
        
        for album in albums {
            // 搜索专辑名
            let matchesAlbumName = album.name.lowercased().contains(query)
            
            if matchesAlbumName {
                results.append(SearchResult(
                    id: album.id,
                    title: album.name,
                    subtitle: "\(album.tracks.count) \(String(localized: "tracks"))",
                    icon: "opticaldisc",
                    action: .openAlbum(album),
                    category: .album
                ))
            }
            
            // 搜索艺术家和歌曲
            let matchingTracks = album.tracks.filter { track in
                let matchesTitle = track.title.lowercased().contains(query)
                let matchesArtist = track.artist?.lowercased().contains(query) ?? false
                return matchesTitle || matchesArtist
            }
            
            if !matchingTracks.isEmpty, !matchesAlbumName {
                // 只有在专辑名不匹配时，才作为歌曲结果添加
                if let firstMatch = matchingTracks.first {
                    let subtitle = String(localized: "in_song \(firstMatch.title)")
                    results.append(SearchResult(
                        id: UUID(), // 使用新 ID，因为同一专辑可能匹配多首歌
                        title: album.name,
                        subtitle: subtitle,
                        icon: "opticaldisc",
                        action: .openAlbum(album),
                        category: .song
                    ))
                }
            }
        }
        
        return results
    }
    
    // MARK: - Actions
    
    private func closeSearch() {
        debounceTask?.cancel()
        
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
