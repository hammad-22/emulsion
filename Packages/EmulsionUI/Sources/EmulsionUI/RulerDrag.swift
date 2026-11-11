struct RulerDrag {
    private var previousTranslation = 0.0
    private var rawValue: Double?
    private var isHorizontal: Bool?

    mutating func update(
        value: Double, translation: Double, verticalTranslation: Double = 0, pointsPerUnit: Double,
        range: ClosedRange<Double>, neutral: Double, detent: Double
    ) -> Double {
        if isHorizontal == nil { isHorizontal = abs(translation) > abs(verticalTranslation) }
        guard isHorizontal == true else { return value }
        let delta = translation - previousTranslation
        previousTranslation = translation
        let next = (rawValue ?? value) - delta / pointsPerUnit
        let bounded = min(range.upperBound, max(range.lowerBound, next))
        rawValue = bounded
        return abs(bounded - neutral) < detent ? neutral : bounded
    }

    mutating func end() {
        previousTranslation = 0
        rawValue = nil
        isHorizontal = nil
    }
}
