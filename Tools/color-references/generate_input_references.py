"""Independent reference vectors for Emulsion's input transforms (MOV-85, MOV-97).

For every `InputColorSpace`, decodes a fixed set of code-value triplets with colour-science
and converts them to linear sRGB / Rec.709 (D65, Bradford adaptation): the engine's working
space. The engine is never consulted, so the tests compare it against an outside source rather
than against its own Swift mirror.

Offline tool only: nothing here ships. Re-run after changing a sample set or the pinned
colour-science version:

    python3 -m venv .venv && .venv/bin/pip install -r Tools/color-references/requirements.txt
    .venv/bin/python -I Tools/color-references/generate_input_references.py

The output is deterministic (values rounded to 10 significant digits).
"""

import functools
import json
import pathlib
import sys
import warnings

warnings.filterwarnings("ignore", module="colour")  # optional SciPy/Matplotlib notices

import colour  # noqa: E402
import numpy as np  # noqa: E402

OUTPUT = pathlib.Path(__file__).resolve().parents[2] / (
    "Packages/EmulsionCore/Tests/EmulsionCoreTests/References/input-transforms.json"
)
DELTA = 0.002  # code-value offset either side of a curve's linear/log cut
SIGNIFICANT_DIGITS = 10

# The working space is defined by its primaries, like the engine's. colour-science's "sRGB"
# carries the rounded 4-digit IEC 61966-2-1 matrices, which differ by up to ~2e-5 absolute.
WORKING = colour.RGB_COLOURSPACES["sRGB"].copy()
WORKING.use_derived_transformation_matrices(True)

# Engine convention, not a colour-science default: HLG scene light is scaled so a 38% signal
# is 18% gray (ITU-R BT.2408 reference level), matching `ColorMath.HLG.sceneScale`.
HLG_SCENE_SCALE = 0.18 / (0.38 * 0.38 / 3)
m = colour.models


def hlg_decode(v):
    return m.oetf_inverse_BT2100_HLG(v) * HLG_SCENE_SCALE


def hlg_encode(x):
    return m.oetf_BT2100_HLG(x / HLG_SCENE_SCALE)


def identity(v):
    return np.asarray(v, dtype=float)


LOGC3_EI800 = dict(firmware="SUP 3.x", method="Linear Scene Exposure Factor", EI=800)
logc3_decode = functools.partial(m.log_decoding_ARRILogC3, **LOGC3_EI800)
logc3_encode = functools.partial(m.log_encoding_ARRILogC3, **LOGC3_EI800)
bt1886_decode = functools.partial(m.eotf_BT1886, L_B=0, L_W=1)
bt1886_encode = functools.partial(m.eotf_inverse_BT1886, L_B=0, L_W=1)


# rawValue: (description, decode, encode, colourspace, code-value cuts, scene-referred)
# Cuts are where each published curve switches branch (code-value domain):
#   Apple Log Profile white paper: P_t = sigma (R_t - R_0)^2, and 0 (clamp to R_0 below);
#   Sony S-Log3: 171.2102946929 / 1023; ARRI LogC3 SUP 3.x EI 800: e*cut + f = 0.149658;
#   ARRI LogC4: 0; Panasonic V-Log: 0.181; DaVinci Intermediate: 0.02740668;
#   ACEScct (S-2016-001): 0.155251141552511; BT.2100 HLG: 0.5; sRGB (IEC 61966-2-1): 0.04045;
#   BT.1886: 0 (clamp).
APPLE = m.rgb.transfer_functions.apple_log_profile.CONSTANTS_APPLE_LOG_PROFILE
APPLE_LOG_CUT = APPLE.sigma * (APPLE.R_t - APPLE.R_0) ** 2

SPACES = {
    "appleLog": ("Apple Log Profile, Rec.2020 primaries", m.log_decoding_AppleLogProfile,
                 m.log_encoding_AppleLogProfile, "ITU-R BT.2020", [APPLE_LOG_CUT, 0.0], True),
    "sLog3SGamut3Cine": ("Sony S-Log3, S-Gamut3.Cine", m.log_decoding_SLog3, m.log_encoding_SLog3,
                         "S-Gamut3.Cine", [171.2102946929 / 1023], True),
    "arriLogC3": ("ARRI LogC3 SUP 3.x EI 800, ARRI Wide Gamut 3", logc3_decode, logc3_encode,
                  "ARRI Wide Gamut 3", [0.149658], True),
    "arriLogC4": ("ARRI LogC4, ARRI Wide Gamut 4", m.log_decoding_ARRILogC4, m.log_encoding_ARRILogC4,
                  "ARRI Wide Gamut 4", [0.0], True),
    "vLog": ("Panasonic V-Log, V-Gamut", m.log_decoding_VLog, m.log_encoding_VLog, "V-Gamut", [0.181], True),
    "davinciIntermediate": ("DaVinci Intermediate, DaVinci Wide Gamut", m.oetf_inverse_DaVinciIntermediate,
                            m.oetf_DaVinciIntermediate, "DaVinci Wide Gamut", [0.02740668], True),
    "acescct": ("ACEScct, AP1 (ACES white, Bradford to D65)", m.log_decoding_ACEScct, m.log_encoding_ACEScct,
                "ACEScct", [0.155251141552511], True),
    "hlgRec2020": ("BT.2100 HLG inverse OETF x BT.2408 scene scale, Rec.2020", hlg_decode, hlg_encode,
                   "ITU-R BT.2020", [0.5], True),
    "rec709": ("BT.1886 EOTF (gamma 2.4, L_B = 0), Rec.709", bt1886_decode, bt1886_encode, WORKING, [0.0], False),
    "displayP3": ("sRGB piecewise EOTF, Display P3", m.eotf_sRGB, m.eotf_inverse_sRGB, "Display P3",
                  [0.04045], False),
    "linearP3": ("Linear, Display P3 primaries", identity, identity, "Display P3", [], True),
}


def samples(encode, cuts, scene_referred):
    """Labelled code-value triplets: neutrals, primaries, black, superwhite, negatives, cuts."""
    code = lambda x: float(encode(x))  # noqa: E731
    mid = code(0.18)
    out = [("code 0", (0.0, 0.0, 0.0)), ("code -0.05 (negative)", (-0.05, -0.05, -0.05))]
    out.append(("black", (code(0.0),) * 3))
    out.append(("mid-gray", (mid,) * 3))
    out.append(("code 1.0", (1.0, 1.0, 1.0)))
    if scene_referred:
        out.append(("superwhite (16x linear)", (code(16.0),) * 3))
    else:
        out.append(("superwhite (code 1.05)", (1.05, 1.05, 1.05)))
    hi, lo = code(0.9), code(0.01)
    for name, triplet in [
        ("red", (hi, lo, lo)), ("green", (lo, hi, lo)), ("blue", (lo, lo, hi)),
        ("cyan", (lo, hi, hi)), ("magenta", (hi, lo, hi)), ("yellow", (hi, hi, lo)),
    ]:
        out.append((f"saturated {name}", triplet))
    out.append(("negative red channel", (-0.02, mid, mid)))
    for c in cuts:
        out.append((f"cut {c:.6g} - {DELTA}", (c - DELTA,) * 3))
        out.append((f"cut {c:.6g} + {DELTA}", (c + DELTA,) * 3))
        out.append((f"cut {c:.6g} straddled", (c - DELTA, c + DELTA, c)))
    out += [(f"grid {v:.2f}", (v, v, v)) for v in (0.05, 0.2, 0.35, 0.5, 0.65, 0.8, 0.95)]
    unique = {}
    for label, triplet in out:
        unique.setdefault(triplet, label)  # e.g. display "black" is code 0
    return [(label, triplet) for triplet, label in unique.items()]


def rounded(values):
    return [float(f"{v:.{SIGNIFICANT_DIGITS}g}") + 0.0 for v in values]  # + 0.0 drops -0.0


def compact_json(table):
    """Pretty-printed, but one sample per line so diffs stay readable."""
    spaces = ",\n".join(
        f'  "{key}": {{"source": {json.dumps(space["source"])}, "samples": [\n'
        + ",\n".join("   " + json.dumps(row) for row in space["samples"])
        + "\n  ]}"
        for key, space in table["spaces"].items()
    )
    header = ",\n".join(f" {json.dumps(k)}: {json.dumps(v)}" for k, v in table.items() if k != "spaces")
    return "{\n" + header + ',\n "spaces": {\n' + spaces + "\n }\n}"


def main():
    table = {
        "generator": "Tools/color-references/generate_input_references.py",
        "colourScience": colour.__version__,
        "workingSpace": "linear Rec.709 primaries, D65, matrix derived from primaries (Bradford adaptation)",
        "spaces": {},
    }
    for key, (description, decode, encode, colourspace, cuts, scene_referred) in SPACES.items():
        rows = []
        for label, codes in samples(encode, cuts, scene_referred):
            linear = decode(np.array(codes, dtype=float))
            working = colour.RGB_to_RGB(linear, colourspace, WORKING, chromatic_adaptation_transform="Bradford")
            rows.append({"label": label, "code": rounded(codes), "working": rounded(working)})
        table["spaces"][key] = {"source": description, "samples": rows}
    OUTPUT.write_text(compact_json(table) + "\n")
    print(f"wrote {sum(len(s['samples']) for s in table['spaces'].values())} samples to {OUTPUT}", file=sys.stderr)


if __name__ == "__main__":
    main()
