import CoreImage
import EmulsionCore
import EmulsionFixtures
import Foundation
import Testing

/// One golden: a scene rendered with fixed adjustments (and a fixed grain seed). `name` is
/// `scene.variant`, also the golden's file name.
struct RegressionCase: Sendable {
    let name: String
    let scene: @Sendable () throws -> CIImage
    let adjustments: Adjustments
    /// `.displayReferred` cases give a finished picture; it is re-rendered from a scene estimate.
    var contract: InputContract = .sceneReferred
    var thresholds = VisualRegression.thresholds
}

extension RegressionCase {
    static let all: [RegressionCase] = pointCases + spatialCases + displayCases + realSceneCases

    static func named(_ name: String) throws -> RegressionCase {
        try #require(all.first { $0.name == name }, "no regression case named \(name)")
    }

    private static func adjust(_ base: Adjustments = .neutral, _ change: (inout Adjustments) -> Void) -> Adjustments {
        var a = base
        change(&a)
        return a
    }

    /// Point (per-pixel) variants: no grain, no halation.
    private static let pointVariants: [(name: String, adjustments: Adjustments)] = [
        ("neutral", .neutral),
        ("exposure-plus2", adjust { $0.exposure = 2 }),
        ("exposure-minus2", adjust { $0.exposure = -2 }),
        ("warm", adjust { ($0.warmth, $0.tint) = (0.6, -0.3) }),
        ("cool", adjust { ($0.warmth, $0.tint) = (-0.6, 0.3) }),
        ("color-plus", adjust { $0.color = 0.7 }),
        ("color-minus", adjust { $0.color = -0.7 }),
    ]

    private static let pointScenes: [(name: String, image: @Sendable () -> CIImage)] = [
        ("wedge", { SceneFixtures.wedge().image }),
        ("chart24", SceneFixtures.chart24),
        ("primaries", { SceneFixtures.primaries() }),
        ("skin-like", SceneFixtures.skinLike),
    ]

    private static let pointCases = pointScenes.flatMap { scene in
        pointVariants.map { RegressionCase(name: "\(scene.name).\($0.name)", scene: scene.image, adjustments: $0.adjustments) }
    }

    /// The suite's default look: `Adjustments()` (grain and halation 0.35) with a fixed seed.
    static let defaultLook = adjust(Adjustments()) { $0.seed = 7 }

    private static let spatialCases: [RegressionCase] = {
        let highlight: @Sendable () -> CIImage = { SceneFixtures.highlightPoint(size: 200) }
        let gradient: @Sendable () -> CIImage = { SceneFixtures.gradientScene() }
        return [
            RegressionCase(name: "highlight-point.halation", scene: highlight, adjustments: adjust { $0.halation = 1 }),
            RegressionCase(
                name: "highlight-point.halation-exposed", scene: highlight, adjustments: adjust { ($0.exposure, $0.halation) = (1.5, 0.35) }
            ),
            RegressionCase(
                name: "gradient.localtone-recover", scene: gradient, adjustments: adjust { ($0.highlights, $0.shadows) = (0.8, 0.8) }),
            RegressionCase(
                name: "gradient.localtone-contrast", scene: gradient, adjustments: adjust { ($0.highlights, $0.shadows) = (-0.8, -0.8) }),
            RegressionCase(name: "gradient.default-look", scene: gradient, adjustments: defaultLook),
            RegressionCase(name: "gradient.grain", scene: gradient, adjustments: adjust { ($0.grain, $0.seed) = (1, 3) }),
        ]
    }()

    /// A finished Display P3 picture (gray ramp, near-white sky, saturated patches) through the
    /// display-referred path.
    private static let displayCases: [RegressionCase] = [
        ("neutral", Adjustments.neutral), ("exposure-plus2", adjust { $0.exposure = 2 }), ("exposure-minus2", adjust { $0.exposure = -2 }),
    ].map {
        RegressionCase(
            name: "display-chart.\($0.0)", scene: { DisplayFixtures.proofChart() }, adjustments: $0.1, contract: .displayReferred)
    }

    private static let graded = adjust {
        ($0.exposure, $0.warmth, $0.color) = (0.7, 0.3, 0.4)
        ($0.grain, $0.halation, $0.seed) = (0.6, 0.6, 11)
    }

    private static let realSceneCases: [RegressionCase] = RealScene.allCases.flatMap { scene in
        [
            RegressionCase(name: "\(scene.rawValue).default-look", scene: { try scene.image() }, adjustments: defaultLook),
            RegressionCase(name: "\(scene.rawValue).graded", scene: { try scene.image() }, adjustments: graded),
            RegressionCase(
                name: "\(scene.rawValue).localtone", scene: { try scene.image() },
                adjustments: adjust { ($0.highlights, $0.shadows) = (0.5, 0.4) }, thresholds: VisualRegression.photoLocalToneThresholds),
        ]
    }
}
