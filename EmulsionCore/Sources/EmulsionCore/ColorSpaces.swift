import Foundation
import simd

/// Camera and display encodings Emulsion can read, each decoded to scene light (0.18 =
/// mid-gray) in the linear sRGB/D65 working space. Curves and primaries follow each
/// manufacturer's published white paper (cross-checked against the colour-science library).
public enum InputColorSpace: String, CaseIterable, Identifiable, Codable, Sendable {
    case appleLog, sLog3SGamut3Cine, arriLogC3, arriLogC4, vLog, davinciIntermediate, acescct
    case hlgRec2020, rec709, displayP3, linearP3
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appleLog: return "Apple Log"
        case .sLog3SGamut3Cine: return "Sony S-Log3 / S-Gamut3.Cine"
        case .arriLogC3: return "ARRI LogC3 / AWG3 (EI 800)"
        case .arriLogC4: return "ARRI LogC4 / AWG4"
        case .vLog: return "Panasonic V-Log / V-Gamut"
        case .davinciIntermediate: return "DaVinci Intermediate / DWG"
        case .acescct: return "ACEScct / AP1"
        case .hlgRec2020: return "Rec.2100 HLG"
        case .rec709: return "Rec.709 (display)"
        case .displayP3: return "Display P3 (display)"
        case .linearP3: return "Linear P3 (scene)"
        }
    }

    /// Display-referred sources are inverted through the film system's neutral response;
    /// everything else is scene-referred after its curve.
    public var isDisplayReferred: Bool { self == .rec709 || self == .displayP3 }

    /// Curve identifier understood by the `inputTransform` kernel.
    var curve: Int {
        switch self {
        case .appleLog: return 1
        case .sLog3SGamut3Cine: return 2
        case .arriLogC3: return 3
        case .arriLogC4: return 4
        case .vLog: return 5
        case .davinciIntermediate: return 6
        case .acescct: return 7
        case .hlgRec2020: return 8
        case .rec709: return 9  // BT.1886 display (gamma 2.4)
        case .displayP3: return 10  // sRGB piecewise transfer
        case .linearP3: return 0
        }
    }

    typealias Primaries = (r: SIMD2<Double>, g: SIMD2<Double>, b: SIMD2<Double>, white: SIMD2<Double>)
    static let d65 = SIMD2(0.3127, 0.3290)

    var primaries: Primaries {
        switch self {
        case .appleLog, .hlgRec2020: return ([0.708, 0.292], [0.170, 0.797], [0.131, 0.046], Self.d65)
        case .sLog3SGamut3Cine: return ([0.766, 0.275], [0.225, 0.800], [0.089, -0.087], Self.d65)
        case .arriLogC3: return ([0.6840, 0.3130], [0.2210, 0.8480], [0.0861, -0.1020], Self.d65)
        case .arriLogC4: return ([0.7347, 0.2653], [0.1424, 0.8576], [0.0991, -0.0308], Self.d65)
        case .vLog: return ([0.730, 0.280], [0.165, 0.840], [0.100, -0.030], Self.d65)
        case .davinciIntermediate: return ([0.8000, 0.3130], [0.1682, 0.9877], [0.0790, -0.1155], Self.d65)
        case .acescct: return ([0.713, 0.293], [0.165, 0.830], [0.128, 0.044], [0.32168, 0.33767])
        case .rec709: return ([0.64, 0.33], [0.30, 0.60], [0.15, 0.06], Self.d65)
        case .displayP3, .linearP3: return ([0.680, 0.320], [0.265, 0.690], [0.150, 0.060], Self.d65)
        }
    }

    /// Source RGB → linear sRGB (D65), with Bradford adaptation for non-D65 white points.
    var toWorking: simd_double3x3 {
        let p = primaries
        let toXYZ = ColorMath.rgbToXYZ(p.r, p.g, p.b, white: p.white)
        let adapt = ColorMath.bradford(from: p.white, to: Self.d65)
        let w = InputColorSpace.rec709.primaries  // the working space: linear sRGB / Rec.709
        let sRGB = ColorMath.rgbToXYZ(w.r, w.g, w.b, white: w.white)
        return sRGB.inverse * adapt * toXYZ
    }
}

enum ColorMath {
    static func xyz(_ xy: SIMD2<Double>) -> SIMD3<Double> { SIMD3(xy.x / xy.y, 1, (1 - xy.x - xy.y) / xy.y) }

    static func rgbToXYZ(_ r: SIMD2<Double>, _ g: SIMD2<Double>, _ b: SIMD2<Double>, white: SIMD2<Double>) -> simd_double3x3 {
        let m = simd_double3x3(columns: (xyz(r), xyz(g), xyz(b)))
        let s = m.inverse * xyz(white)
        return simd_double3x3(columns: (m.columns.0 * s.x, m.columns.1 * s.y, m.columns.2 * s.z))
    }

    /// Bradford chromatic adaptation between two white points (identity when equal).
    static func bradford(from source: SIMD2<Double>, to target: SIMD2<Double>) -> simd_double3x3 {
        let m = simd_double3x3(rows: [SIMD3(0.8951, 0.2664, -0.1614), SIMD3(-0.7502, 1.7135, 0.0367), SIMD3(0.0389, -0.0685, 1.0296)])
        let s = m * xyz(source)
        let d = m * xyz(target)
        let scale = simd_double3x3(diagonal: d / s)
        return m.inverse * scale * m
    }

    /// Reference decode in Swift (mirrors the kernel) for tests and LUT generation.
    static func decode(_ v: Double, curve: Int) -> Double {
        switch curve {
        case 1:  // Apple Log
            let r0 = -0.05641088
            let rt = 0.01
            let sigma = 47.28711236
            let beta = 0.00964052
            let gamma = 0.08550479
            let delta = 0.69336945
            let pt = sigma * (rt - r0) * (rt - r0)
            if v >= pt { return pow(2, (v - delta) / gamma) - beta }
            return v >= 0 ? (v / sigma).squareRoot() + r0 : r0
        case 2:  // S-Log3 (full-range normalized code value, reflection)
            if v >= 171.2102946929 / 1023 { return pow(10, (1023 * v - 420) / 261.5) * 0.19 - 0.01 }
            return (1023 * v - 95) * 0.01125 / (171.2102946929 - 95)
        case 3:  // ARRI LogC3, EI 800
            if v > 0.149658 { return (pow(10, (v - 0.385537) / 0.247190) - 0.052272) / 5.555556 }
            return (v - 0.092809) / 5.367655
        case 4:  // ARRI LogC4
            let (a, b, c) = (LogC4.a, LogC4.b, LogC4.c)
            let s = (7 * log(2) * pow(2, 7 - 14 * c / b)) / (a * b)
            let t = (pow(2, 14 * (-c / b) + 6) - 64) / a
            return v >= 0 ? (pow(2, 14 * ((v - c) / b) + 6) - 64) / a : v * s + t
        case 5:  // Panasonic V-Log
            return v < 0.181 ? (v - 0.125) / 5.6 : pow(10, (v - 0.598206) / 0.241514) - 0.00873
        case 6:  // DaVinci Intermediate
            return v > 0.02740668 ? pow(2, v / 0.07329248 - 7) - 0.0075 : v / 10.44426855
        case 7:  // ACEScct
            return v <= 0.155251141552511 ? (v - 0.0729055341958355) / 10.5402377416545 : min(pow(2, v * 17.52 - 9.72), 65504)
        case 8:  // BT.2100 HLG inverse OETF, scaled so 38% signal = 18% gray (ITU-R BT.2408)
            let a = 0.17883277
            let b = 0.28466892
            let c = 0.55991073
            let e = v <= 0.5 ? v * v / 3 : (exp((v - c) / a) + b) / 12
            return e * hlgSceneScale
        case 9: return pow(max(v, 0), 2.4)
        case 10: return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        default:
            return v
        }
    }
    static let hlgSceneScale = 0.18 / (0.38 * 0.38 / 3)
    /// ARRI LogC4 specification constants.
    enum LogC4 { static let a = (262144.0 - 16) / 117.45, b = (1023.0 - 95) / 1023, c = 95.0 / 1023 }
}
