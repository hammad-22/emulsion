import Foundation

/// Environment variables that switch on opt-in tests and probes. The raw values are the
/// documented names (`Tests/AGENTS.md`); don't rename them. `ReviewRenders` reads its own:
/// it must build without the rest of the test target.
enum TestEnvironment: String {
    /// ":"-separated folders of real DNGs; real samples never enter the repo.
    case rawSamples = "EMULSION_RAW_SAMPLES"
    case rawProbe = "EMULSION_RAW_PROBE"
    /// Folder the RAW probe writes its wedge DNGs to.
    case rawProbeDump = "EMULSION_RAW_PROBE_DUMP"
    /// Folder for the RAW develop before/after PNGs.
    case proofDirectory = "EMULSION_PROOF_DIR"
    /// Folder for the display-referred proof renders.
    case displayReferredProof = "EMULSION_PROOF"

    var value: String? { ProcessInfo.processInfo.environment[rawValue] }
    var isSet: Bool { value != nil }
}
