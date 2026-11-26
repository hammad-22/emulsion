import EmulsionCore
import EmulsionKit
import SwiftUI

/// A fixed indicator over a moving scale; dragging left increases the adjustment.
struct AdjustmentRuler: View {
    let control: AdjustmentControl
    @Binding var adjustments: Adjustments
    /// One of several rulers in the inspector: a smaller readout over the minimum touch height.
    var isCompact = false
    var axis: Axis = .horizontal
    @State private var drag = RulerDrag()
    @GestureState private var isScrubbingVertically = false

    private let tickSpacing: CGFloat = 10
    /// Every fifth tick is major: taller and a level brighter, like a printed scale.
    private let majorTickHeight: CGFloat = 24
    private let minorTickHeight: CGFloat = 12
    private let tickWidth: CGFloat = 1
    /// Taller and wider than any tick, so the fixed indicator reads first.
    private let indicatorSize = CGSize(width: 2, height: 36)
    private var scaleHeight: CGFloat { isCompact ? FilmLabLayout.minimumControlHeight : 56 }
    private var value: Double { adjustments[keyPath: control.keyPath] }
    private var neutral: Double { Adjustments()[keyPath: control.keyPath] }
    private var tickCount: Int { Int(((control.range.upperBound - control.range.lowerBound) / control.increment).rounded()) }
    private var side: Int { value < neutral ? -1 : value > neutral ? 1 : 0 }

    var body: some View {
        VStack(spacing: FilmLabLayout.compact) {
            if axis == .vertical {
                title.multilineTextAlignment(.center)
                readout
            } else {
                horizontalReadout
            }
            scale
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(control.accessibilityLabel(for: adjustments.process))
        .accessibilityValue(control.accessibilityValue(value))
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

    private var horizontalReadout: some View {
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
    }

    private var title: some View { Text(control.title(for: adjustments.process)).font(.subheadline.weight(.medium)) }

    private var readout: some View {
        Text(control.formatted(value)).font((isCompact ? Font.body : .title2).weight(.medium)).monospacedDigit()
    }

    @ViewBuilder private var scale: some View {
        if axis == .vertical {
            scaleSurface
                .gesture(
                    DragGesture()
                        .updating($isScrubbingVertically) { _, active, _ in active = true }
                        .onChanged { scrub($0.translation.height, across: $0.translation.width) }
                )
                .onChange(of: isScrubbingVertically) { _, active in
                    if !active { drag.end() }
                }
                .frame(minHeight: FilmLabLayout.minimumControlHeight)
        } else {
            scaleSurface
                .horizontalScrub {
                    scrub($0.width, across: $0.height)
                } onEnded: {
                    drag.end()
                }
                .frame(height: scaleHeight)
        }
    }

    private var scaleSurface: some View {
        ticks.frame(maxWidth: .infinity, maxHeight: .infinity)
            .mask {
                LinearGradient(
                    colors: [.clear, .black, .black, .clear],
                    startPoint: axis == .vertical ? .top : .leading,
                    endPoint: axis == .vertical ? .bottom : .trailing)
            }
            .contentShape(.rect)
            .onTapGesture(count: 2) { set(neutral) }
            .clipped()
    }

    private func scrub(_ translation: CGFloat, across perpendicular: CGFloat) {
        set(
            drag.update(
                value: value, translation: translation, verticalTranslation: perpendicular,
                pointsPerUnit: tickSpacing / control.increment, range: control.range,
                neutral: neutral, detent: control.increment * 0.3))
    }

    /// One drawing for the whole scale, so a drag redraws the visible ticks instead of
    /// re-laying out a view per tick. `.style` resolves the hierarchical colors in the
    /// environment, keeping light/dark and Increase Contrast. The fixed indicator is drawn
    /// last and a level brighter than any tick, so it reads first.
    private var ticks: some View {
        let position = (value - control.range.lowerBound) / control.increment
        let tickCount = self.tickCount
        let tickSpacing = self.tickSpacing
        let (major, minor, tickWidth, indicatorSize) = (majorTickHeight, minorTickHeight, self.tickWidth, self.indicatorSize)
        return Canvas { context, size in
            let isVertical = axis == .vertical
            let length = isVertical ? size.height : size.width
            let breadth = isVertical ? size.width : size.height
            let halfSpan = Double(length) / 2 / tickSpacing
            let first = max(0, Int((position - halfSpan).rounded(.down)))
            let last = min(tickCount, Int((position + halfSpan).rounded(.up)))
            guard first <= last else { return }
            for tick in first...last {
                let isMajor = tick.isMultiple(of: 5)
                let height = isMajor ? major : minor
                let x = length / 2 + (Double(tick) - position) * tickSpacing
                let mark = CGRect(x: x - tickWidth / 2, y: (breadth - height) / 2, width: tickWidth, height: height)
                context.fill(Path(oriented(mark)), with: isMajor ? .style(.secondary) : .style(.tertiary))
            }
            let indicator = CGRect(
                x: (length - indicatorSize.width) / 2, y: (breadth - indicatorSize.height) / 2,
                width: indicatorSize.width, height: indicatorSize.height)
            context.fill(Path(roundedRect: oriented(indicator), cornerRadius: indicatorSize.width / 2), with: .style(.primary))
        }
    }

    private func oriented(_ rect: CGRect) -> CGRect {
        axis == .vertical ? CGRect(x: rect.minY, y: rect.minX, width: rect.height, height: rect.width) : rect
    }

    private func set(_ value: Double) {
        adjustments[keyPath: control.keyPath] = min(control.range.upperBound, max(control.range.lowerBound, value))
    }
}
