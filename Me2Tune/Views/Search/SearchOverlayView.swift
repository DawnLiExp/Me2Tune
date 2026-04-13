//
//  SearchOverlayView.swift
//  Me2Tune
//
//  搜索覆盖界面 - 全局搜索 + 结果限制
//

import SwiftUI

struct SearchOverlayView: View {
    @Binding var isPresented: Bool
    @FocusState private var isSearchFocused: Bool
    
    let searchData: SearchData
    let onResultSelected: (SearchResult) -> Void
    
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var debounceTask: Task<Void, Never>?
    @State private var animationProgress: CGFloat = 0
    
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
        let relevance: Int
        
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
    
    private let maxTotalSongResults = 20
    private let maxAlbumResults = 10
    private let maxPerSourceSongs = 20
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.6 * animationProgress)
                .ignoresSafeArea()
                .onTapGesture {
                    closeSearch()
                }
            
            searchCard
                .opacity(animationProgress)
                .offset(y: (1 - animationProgress) * 20)
                .padding(.top, 130)
        }
        .onAppear {
            isSearchFocused = true
            withAnimation(.easeOut(duration: 0.25)) {
                animationProgress = 1
            }
        }
        .onKeyPress(.escape) {
            closeSearch()
            return .handled
        }
        .onChange(of: searchText) { _, newValue in
            debounceSearch(newValue)
        }
        .onChange(of: debouncedSearchText) { _, _ in
            searchResults = performSearch()
        }
    }
    
    // MARK: - Search Card
    
    private var searchCard: some View {
        VStack(spacing: 0) {
            searchInputSection
            
            if !debouncedSearchText.isEmpty {
                Divider()
                    .background(Color.searchOverlayStroke.opacity(0.3))
                    .padding(.horizontal, 16)
                
                resultsSection
                    .frame(height: 420)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.searchOverlayBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.searchOverlayStroke, lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.6), radius: 30)
        )
    }
    
    // MARK: - Search Input
    
    private var searchInputSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(.searchIconColor)
                .frame(width: 24, height: 24)
            
            TextField("search_placeholder", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundColor(.searchInputText)
                .focused($isSearchFocused)
            
            Button(action: closeSearch) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.searchIconColor)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }
    
    // MARK: - Results
    
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if searchResults.isEmpty {
                emptyResultsView
            } else {
                let groupedResults = Dictionary(grouping: searchResults, by: { $0.category })
                
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
                    .foregroundColor(.accent.opacity(0.9))
                    
                Text(resultCountBadgeText(for: results.count))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.searchSecondaryText)
                    
                Spacer()
            }
            .padding(.horizontal, 16)
                
            LazyVStack(spacing: 2) {
                ForEach(results) { result in
                    SearchResultRowView(
                        title: result.title,
                        subtitle: result.subtitle,
                        icon: result.icon,
                        onTap: {
                            onResultSelected(result)
                            closeSearch()
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
                .foregroundColor(.searchSecondaryText)
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
        
        let playlistResults = searchPlaylistTracks(query: query)
        let albumResults = searchAlbums(query: query)
        let albumTrackResults = searchAlbumTracks(query: query)
        
        var songResults = playlistResults + albumTrackResults
        songResults.sort { $0.relevance > $1.relevance }
        
        if songResults.count > maxTotalSongResults {
            songResults = Array(songResults.prefix(maxTotalSongResults))
        }
        
        allResults.append(contentsOf: albumResults)
        allResults.append(contentsOf: songResults)
        
        return allResults
    }
    
    // MARK: - Search Helpers
    
    private func searchPlaylistTracks(query: String) -> [SearchResult] {
        var results: [SearchResult] = []
        
        for (index, track) in searchData.playlist.enumerated() {
            guard results.count < maxPerSourceSongs else { break }
            
            let titleMatch = track.title.lowercased().contains(query)
            let artistMatch = track.artist?.lowercased().contains(query) ?? false
            let albumMatch = track.albumTitle?.lowercased().contains(query) ?? false
            
            guard titleMatch || artistMatch || albumMatch else { continue }
            
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
            let artistMatch = album.tracks.contains { track in
                track.artist?.lowercased().contains(query) ?? false
            }
                
            guard nameMatch || artistMatch else { continue }
                
            let artist = album.tracks.first?.artist
            let trackCountText = trackCountText(for: album.tracks.count)
            let subtitle: String
            if let artist, !artist.isEmpty {
                let format = String(localized: "search_album_subtitle_with_artist_format")
                subtitle = String(format: format, locale: Locale.current, artist, trackCountText)
            } else {
                subtitle = trackCountText
            }
                
            let relevance = nameMatch ? 3 : 2
                
            results.append(SearchResult(
                id: album.id,
                title: album.name,
                subtitle: subtitle,
                icon: "opticaldisc",
                action: .openAlbum(album),
                category: .album,
                relevance: relevance
            ))
        }
            
        return results
    }
    
    private func searchAlbumTracks(query: String) -> [SearchResult] {
        var results: [SearchResult] = []
        
        albumLoop: for album in searchData.albums {
            for (index, track) in album.tracks.enumerated() {
                guard results.count < maxPerSourceSongs else { break albumLoop }
                
                let titleMatch = track.title.lowercased().contains(query)
                let artistMatch = track.artist?.lowercased().contains(query) ?? false
                
                guard titleMatch || artistMatch else { continue }
                
                let relevance = titleMatch ? 3 : 2
                
                let subtitle = [
                    track.artist ?? String(localized: "unknown_artist"),
                    inAlbumText(for: album.name)
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

    private func resultCountBadgeText(for count: Int) -> String {
        let format = String(localized: "search_result_count_badge_format")
        return String(format: format, locale: Locale.current, Int64(count))
    }

    private func trackCountText(for count: Int) -> String {
        let format = String(localized: "track_count_format")
        return String(format: format, locale: Locale.current, Int64(count))
    }

    private func inAlbumText(for albumName: String) -> String {
        let format = String(localized: "search_in_album_format")
        return String(format: format, locale: Locale.current, albumName)
    }
    
    // MARK: - Actions
    
    private func closeSearch() {
        debounceTask?.cancel()
        
        withAnimation(.easeOut(duration: 0.2)) {
            animationProgress = 0
        }
        
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            await MainActor.run {
                isPresented = false
            }
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
