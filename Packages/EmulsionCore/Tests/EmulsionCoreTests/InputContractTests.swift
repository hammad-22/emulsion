import EmulsionFixtures
import Testing

@testable import EmulsionCore

/// Every input declares what its light means, and the developed negative carries it through
/// the pipeline (docs/ENGINE.md, "Input contracts").
struct InputContractTests {
    private static let expected: [InputColorSpace: InputContract] = [
        .appleLog: .sceneReferred,
        .sLog3SGamut3Cine: .sceneReferred,
        .arriLogC3: .sceneReferred,
        .arriLogC4: .sceneReferred,
        .vLog: .sceneReferred,
        .davinciIntermediate: .sceneReferred,
        .acescct: .sceneReferred,
        .linearP3: .sceneReferred,
        .hlgRec2020: .nominalScene,
        .rec709: .displayReferred,
        .displayP3: .displayReferred,
    ]

    private var renderer: Renderer { EmulsionTestCase.sharedRenderer }

    @Test(arguments: InputColorSpace.allCases)
    func everyInputDeclaresItsContract(space: InputColorSpace) throws {
        let contract = try #require(Self.expected[space], "\(space) is missing from the expected table")
        #expect(space.contract == contract)
    }

    @Test(arguments: [InputColorSpace.appleLog, .hlgRec2020, .displayP3])
    func encodedNegativeCarriesItsSpaceContract(space: InputColorSpace) throws {
        let codes: [SIMD3<Float>] = [SIMD3(0.4, 0.4, 0.4), SIMD3(0.6, 0.3, 0.2)]
        let image = Fixtures.row(codes, space: nil)
        let negative = try renderer.developer.scene(fromEncoded: image, as: space, range: .full)
        #expect(negative.contract == space.contract)
    }

    @Test func jpegDevelopsAsDisplayReferredThroughMaterializeAndResize() throws {
        let picture = try renderer.render(Negative(image: SceneFixtures.patches(cell: 16), contract: .sceneReferred), .neutral)
        let jpeg = try renderer.export(picture, format: .jpeg)

        let developed = try renderer.developer.develop(jpeg)
        #expect(developed.contract == .displayReferred)
        let materialized = try renderer.materialize(developed)
        #expect(materialized.contract == .displayReferred)
        let resized = renderer.resized(materialized, longestEdge: materialized.size.width / 2)
        #expect(resized.size.width < materialized.size.width)
        #expect(resized.contract == .displayReferred)
    }
}
