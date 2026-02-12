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

    var body: some View {
        Chart(data) { item in
            BarMark(
                x: .value("Date", item.date, unit: xAxisUnit),
                y: .value("Plays", max(item.playCount, 1))
            )
            .foregroundStyle(
                item.playCount == 0
                    ? AnyShapeStyle(Color.secondary.opacity(0.15))
                    : AnyShapeStyle(LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.8),
                            Color.accentColor.opacity(0.4)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            )
            .cornerRadius(period == .monthly ? 6 : 4)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: xAxisUnit, count: xAxisStride)) { _ in
                if period == .daily {
                    AxisValueLabel(format: .dateTime.month().day())
                } else if period == .weekly {
                    AxisValueLabel(format: .dateTime.month().day())
                } else {
                    AxisValueLabel(format: .dateTime.month())
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartYScale(domain: 0...max(10, data.map(\.playCount).max() ?? 10))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

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
}

#Preview {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let data: [DailyStatItem] = (0 ..< 30).map { i in
        let date = calendar.date(byAdding: .day, value: -i, to: today)!
        return DailyStatItem(id: "\(i)", date: date, playCount: i % 7 == 0 ? 0 : Int.random(in: 1...20))
    }.reversed()

    return StatisticsChartView(data: data, period: .daily)
        .frame(height: 240)
}
