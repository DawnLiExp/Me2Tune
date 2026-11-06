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
    @State private var resultBatch: SearchEngine.Batch?
    @State private var isClosing = false
    @State private var closeTask: Task<Void, Never>?
    @State private var debounceTask: Task<Void, Never>?
    @State private var animationProgress: CGFloat = 0

    typealias SearchData = SearchEngine.SearchData
    typealias SearchResult = SearchEngine.SearchResult

    private var request: SearchEngine.Request? {
        guard !isClosing, isPresented else { return nil }
        return SearchEngine.Request(query: debouncedSearchText, version: searchData.version)
    }

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
            isClosing = false
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
        .task(id: request) {
            guard let request else { return }
            await SearchEngine.run(
                request: request,
                data: searchData,
                canPublish: { !isClosing && isPresented },
                publish: { resultBatch = $0 }
            )
        }
        .onDisappear {
            isClosing = true
            debounceTask?.cancel()
            closeTask?.cancel()
            resultBatch = nil
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
            if let searchResults = resultBatch?.results(for: request) {
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
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            guard resultBatch?.results(for: request)?.contains(where: { $0.id == result.id }) == true else {
                                return
                            }
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

    private func resultCountBadgeText(for count: Int) -> String {
        let format = String(localized: "search_result_count_badge_format")
        return String(format: format, locale: Locale.current, Int64(count))
    }

    // MARK: - Actions

    private func closeSearch() {
        guard !isClosing else { return }
        isClosing = true
        resultBatch = nil
        debounceTask?.cancel()

        withAnimation(.easeOut(duration: 0.2)) {
            animationProgress = 0
        }

        closeTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
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
