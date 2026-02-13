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
        return DailyStatItem(id: "\(i)", date: date, playCount: i % 7 == 0 ? 0 : Int.random(in: 1...50))
    }.reversed()

    return StatisticsChartView(data: data, period: .daily)
        .frame(height: 240)
}
