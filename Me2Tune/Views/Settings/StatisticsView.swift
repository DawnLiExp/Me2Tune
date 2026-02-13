//
//  StatisticsView.swift
//  Me2Tune
//
//  统计主视图 - 集成图表与概览卡片
//

import SwiftUI

struct StatisticsView: View {
    @State private var viewModel = StatisticsViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Period Picker
            
            Picker("", selection: $viewModel.selectedPeriod) {
                ForEach(StatPeriod.allCases, id: \.self) { period in
                    Text(period.displayName)
                        .tag(period)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            // MARK: - Chart Section
            
            ZStack {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.stats.isEmpty || viewModel.stats.allSatisfy({ $0.playCount == 0 }) {
                    EmptyStateView()
                        .transition(.opacity)
                } else {
                    StatisticsChartView(data: viewModel.stats, period: viewModel.selectedPeriod)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity
                        ))
                }
            }
            .frame(height: 240)
            .animation(.easeOut(duration: 0.3), value: viewModel.isLoading)
            .animation(.easeOut(duration: 0.3), value: viewModel.stats.isEmpty)
            .animation(.easeOut(duration: 0.3), value: viewModel.selectedPeriod)
            
            Divider()
            
            // MARK: - Overview Cards
            
            HStack(spacing: 16) {
                StatCard(
                    title: String(localized: "stat_tracks", defaultValue: "Total Tracks"),
                    value: viewModel.totalTracks,
                    icon: "music.note"
                )
                StatCard(
                    title: String(localized: "stat_albums", defaultValue: "Total Albums"),
                    value: viewModel.totalAlbums,
                    icon: "square.stack"
                )
                StatCard(
                    title: String(localized: "stat_artists", defaultValue: "Unique Artists"),
                    value: viewModel.uniqueArtists,
                    icon: "person.2"
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .task {
            await viewModel.loadStatistics()
        }
        .onChange(of: viewModel.selectedPeriod) { _, _ in
            Task {
                await viewModel.loadStatistics()
            }
        }
    }
}

#Preview {
    StatisticsView()
        .frame(width: 550, height: 400)
}
