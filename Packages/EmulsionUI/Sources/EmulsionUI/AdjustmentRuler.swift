import EmulsionCore
import EmulsionKit
import SwiftUI

/// A fixed indicator over a moving scale; dragging left increases the adjustment.
struct AdjustmentRuler: View {
    let control: AdjustmentControl
    @Binding var adjustments: Adjustments
    /// Distinguishes rulers for UI tests when several are on screen.
    var identifier = "adjustment-ruler"
    /// One of several rulers in the inspector: a smaller readout over the minimum touch height.
    var isCompact = false
    @State private var drag = RulerDrag()

    private let tickSpacing: CGFloat = 10
    private var scaleHeight: CGFloat { isCompact ? FilmLabLayout.minimumControlHeight : 56 }
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            scale
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(control.title)
        .accessibilityValue(control.formatted(value))
        .accessibilityIdentifier(identifier)
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
        Text(control.formatted(value)).font((isCompact ? Font.body : .title2).weight(.medium)).monospacedDigit()
    }

    private var scale: some View {
        ZStack {
            ticks
            Capsule().fill(.primary).frame(width: 2, height: 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mask {
            LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing)
        }
        .contentShape(.rect)
        .horizontalScrub { translation in
            let next = drag.update(
                value: value, translation: translation.width, verticalTranslation: translation.height,
                pointsPerUnit: tickSpacing / control.increment, range: control.range,
                neutral: neutral, detent: control.increment * 0.3
            )
            set(next)
        } onEnded: {
            drag.end()
        }
        .onTapGesture(count: 2) { set(neutral) }
        .frame(height: scaleHeight)
        .clipped()
    }

    /// One drawing for the whole scale, so a drag redraws the visible ticks instead of
    /// re-laying out a view per tick. `.style` resolves the hierarchical colors in the
    /// environment, keeping light/dark and Increase Contrast.
    private var ticks: some View {
        let position = (value - control.range.lowerBound) / control.increment
        let tickCount = self.tickCount
        let tickSpacing = self.tickSpacing
        return Canvas { context, size in
            let halfSpan = Double(size.width) / 2 / tickSpacing
            let first = max(0, Int((position - halfSpan).rounded(.down)))
            let last = min(tickCount, Int((position + halfSpan).rounded(.up)))
            guard first <= last else { return }
            for tick in first...last {
                let isMajor = tick.isMultiple(of: 5)
                let height: CGFloat = isMajor ? 24 : 12
                let x = size.width / 2 + (Double(tick) - position) * tickSpacing
                let mark = CGRect(x: x - 0.5, y: (size.height - height) / 2, width: 1, height: height)
                context.fill(Path(mark), with: isMajor ? .style(.primary) : .style(.secondary))
            }
        }
    }

    private func set(_ value: Double) {
        adjustments[keyPath: control.keyPath] = min(control.range.upperBound, max(control.range.lowerBound, value))
    }
}
