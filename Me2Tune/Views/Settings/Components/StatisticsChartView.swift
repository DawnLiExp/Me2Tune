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
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .onAppear {
            triggerAnimation()
        }
        .onChange(of: data) { _, _ in
            triggerAnimation()
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
        if item.playCount == 0 {
            return AnyShapeStyle(Color.secondary.opacity(0.15))
        } else {
            return AnyShapeStyle(LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.8),
                    Color.accentColor.opacity(0.4)
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
