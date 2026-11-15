import Foundation

/// Constants of the digicam process; status and source of each: docs/DIGICAM.md, "Digicam constants".
enum DigicamLook {
    // Default Grain (noise) and Halation (processing) amounts. Owner direction.
    static let defaultNoise = 0.75
    static let defaultProcessing = 0.7
    /// Top of the Noise control. Owner direction (14 Nov 2026): film grain reaches 2, digicam noise stays capped at 1.
    static let maximumNoise = 1.0

    // 4:3 sensor of 2592 × 1944 px. Measured: period file headers.
    static let aspectRatio = 4.0 / 3.0
    static let sensorLongEdge = 2592.0

    // Lens: corner falloff (stops), softness and purple fringe (sensor px). Owner direction.
    static let vignetteStops = 1.0
    static let lensSoftnessSigma = 0.8
    static let cornerSoftnessSigma = 3.0
    static let fringeOnset = 0.85
    static let fringeRadius = 3.5
    static let fringeColor = SIMD3(0.55, 0.2, 1.0)
    static let fringeStrength = 1.0

    // Smallest blur worth applying (output px); below it nothing visible changes. Artistic.
    static let minimumBlurSigma = 0.5

    // Partial auto white balance from a daylight reference (K, mireds, gains); status per member in docs.
    static let whiteBalanceCorrection = 0.6
    static let whiteBalanceReference = 5500.0
    static let biasMireds = 12.0
    static let biasMagenta = 0.008

    // Warmth (mireds) and Tint (green gain) per unit of the control. Artistic.
    static let warmthMireds = 60.0
    static let tintGreen = 0.12

    // Hard per-channel clip (owner direction) and black floor (artistic), stops from mid-gray.
    static let clipStops = 2.0
    static let clip = 0.18 * pow(2, clipStops)
    static let blackStops = 4.5
    static let blackOffset = pow(2, -(clipStops + blackStops))

    // Noise σ at amount 1, fractions of the clip. Owner direction; blue gain measured.
    static let shotNoise = 0.02
    static let readNoise = 0.006
    static let chromaNoiseShare = 2.0
    static let chromaNoiseCell = 6.0
    static let blueNoiseGain = 1.25

    // Saturation (measured) and Color control range (artistic).
    static let saturation = 1.15
    static let colorBoost = 0.5, colorCut = 0.8

    // JPEG tone curve: ISO 12232 mid-gray code, lifted black floor, S-curve share.
    static let middleGrayCode = 118.0 / 255.0
    static let blackFloorCode = 22.0 / 255.0
    static let contrast = 0.15
    static let toneCurvePivot = (middleGrayCode - blackFloorCode) / (1 - blackFloorCode)
    static let gammaPower: Double = {
        let middleGray = (0.18 / clip - blackOffset) / (1 - blackOffset)
        return log(toneCurvePivot) / log(ColorMath.encodeSRGB(middleGray))
    }()

    // In-camera sharpening (sensor px) and export JPEG quality. Owner direction.
    static let sharpenRadius = 1.8
    static let sharpenAmount = 1.85
    static let jpegQualityClean = 0.9
    static let jpegQualityLoss = 0.4
}
