/// What a negative's values mean, and what the engine may claim about them (docs/ENGINE.md,
/// "Input contracts").
public enum InputContract: Sendable {
    /// Scene light by a published decode: RAW developed with Apple's look off, camera log, linear.
    case sceneReferred
    /// Scene-referred by its standard but usually rendered by the camera before encoding (HLG).
    /// Decoded as scene light; not claimed to be the scene.
    case nominalScene
    /// A finished picture made for a display (JPEG, HEIC, Rec.709, Display P3). Its scene light
    /// can't be recovered: the engine re-renders it from an estimate.
    case displayReferred
}
