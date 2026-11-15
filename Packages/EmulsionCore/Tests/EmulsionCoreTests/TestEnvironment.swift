import Foundation

/// Opt-in switches; raw values are the names in Tests/AGENTS.md. `ReviewRenders` reads its own.
enum TestEnvironment: String {
    case rawSamples = "EMULSION_RAW_SAMPLES"
    case rawProbe = "EMULSION_RAW_PROBE"
    case rawProbeDump = "EMULSION_RAW_PROBE_DUMP"
    case proofDirectory = "EMULSION_PROOF_DIR"
    case displayReferredProof = "EMULSION_PROOF"

    var value: String? { ProcessInfo.processInfo.environment[rawValue] }
    var isSet: Bool { value != nil }
}
