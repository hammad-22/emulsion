import simd

extension SyntheticDNG {
    /// A typical daylight sensor neutral: red and blue sites see less of a D65 white than green.
    static let daylightNeutral = SIMD3<Double>(0.48, 1.0, 0.62)

    /// Linear sRGB (D65) → XYZ, IEC 61966-2-1 primaries.
    public static let xyzFromLinearSRGB = simd_double3x3(rows: [
        SIMD3(0.4124564, 0.3575761, 0.1804375),
        SIMD3(0.2126729, 0.7151522, 0.0721750),
        SIMD3(0.0193339, 0.1191920, 0.9503041),
    ])

    /// Linear Rec. 2020 (D65) → XYZ, ITU-R BT.2020 primaries.
    private static let xyzFromLinearRec2020 = simd_double3x3(rows: [
        SIMD3(0.6369580, 0.1446169, 0.1688810),
        SIMD3(0.2627002, 0.6779981, 0.0593017),
        SIMD3(0.0000000, 0.0280727, 1.0609851),
    ])

    /// Artistic stand-in for overlapping sensor dye responses; rows sum to 1 so white stays white.
    private static let sensorCrosstalk = simd_double3x3(rows: [
        SIMD3(0.90, 0.08, 0.02),
        SIMD3(0.05, 0.90, 0.05),
        SIMD3(0.02, 0.10, 0.88),
    ])

    /// `diag(daylightNeutral) · XYZ→linear sRGB`: a scene colour `c` in linear sRGB under D65
    /// reads `daylightNeutral * c` exactly in camera space. Its gamut is sRGB, so it cannot
    /// record colours outside sRGB (they clip to 0 at the sensor).
    public static let sRGBCameraFromXYZ = simd_double3x3(diagonal: daylightNeutral) * xyzFromLinearSRGB.inverse

    /// A wider, non-trivial synthetic camera: `diag(daylightNeutral) · crosstalk · XYZ→linear Rec. 2020`.
    /// D65 white still reads `daylightNeutral`; Display P3 colours outside sRGB stay positive,
    /// so they survive the sensor.
    static let wideGamutCameraFromXYZ = simd_double3x3(diagonal: daylightNeutral) * sensorCrosstalk * xyzFromLinearRec2020.inverse

    /// Camera value of a scene colour given in linear sRGB (D65 light).
    public static func camera(linearSRGB: SIMD3<Double>, cameraFromXYZ: simd_double3x3) -> SIMD3<Double> {
        cameraFromXYZ * (xyzFromLinearSRGB * linearSRGB)
    }

    /// Camera value of a light of chromaticity `xy` and luminance (Y) 1.
    public static func camera(chromaticity xy: SIMD2<Double>, cameraFromXYZ: simd_double3x3) -> SIMD3<Double> {
        cameraFromXYZ * SIMD3(xy.x / xy.y, 1, (1 - xy.x - xy.y) / xy.y)
    }

    /// Camera neutral (green = 1) of a light of chromaticity `xy`, as DNG AsShotNeutral stores it.
    public static func neutral(chromaticity xy: SIMD2<Double>, cameraFromXYZ: simd_double3x3) -> SIMD3<Double> {
        let value = camera(chromaticity: xy, cameraFromXYZ: cameraFromXYZ)
        return value / value.y
    }

    /// CIE 1931 xy of a Planckian radiator, 1667–25000 K: the Kim et al. 2002 cubic-spline
    /// approximation of the Planckian locus.
    public static func planckianChromaticity(kelvin t: Double) -> SIMD2<Double> {
        let t3 = t * t * t
        let x =
            t <= 4000
            ? -0.2661239e9 / t3 - 0.2343589e6 / (t * t) + 0.8776956e3 / t + 0.179910
            : -3.0258469e9 / t3 + 2.1070379e6 / (t * t) + 0.2226347e3 / t + 0.240390
        let y: Double
        if t <= 2222 {
            y = -1.1063814 * x * x * x - 1.34811020 * x * x + 2.18555832 * x - 0.20219683
        } else if t <= 4000 {
            y = -0.9549476 * x * x * x - 1.37418593 * x * x + 2.09137015 * x - 0.16748867
        } else {
            y = 3.0817580 * x * x * x - 5.87338670 * x * x + 3.75112997 * x - 0.37001483
        }
        return SIMD2(x, y)
    }

    /// D65 white point as the colour standards round it (sRGB, Rec. 709/2020, Display P3), the
    /// value `InputColorSpace.d65` uses.
    public static let d65Chromaticity = SIMD2<Double>(0.3127, 0.3290)

    /// Colour temperature of CIE standard illuminant A, a tungsten lamp: 2856 K (CIE 15:2004).
    public static let illuminantAKelvin = 2856.0
}
