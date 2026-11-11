import EmulsionCore
import EmulsionKit
import SwiftUI

/// A fixed indicator over a moving scale; dragging left increases the adjustment.
struct AdjustmentRuler: View {
    let control: AdjustmentControl
    @Binding var adjustments: Adjustments
    @State private var drag = RulerDrag()

    private let tickSpacing: CGFloat = 10
    private let scaleHeight: CGFloat = 56
    private var value: Double { adjustments[keyPath: control.keyPath] }
    private var neutral: Double { Adjustments()[keyPath: control.keyPath] }
    private var tickCount: Int { Int(((control.range.upperBound - control.range.lowerBound) / control.increment).rounded()) }
    private var side: Int { value < neutral ? -1 : value > neutral ? 1 : 0 }

    var body: some View {
        VStack(spacing: FilmLabLayout.compact) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    title.fixedSize()
                    Spacer(minLength: FilmLabLayout.compact)
                    readout.fixedSize()
                }
                VStack(alignment: .leading, spacing: FilmLabLayout.compact) {
                    title
                    readout
                }
            }
            scale
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(control.title)
        .accessibilityValue(control.formatted(value))
        .accessibilityIdentifier("adjustment-ruler")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(value + control.increment)
            case .decrement: set(value - control.increment)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Reset") { set(neutral) }
        .sensoryFeedback(.impact(weight: .light), trigger: side)
        .onChange(of: control.id) { drag.end() }
    }

    private var title: some View { Text(control.title).font(.subheadline.weight(.medium)) }

    private var readout: some View {
        Text(control.formatted(value)).font(.title2.weight(.medium)).monospacedDigit()
    }

    private var scale: some View {
        GeometryReader { geometry in
            let position = (value - control.range.lowerBound) / control.increment
            ZStack {
                ForEach(0...tickCount, id: \.self) { tick in
                    Rectangle()
                        .fill(tick.isMultiple(of: 5) ? .primary : .secondary)
                        .frame(width: 1, height: tick.isMultiple(of: 5) ? 24 : 12)
                        .position(x: geometry.size.width / 2 + (Double(tick) - position) * tickSpacing, y: scaleHeight / 2)
                }
                Capsule().fill(.primary).frame(width: 2, height: 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mask {
                LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing)
            }
            .contentShape(.rect)
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { gesture in
                        let next = drag.update(
                            value: value, translation: gesture.translation.width,
                            verticalTranslation: gesture.translation.height,
                            pointsPerUnit: tickSpacing / control.increment, range: control.range,
                            neutral: neutral, detent: control.increment * 0.3
                        )
                        set(next)
                    }
                    .onEnded { _ in drag.end() }
            )
            .onTapGesture(count: 2) { set(neutral) }
        }
        .frame(height: scaleHeight)
        .clipped()
    }

    private func set(_ value: Double) {
        adjustments[keyPath: control.keyPath] = min(control.range.upperBound, max(control.range.lowerBound, value))
    }
}
