/// What a negative's values mean (docs/ENGINE.md, "Input contracts").
public enum InputContract: Sendable {
    /// Scene light by a published decode: RAW, camera log, linear.
    case sceneReferred
    /// Scene-referred by its standard but usually camera-rendered (HLG); not claimed to be the scene.
    case nominalScene
    /// A finished picture for a display (JPEG, HEIC, Rec.709, P3), re-rendered from an estimate.
    case displayReferred
    /// A display-referred scene estimate printed absolutely, for the viewfinder; preview only.
    case previewEstimate
}
