//
//  TickedSlider.swift
//  Me2Tune
//
//  Custom slider with ticks
//

import SwiftUI

struct TickedSlider<T: RawRepresentable & CaseIterable & Equatable & Identifiable>: View where T.RawValue == String {
    @Binding var selection: T.RawValue
    let leftLabel: Text
    let rightLabel: Text
    
    private let allCases = Array(T.allCases)
    private let tickCount: Int
    
    init(selection: Binding<T.RawValue>, leftLabel: LocalizedStringKey, rightLabel: LocalizedStringKey) {
        self._selection = selection
        self.leftLabel = Text(leftLabel)
        self.rightLabel = Text(rightLabel)
        self.tickCount = T.allCases.count
    }

    init(selection: Binding<T.RawValue>, leftVerbatimLabel: String, rightVerbatimLabel: String) {
        self._selection = selection
        self.leftLabel = Text(verbatim: leftVerbatimLabel)
        self.rightLabel = Text(verbatim: rightVerbatimLabel)
        self.tickCount = T.allCases.count
    }
    
    private var currentIndex: Int {
        allCases.firstIndex(where: { $0.rawValue == selection }) ?? 0
    }
    
    var body: some View {
        HStack(spacing: 24) {
            leftLabel
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize()
                .frame(width: 35, alignment: .trailing)
            
            GeometryReader { geometry in
                let width = geometry.size.width
                let step = tickCount > 1 ? width / CGFloat(tickCount - 1) : 0
                
                ZStack(alignment: .leading) {
                    // Rail
                    Rectangle()
                        .fill(Color(NSColor.separatorColor).opacity(0.5))
                        .frame(height: 1)
                    
                    // Ticks
                    HStack(spacing: 0) {
                        ForEach(0 ..< tickCount, id: \.self) { index in
                            Rectangle()
                                .fill(Color(NSColor.separatorColor))
                                .frame(width: 1, height: 6)
                            
                            if index < tickCount - 1 {
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    
                    // Knob
                    Circle()
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.15), radius: 1.5, y: 0.5)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                        )
                        .offset(x: CGFloat(currentIndex) * step - 7)
                        .animation(.spring(duration: 0.2), value: selection)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard step > 0 else { return }
                            let newIndex = Int(round(max(0, min(width, value.location.x)) / step))
                            if newIndex >= 0, newIndex < tickCount {
                                selection = allCases[newIndex].rawValue
                            }
                        }
                )

                .frame(maxHeight: .infinity)
            }
            .frame(width: 140, height: 20)
            
            rightLabel
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize()
                .frame(width: 45, alignment: .leading)
        }
    }
}

#Preview {
    @Previewable @State var selection = "medium"
    TickedSlider<GlowBreathingRate>(
        selection: $selection,
        leftLabel: "Slow",
        rightLabel: "Fast"
    )
    .padding()
}
