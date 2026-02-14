//
//  StatisticsChartView.swift
//  Me2Tune
//
//  统计图表组件 - 使用 SwiftUI Charts 展示播放趋势
//

import Charts
import SwiftUI

struct StatisticsChartView: View {
    let data: [DailyStatItem]
    let period: StatPeriod

    // MARK: - Animation State

    @State private var isAnimating = false
    @State private var selectedDate: Date?

    var body: some View {
        Chart(data) { item in
            BarMark(
                x: .value("Date", item.date, unit: xAxisUnit),
                y: .value("Plays", isAnimating ? max(item.playCount, 1) : 0)
            )
            .foregroundStyle(barStyle(for: item))
            .cornerRadius(period == .monthly ? 6 : 4)
        }
        .chartXAxis {
            xAxisContent
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartYScale(domain: 0...max(10, data.map(\.playCount).max() ?? 10))
        .chartXSelection(value: $selectedDate)
        .overlay(alignment: .top) {
            hoverTooltip
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .onAppear {
            triggerAnimation()
        }
        .onChange(of: data) { _, _ in
            triggerAnimation()
        }
    }

    // MARK: - Hover Tooltip

    @ViewBuilder
    private var hoverTooltip: some View {
        if let selectedDate,
           let item = findMatchingItem(for: selectedDate)
        {
            VStack(alignment: .leading, spacing: 4) {
                Text(tooltipDateText(for: item))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Text(String(localized: "stat_plays_count", defaultValue: "Plays"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(tooltipCountText(for: item.playCount))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            }
            .padding(.top, 8)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selectedDate)
        }
    }

    // MARK: - Item Matching

    /// Finds the data item matching the selected date based on the current period
    private func findMatchingItem(for selectedDate: Date) -> DailyStatItem? {
        let calendar = Calendar.current

        switch period {
        case .daily:
            // Match same day
            return data.first(where: { calendar.isDate($0.date, inSameDayAs: selectedDate) })

        case .weekly:
            // Match same week
            return data.first(where: {
                calendar.isDate($0.date, equalTo: selectedDate, toGranularity: .weekOfYear)
            })

        case .monthly:
            // Match same month
            return data.first(where: {
                calendar.isDate($0.date, equalTo: selectedDate, toGranularity: .month)
            })
        }
    }

    // MARK: - Tooltip Content Helpers

    private func tooltipDateText(for item: DailyStatItem) -> String {
        let calendar = Calendar.current

        switch period {
        case .daily:
            // Format: "2月13日 星期五" / "Feb 13, Friday"
            let formatter = DateFormatter()
            formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMdEEEE", options: 0, locale: Locale.current)
            return formatter.string(from: item.date)

        case .weekly:
            // Format: "2月9日 - 2月15日" / "Feb 9 - Feb 15"
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: item.date)?.start else {
                return item.date.formatted(date: .abbreviated, time: .omitted)
            }
            guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
                return item.date.formatted(date: .abbreviated, time: .omitted)
            }

            let startFormat = weekStart.formatted(.dateTime.month().day())
            let endFormat = weekEnd.formatted(.dateTime.month().day())
            return "\(startFormat) - \(endFormat)"

        case .monthly:
            // Format: "2025年2月" / "February 2025"
            return item.date.formatted(.dateTime.year().month(.wide))
        }
    }

    private func tooltipCountText(for count: Int) -> String {
        // For Chinese, add unit "首"; for English, just the number
        if Locale.current.language.languageCode?.identifier == "zh" {
            return "\(count) \(String(localized: "stat_count_unit", defaultValue: "首"))"
        } else {
            return "\(count)"
        }
    }

    // MARK: - Helpers

    private func triggerAnimation() {
        isAnimating = false
        withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.5)) {
            isAnimating = true
        }
    }

    private func barStyle(for item: DailyStatItem) -> AnyShapeStyle {
        let calendar = Calendar.current
        let isSelected: Bool = if let selectedDate {
            switch period {
            case .daily:
                calendar.isDate(item.date, inSameDayAs: selectedDate)
            case .weekly:
                calendar.isDate(item.date, equalTo: selectedDate, toGranularity: .weekOfYear)
            case .monthly:
                calendar.isDate(item.date, equalTo: selectedDate, toGranularity: .month)
            }
        } else {
            false
        }

        if item.playCount == 0 {
            return AnyShapeStyle(Color.secondary.opacity(isSelected ? 0.25 : 0.15))
        } else {
            let baseOpacity = isSelected ? 1.0 : 0.8
            let bottomOpacity = isSelected ? 0.6 : 0.4

            return AnyShapeStyle(LinearGradient(
                colors: [
                    Color.accentColor.opacity(baseOpacity),
                    Color.accentColor.opacity(bottomOpacity)
                ],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
    }

    @AxisContentBuilder
    private var xAxisContent: some AxisContent {
        switch period {
        case .daily:
            AxisMarks(values: xAxisKeyDates) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        if Calendar.current.isDateInToday(date) {
                            Text(String(localized: "stat_today", defaultValue: "Today"))
                        } else {
                            Text(date, format: .dateTime.month().day())
                        }
                    }
                    .offset(x: labelXOffset(for: date), y: edgeLabelYOffset)
                }
            }
        case .weekly:
            AxisMarks(values: xAxisKeyDates) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        if date == data.first?.date {
                            Text(weekCountText)
                        } else {
                            Text(String(localized: "stat_this_week", defaultValue: "This Week"))
                        }
                    }
                    .offset(x: labelXOffset(for: date), y: edgeLabelYOffset)
                }
            }
        case .monthly:
            AxisMarks(values: .stride(by: .month, count: 1)) { _ in
                AxisValueLabel(format: .dateTime.month())
            }
        }
    }

    private var xAxisUnit: Calendar.Component {
        switch period {
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
        }
    }

    private var xAxisStride: Int {
        switch period {
        case .daily: return 5
        case .weekly: return 2
        case .monthly: return 1
        }
    }

    private var xAxisKeyDates: [Date] {
        guard !data.isEmpty else { return [] }

        switch period {
        case .daily:
            guard let first = data.first?.date,
                  let last = data.last?.date else { return [] }
            let midIndex = data.count / 2
            let mid = data[midIndex].date
            return [first, mid, last]

        case .weekly:
            guard let first = data.first?.date,
                  let last = data.last?.date else { return [] }
            return [first, last]

        case .monthly:
            return []
        }
    }

    private var weekCountText: String {
        let count = data.count
        let format = String(localized: "stat_weeks_ago_format", defaultValue: "%d Weeks Ago")
        return String(format: format, count)
    }

    // MARK: - Label Position Adjustments

    private var edgeLabelYOffset: CGFloat {
        4.0
    }

    /// Calculates horizontal offset for axis labels.
    private func labelXOffset(for date: Date) -> CGFloat {
        let baseOffset: CGFloat = -15.0 // Approx. half the average label width to center under tick
        let edgeNudge: CGFloat = 12.0 // Additional shift to pull edge labels toward the chart body

        if date == data.first?.date {
            return baseOffset + edgeNudge
        } else if date == data.last?.date {
            return baseOffset - edgeNudge
        } else {
            return baseOffset
        }
    }
}

#Preview {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let data: [DailyStatItem] = (0 ..< 30).map { i in
        let date = calendar.date(byAdding: .day, value: -i, to: today)!
        return DailyStatItem(id: "\(i)", date: date, playCount: i % 7 == 0 ? 0 : Int.random(in: 1...50))
    }.reversed()

    return StatisticsChartView(data: data, period: .daily)
        .frame(height: 240)
}
