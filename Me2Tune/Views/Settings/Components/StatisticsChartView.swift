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

    var body: some View {
        Chart(data) { item in
            BarMark(
                x: .value("Date", item.date, unit: .day),
                // Ensure visibility even if count is 0 by using a minimum height of 1
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
            .cornerRadius(4)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        // Force-provide a range to satisfy SwiftUI ScaleDomain requirements
        .chartYScale(domain: 0...max(10, data.map(\.playCount).max() ?? 10))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

#Preview {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let data: [DailyStatItem] = (0 ..< 30).map { i in
        let date = calendar.date(byAdding: .day, value: -i, to: today)!
        return DailyStatItem(id: "\(i)", date: date, playCount: i % 7 == 0 ? 0 : Int.random(in: 1...20))
    }.reversed()

    return StatisticsChartView(data: data)
        .frame(height: 240)
}
