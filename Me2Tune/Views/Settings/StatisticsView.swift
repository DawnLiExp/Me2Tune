//
//  StatisticsView.swift
//  Me2Tune
//
//  统计主视图 - 集成图表与概览卡片
//

import SwiftUI

struct StatisticsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var viewModel: StatisticsViewModel
    @Namespace private var periodPickerAnimation

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Period Picker

            periodPicker
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 18)

            // MARK: - Chart Section

            ZStack {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.stats.isEmpty || viewModel.stats.allSatisfy({ $0.playCount == 0 }) {
                    EmptyStateView()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    StatisticsChartView(data: viewModel.stats, period: viewModel.selectedPeriod)
                        .id(viewModel.selectedPeriod)
                        .transition(.opacity)
                }
            }
            .frame(height: 240)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isLoading)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.stats.isEmpty)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.selectedPeriod)

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
            .padding(.top, 16)
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        HStack(spacing: 6) {
            ForEach(StatPeriod.allCases, id: \.self) { period in
                periodButton(for: period)
            }
        }
        .padding(4)
        .frame(width: 255, height: 35)
        .background(periodPickerBackground)
    }

    private func periodButton(for period: StatPeriod) -> some View {
        let isSelected = viewModel.selectedPeriod == period

        return Button {
            withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                viewModel.selectedPeriod = period
            }
        } label: {
            Text(period.displayName)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(periodTextColor(isSelected: isSelected))
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(periodSelectionFill)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(periodSelectionBorder, lineWidth: 1)
                            }
                            .shadow(
                                color: .black.opacity(colorScheme == .dark ? 0.14 : 0.05),
                                radius: colorScheme == .dark ? 8 : 4,
                                x: 0,
                                y: 1
                            )
                            .matchedGeometryEffect(id: "statistics-period-selection", in: periodPickerAnimation)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var periodPickerBackground: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(periodPickerSurfaceFill)
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(periodPickerSurfaceBorder, lineWidth: 1)
            }
    }

    private var periodSelectionFill: Color {
        Color(nsColor: .controlBackgroundColor)
            .opacity(colorScheme == .dark ? 0.72 : 0.68)
    }

    private var periodSelectionBorder: Color {
        Color.accentColor.opacity(colorScheme == .dark ? 0.26 : 0.16)
    }

    private var periodPickerSurfaceFill: Color {
        Color(nsColor: .underPageBackgroundColor)
            .opacity(colorScheme == .dark ? 0.84 : 0.72)
    }

    private var periodPickerSurfaceBorder: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05)
    }

    private func periodTextColor(isSelected: Bool) -> Color {
        if isSelected {
            return Color.accentColor
        }

        return Color(nsColor: .secondaryLabelColor)
    }
}

#Preview {
    StatisticsView(viewModel: StatisticsViewModel())
        .frame(width: 500, height: 525)
}
