import Foundation

public struct CameraExposure: Sendable, Equatable {
    public enum Change: Sendable {
        case automatic
        case shutter(seconds: Double)
        case iso(Float)
        case aperture(Float)
    }

    public let isManual: Bool
    public let shutterSeconds: Double
    public let iso: Float
    public let aperture: Float
    public let shutterStops: [Double]
    public let isoStops: [Float]
    public let apertureStops: [Float]

    public var supportsManual: Bool { !shutterStops.isEmpty && !isoStops.isEmpty }

    func accepts(_ change: Change) -> Bool {
        switch change {
        case .automatic: isManual || supportsManual
        case .shutter(let seconds): shutterStops.contains(seconds)
        case .iso(let iso): isoStops.contains(iso)
        case .aperture(let aperture): apertureStops.contains(aperture)
        }
    }

    /// Half-stop selections at fast speeds and practical long exposures, clipped to the active format.
    static func shutterStops(in range: ClosedRange<Double>) -> [Double] {
        let denominators: [Double] = [
            16_000, 12_000, 8_000, 6_000, 4_000, 3_000, 2_000, 1_500, 1_000, 750,
            500, 350, 250, 180, 125, 90, 60, 45, 30, 20, 15, 10, 8, 6, 4, 3, 2,
        ]
        return stops(denominators.map { 1 / $0 } + [1, 1.5, 2, 3, 4, 6, 8, 12, 15, 20, 30], in: range)
    }

    /// Conventional half-stop ISO choices, clipped to the active format.
    static func isoStops(in range: ClosedRange<Float>) -> [Float] {
        stops(
            [
                25, 35, 50, 70, 100, 140, 200, 280, 400, 560, 800, 1_100, 1_600, 2_200, 3_200, 4_500, 6_400,
                9_000, 12_800, 18_000, 25_600, 36_000, 51_200,
            ], in: range)
    }

    private static func stops<Value: FloatingPoint>(_ candidates: [Value], in range: ClosedRange<Value>) -> [Value] {
        let supported = candidates.filter(range.contains)
        return supported.isEmpty ? [range.lowerBound] : supported
    }
}
