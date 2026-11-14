import Foundation
import simd

/// Camera and display encodings Emulsion reads, decoded to linear sRGB (docs/CONSTANTS.md).
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

    /// What the decoded light means.
    public var contract: InputContract {
        switch self {
        case .rec709, .displayP3: return .displayReferred
        case .hlgRec2020: return .nominalScene
        case .appleLog, .sLog3SGamut3Cine, .arriLogC3, .arriLogC4, .vLog, .davinciIntermediate, .acescct, .linearP3:
            return .sceneReferred
        }
    }

    var curve: Int { transferCurve.rawValue }

    var transferCurve: TransferCurve {
        switch self {
        case .appleLog: .appleLog
        case .sLog3SGamut3Cine: .sLog3
        case .arriLogC3: .arriLogC3
        case .arriLogC4: .arriLogC4
        case .vLog: .vLog
        case .davinciIntermediate: .davinciIntermediate
        case .acescct: .acescct
        case .hlgRec2020: .hlg
        case .rec709: .bt1886
        case .displayP3: .sRGB
        case .linearP3: .linear
        }
    }

    /// Formula on 10-bit legal code values ÷ 1023 rather than E′. Sourced: each maker's white paper.
    var formulaTakesCodeValues: Bool {
        switch self {
        case .sLog3SGamut3Cine, .arriLogC3, .vLog: return true
        default: return false
        }
    }

    /// Y′CbCr matrix for an untagged frame: BT.2020 per BT.2100 and Apple Log, else BT.709 (assumed).
    var defaultYCbCrMatrix: YCbCrMatrix {
        switch self {
        case .appleLog, .hlgRec2020: return .bt2020
        default: return .bt709
        }
    }

    var formulaRange: SignalRange { formulaTakesCodeValues ? .legal : .full }

    var curveInputFromSignal: (scale: Double, offset: Double) {
        let legal = SignalRange.legal
        return formulaTakesCodeValues ? (legal.lumaSpan / SignalRange.largestCode, legal.lumaBlack / SignalRange.largestCode) : (1, 0)
    }

    /// Normalized signal E′ → linear in the source primaries.
    func decode(signal e: Double) -> Double {
        let (scale, offset) = curveInputFromSignal
        return ColorMath.decode(e * scale + offset, curve: curve)
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

    /// Source RGB → linear sRGB (D65), Bradford-adapted from other white points.
    var toWorking: simd_double3x3 {
        let p = primaries
        let toXYZ = ColorMath.rgbToXYZ(p.r, p.g, p.b, white: p.white)
        let adapt = ColorMath.bradford(from: p.white, to: Self.d65)
        return ColorMath.xyzToLinearSRGB * adapt * toXYZ
    }
}

/// Raw values are the `decodeCurve` identifiers in Emulsion.ci.metal; keep them in step.
enum TransferCurve: Int {
    case linear = 0
    case appleLog = 1
    case sLog3 = 2
    case arriLogC3 = 3
    case arriLogC4 = 4
    case vLog = 5
    case davinciIntermediate = 6
    case acescct = 7
    case hlg = 8
    case bt1886 = 9
    case sRGB = 10
}

enum ColorMath {
    static func xyz(_ xy: SIMD2<Double>) -> SIMD3<Double> { SIMD3(xy.x / xy.y, 1, (1 - xy.x - xy.y) / xy.y) }

    static func rgbToXYZ(_ r: SIMD2<Double>, _ g: SIMD2<Double>, _ b: SIMD2<Double>, white: SIMD2<Double>) -> simd_double3x3 {
        let m = simd_double3x3(columns: (xyz(r), xyz(g), xyz(b)))
        let s = m.inverse * xyz(white)
        return simd_double3x3(columns: (m.columns.0 * s.x, m.columns.1 * s.y, m.columns.2 * s.z))
    }

    static func bradford(from source: SIMD2<Double>, to target: SIMD2<Double>) -> simd_double3x3 {
        let m = simd_double3x3(rows: [SIMD3(0.8951, 0.2664, -0.1614), SIMD3(-0.7502, 1.7135, 0.0367), SIMD3(0.0389, -0.0685, 1.0296)])
        let s = m * xyz(source)
        let d = m * xyz(target)
        let scale = simd_double3x3(diagonal: d / s)
        return m.inverse * scale * m
    }

    /// Swift mirror of `decodeCurve`, from each curve's own domain (code value ÷ 1023 or E′).
    static func decode(_ v: Double, curve: Int) -> Double {
        decode(v, curve: TransferCurve(rawValue: curve) ?? .linear)
    }

    static func decode(_ v: Double, curve: TransferCurve) -> Double {
        switch curve {
        case .appleLog:
            let r0 = -0.05641088
            let rt = 0.01
            let sigma = 47.28711236
            let beta = 0.00964052
            let gamma = 0.08550479
            let delta = 0.69336945
            let pt = sigma * (rt - r0) * (rt - r0)
            if v >= pt { return pow(2, (v - delta) / gamma) - beta }
            return v >= 0 ? (v / sigma).squareRoot() + r0 : r0
        case .sLog3:
            if v >= 171.2102946929 / 1023 { return pow(10, (1023 * v - 420) / 261.5) * 0.19 - 0.01 }
            return (1023 * v - 95) * 0.01125 / (171.2102946929 - 95)
        case .arriLogC3:
            if v > 0.149658 { return (pow(10, (v - 0.385537) / 0.247190) - 0.052272) / 5.555556 }
            return (v - 0.092809) / 5.367655
        case .arriLogC4:
            let (a, b, c) = (LogC4.a, LogC4.b, LogC4.c)
            let s = (7 * log(2) * pow(2, 7 - 14 * c / b)) / (a * b)
            let t = (pow(2, 14 * (-c / b) + 6) - 64) / a
            return v >= 0 ? (pow(2, 14 * ((v - c) / b) + 6) - 64) / a : v * s + t
        case .vLog:
            return v < 0.181 ? (v - 0.125) / 5.6 : pow(10, (v - 0.598206) / 0.241514) - 0.00873
        case .davinciIntermediate:
            return v > 0.02740668 ? pow(2, v / 0.07329248 - 7) - 0.0075 : v / 10.44426855
        case .acescct:
            return v <= 0.155251141552511 ? (v - 0.0729055341958355) / 10.5402377416545 : min(pow(2, v * 17.52 - 9.72), 65504)
        case .hlg:
            // Scaled so 38 % signal = 18 % gray (BT.2408); odd extension below 0 keeps it monotonic.
            let (a, b, c) = (HLG.a, HLG.b, HLG.c)
            let e = v <= 0.5 ? v * abs(v) / 3 : (exp((v - c) / a) + b) / 12
            return e * HLG.sceneScale
        case .bt1886:
            // Odd extension below 0: the sub-black policy (ENGINE.md).
            return v < 0 ? -pow(-v, 2.4) : pow(v, 2.4)
        case .sRGB:
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        case .linear:
            return v
        }
    }

    /// IEC 61966-2-1 sRGB encode, linear → encoded.
    static func encodeSRGB(_ linear: Double) -> Double {
        linear <= 0.0031308 ? 12.92 * linear : 1.055 * pow(linear, 1 / 2.4) - 0.055
    }

    /// CIE 1931 xy of a Planckian radiator, Kim et al. 2002, clamped to 1667–25000 K.
    static func planckianChromaticity(kelvin: Double) -> SIMD2<Double> {
        let t = min(max(kelvin, 1667), 25000)
        let (t1, t2, t3) = (1e3 / t, 1e6 / (t * t), 1e9 / (t * t * t))
        let x =
            t <= 4000
            ? -0.2661239 * t3 - 0.2343589 * t2 + 0.8776956 * t1 + 0.179910
            : -3.0258469 * t3 + 2.1070379 * t2 + 0.2226347 * t1 + 0.240390
        let y: Double =
            switch t {
            case ...2222: -1.1063814 * x * x * x - 1.34811020 * x * x + 2.18555832 * x - 0.20219683
            case ...4000: -0.9549476 * x * x * x - 1.37418593 * x * x + 2.09137015 * x - 0.16748867
            default: 3.0817580 * x * x * x - 5.87338670 * x * x + 3.75112997 * x - 0.37001483
            }
        return SIMD2(x, y)
    }

    static let xyzToLinearSRGB: simd_double3x3 = {
        let p = InputColorSpace.rec709.primaries
        return rgbToXYZ(p.r, p.g, p.b, white: p.white).inverse
    }()

    enum HLG { static let a = 0.17883277, b = 0.28466892, c = 0.55991073, sceneScale = 0.18 / (0.38 * 0.38 / 3) }
    /// ARRI LogC4 specification constants.
    enum LogC4 { static let a = (262144.0 - 16) / 117.45, b = (1023.0 - 95) / 1023, c = 95.0 / 1023 }
}
