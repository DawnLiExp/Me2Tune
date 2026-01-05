//
//  SearchOverlayView.swift
//  Me2Tune
//
//  搜索覆盖界面 - 全局搜索 + 结果限制（性能优化）
//

import SwiftUI

struct SearchOverlayView: View {
    @Binding var isPresented: Bool
    @FocusState private var isSearchFocused: Bool
    
    let searchData: SearchData
    let onResultSelected: (SearchResult) -> Void
    
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var hoveredResultId: UUID?
    @State private var debounceTask: Task<Void, Never>?
    
    struct SearchData {
        let playlist: [AudioTrack]
        let albums: [Album]
    }
    
    struct SearchResult: Identifiable {
        let id: UUID
        let title: String
        let subtitle: String
        let icon: String
        let action: Action
        let category: Category
        let relevance: Int // 相关性评分，用于排序
        
        enum Action {
            case playPlaylistTrack(Int)
            case playAlbumTrack(Album, Int)
            case openAlbum(Album)
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
    
    private let maxSongResults = 50
    private let maxAlbumResults = 20
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture {
                    closeSearch()
                }
            
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
            Text("global_search")
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
        
        var allResults: [SearchResult] = []
        
        // 1. 搜索播放列表歌曲
        let playlistResults = searchPlaylistTracks(query: query)
        
        // 2. 搜索专辑
        let albumResults = searchAlbums(query: query)
        
        // 3. 搜索专辑内歌曲
        let albumTrackResults = searchAlbumTracks(query: query)
        
        allResults.append(contentsOf: playlistResults)
        allResults.append(contentsOf: albumResults)
        allResults.append(contentsOf: albumTrackResults)
        
        // 按相关性排序
        return allResults.sorted { $0.relevance > $1.relevance }
    }
    
    // MARK: - Search Helpers
    
    private func searchPlaylistTracks(query: String) -> [SearchResult] {
        var results: [SearchResult] = []
        
        for (index, track) in searchData.playlist.enumerated() {
            guard results.count < maxSongResults else { break }
            
            let titleMatch = track.title.lowercased().contains(query)
            let artistMatch = track.artist?.lowercased().contains(query) ?? false
            let albumMatch = track.albumTitle?.lowercased().contains(query) ?? false
            
            guard titleMatch || artistMatch || albumMatch else { continue }
            
            // 相关性评分：标题匹配 > 艺术家匹配 > 专辑匹配
            let relevance = titleMatch ? 3 : (artistMatch ? 2 : 1)
            
            let subtitle = [
                track.artist ?? String(localized: "unknown_artist"),
                String(localized: "from_playlist")
            ]
            .joined(separator: " • ")
            
            results.append(SearchResult(
                id: UUID(),
                title: track.title,
                subtitle: subtitle,
                icon: "music.note",
                action: .playPlaylistTrack(index),
                category: .song,
                relevance: relevance
            ))
        }
        
        return results
    }
    
    private func searchAlbums(query: String) -> [SearchResult] {
        var results: [SearchResult] = []
        
        for album in searchData.albums {
            guard results.count < maxAlbumResults else { break }
            
            let nameMatch = album.name.lowercased().contains(query)
            guard nameMatch else { continue }
            
            results.append(SearchResult(
                id: album.id,
                title: album.name,
                subtitle: "\(album.tracks.count) \(String(localized: "tracks"))",
                icon: "opticaldisc",
                action: .openAlbum(album),
                category: .album,
                relevance: 3
            ))
        }
        
        return results
    }
    
    private func searchAlbumTracks(query: String) -> [SearchResult] {
        var results: [SearchResult] = []
        
        for album in searchData.albums {
            for (index, track) in album.tracks.enumerated() {
                guard results.count < maxSongResults else { break }
                
                let titleMatch = track.title.lowercased().contains(query)
                let artistMatch = track.artist?.lowercased().contains(query) ?? false
                
                guard titleMatch || artistMatch else { continue }
                
                let relevance = titleMatch ? 3 : 2
                
                let subtitle = [
                    track.artist ?? String(localized: "unknown_artist"),
                    String(localized: "in_album \(album.name)")
                ]
                .joined(separator: " • ")
                
                results.append(SearchResult(
                    id: UUID(),
                    title: track.title,
                    subtitle: subtitle,
                    icon: "music.note",
                    action: .playAlbumTrack(album, index),
                    category: .song,
                    relevance: relevance
                ))
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
        searchData: SearchOverlayView.SearchData(playlist: [], albums: []),
        onResultSelected: { _ in }
    )
}
