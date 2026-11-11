"""Independent reference values for the visual regression suite's colour difference (MOV-37).

Three tables, all computed by colour-science, never by the engine:

- `lab_pairs`: the 34 CIEDE2000 test pairs of Sharma, Wu & Dalal (2005), "The CIEDE2000
  colour-difference formula: implementation notes, supplementary test data, and mathematical
  observations", Color Res. Appl. 30(1), Table 1. The script asserts colour-science reproduces
  the published dE00 column before writing anything.
- `p3_pairs`: Display P3 encoded RGB pairs (sRGB EOTF, P3-D65 primaries with derived matrices)
  -> CIELAB with the colourspace's D65 white, and their dE00.
- `chart24`: the "ColorChecker 2005" dataset's 24 patches as linear Rec.709/D65 scene values
  (derived matrices, Bradford adaptation from the dataset's illuminant), the engine's working space.

Offline tool only: nothing here ships. Re-run after changing a pair or the pinned colour-science:

    python3 -m venv .venv && .venv/bin/pip install -r Tools/color-references/requirements.txt
    .venv/bin/python -I Tools/color-references/generate_delta_e_references.py

The output is deterministic (values rounded to 10 significant digits).
"""

import json
import pathlib
import sys
import warnings

warnings.filterwarnings("ignore", module="colour")  # optional SciPy/Matplotlib notices

import colour  # noqa: E402
import numpy as np  # noqa: E402

OUTPUT = pathlib.Path(__file__).resolve().parents[2] / "Packages/EmulsionCore/Tests/EmulsionCoreTests/References/delta-e.json"
SIGNIFICANT_DIGITS = 10
PUBLISHED_TOLERANCE = 1e-4  # the published column has 4 decimals

# (L1, a1, b1), (L2, a2, b2), published dE00: Sharma, Wu & Dalal (2005), Table 1.
SHARMA_PAIRS = [
    ((50.0000, 2.6772, -79.7751), (50.0000, 0.0000, -82.7485), 2.0425),
    ((50.0000, 3.1571, -77.2803), (50.0000, 0.0000, -82.7485), 2.8615),
    ((50.0000, 2.8361, -74.0200), (50.0000, 0.0000, -82.7485), 3.4412),
    ((50.0000, -1.3802, -84.2814), (50.0000, 0.0000, -82.7485), 1.0000),
    ((50.0000, -1.1848, -84.8006), (50.0000, 0.0000, -82.7485), 1.0000),
    ((50.0000, -0.9009, -85.5211), (50.0000, 0.0000, -82.7485), 1.0000),
    ((50.0000, 0.0000, 0.0000), (50.0000, -1.0000, 2.0000), 2.3669),
    ((50.0000, -1.0000, 2.0000), (50.0000, 0.0000, 0.0000), 2.3669),
    ((50.0000, 2.4900, -0.0010), (50.0000, -2.4900, 0.0009), 7.1792),
    ((50.0000, 2.4900, -0.0010), (50.0000, -2.4900, 0.0010), 7.1792),
    ((50.0000, 2.4900, -0.0010), (50.0000, -2.4900, 0.0011), 7.2195),
    ((50.0000, 2.4900, -0.0010), (50.0000, -2.4900, 0.0012), 7.2195),
    ((50.0000, -0.0010, 2.4900), (50.0000, 0.0009, -2.4900), 4.8045),
    ((50.0000, -0.0010, 2.4900), (50.0000, 0.0010, -2.4900), 4.8045),
    ((50.0000, -0.0010, 2.4900), (50.0000, 0.0011, -2.4900), 4.7461),
    ((50.0000, 2.5000, 0.0000), (50.0000, 0.0000, -2.5000), 4.3065),
    ((50.0000, 2.5000, 0.0000), (73.0000, 25.0000, -18.0000), 27.1492),
    ((50.0000, 2.5000, 0.0000), (61.0000, -5.0000, 29.0000), 22.8977),
    ((50.0000, 2.5000, 0.0000), (56.0000, -27.0000, -3.0000), 31.9030),
    ((50.0000, 2.5000, 0.0000), (58.0000, 24.0000, 15.0000), 19.4535),
    ((50.0000, 2.5000, 0.0000), (50.0000, 3.1736, 0.5854), 1.0000),
    ((50.0000, 2.5000, 0.0000), (50.0000, 3.2972, 0.0000), 1.0000),
    ((50.0000, 2.5000, 0.0000), (50.0000, 1.8634, 0.5757), 1.0000),
    ((50.0000, 2.5000, 0.0000), (50.0000, 3.2592, 0.3350), 1.0000),
    ((60.2574, -34.0099, 36.2677), (60.4626, -34.1751, 39.4387), 1.2644),
    ((63.0109, -31.0961, -5.8663), (62.8187, -29.7946, -4.0864), 1.2630),
    ((61.2901, 3.7196, -5.3901), (61.4292, 2.2480, -4.9620), 1.8731),
    ((35.0831, -44.1164, 3.7933), (35.0232, -40.0716, 1.5901), 1.8645),
    ((22.7233, 20.0904, -46.6940), (23.0331, 14.9730, -42.5619), 2.0373),
    ((36.4612, 47.8580, 18.3852), (36.2715, 50.5065, 21.2231), 1.4146),
    ((90.8027, -2.0831, 1.4410), (91.1528, -1.6435, 0.0447), 1.4441),
    ((90.9257, -0.5406, -0.9208), (88.6381, -0.8985, -0.7239), 1.5381),
    ((6.7747, -0.2908, -2.4247), (5.8714, -0.0985, -2.2286), 0.6377),
    ((2.0776, 0.0795, -1.1350), (0.9033, -0.0636, -0.5514), 0.9082),
]

P3 = colour.RGB_COLOURSPACES["Display P3"].copy()
P3.use_derived_transformation_matrices(True)

# The engine's working space, defined by its primaries (see generate_input_references.py).
WORKING = colour.RGB_COLOURSPACES["sRGB"].copy()
WORKING.use_derived_transformation_matrices(True)

STEP_8BIT = 1 / 255
STEP_16BIT = 1 / 65535

# Display P3 encoded pairs: neutrals, darks, saturated primaries, skin-like, one-code steps.
P3_PAIRS = [
    ("black vs near-black", (0, 0, 0), (0.02, 0.02, 0.02)),
    ("mid-gray vs lighter gray", (0.5, 0.5, 0.5), (0.52, 0.52, 0.52)),
    ("white vs off-white", (1, 1, 1), (0.98, 0.99, 1)),
    ("gray vs slightly warm gray", (0.46, 0.46, 0.46), (0.48, 0.46, 0.44)),
    ("dark red vs dark brown", (0.05, 0.01, 0.01), (0.06, 0.03, 0.01)),
    ("dark blue vs dark gray", (0.02, 0.03, 0.08), (0.04, 0.04, 0.04)),
    ("red vs orange-red", (1, 0, 0), (1, 0.2, 0)),
    ("green vs yellow-green", (0, 1, 0), (0.3, 1, 0)),
    ("blue vs violet", (0, 0, 1), (0.2, 0, 1)),
    ("cyan vs magenta", (0, 1, 1), (1, 0, 1)),
    ("yellow vs white", (1, 1, 0), (1, 1, 1)),
    ("light skin vs warmer", (0.80, 0.62, 0.52), (0.84, 0.62, 0.48)),
    ("dark skin vs lighter", (0.45, 0.32, 0.26), (0.50, 0.36, 0.29)),
    ("skin vs grey", (0.72, 0.55, 0.45), (0.58, 0.58, 0.58)),
    ("mid-gray one 8-bit code in red", (0.5, 0.5, 0.5), (0.5 + STEP_8BIT, 0.5, 0.5)),
    ("dark one 8-bit code in blue", (0.1, 0.1, 0.1), (0.1, 0.1, 0.1 + STEP_8BIT)),
    ("saturated green one 8-bit code", (0.1, 0.8, 0.2), (0.1, 0.8 + STEP_8BIT, 0.2)),
    ("mid-gray one 16-bit code", (0.5, 0.5, 0.5), (0.5 + STEP_16BIT, 0.5, 0.5)),
    ("near-black one 16-bit code", (0.002, 0.002, 0.002), (0.002, 0.002 + STEP_16BIT, 0.002)),
    ("identical", (0.3, 0.6, 0.9), (0.3, 0.6, 0.9)),
]


def rounded(values):
    return [float(f"{v:.{SIGNIFICANT_DIGITS}g}") + 0.0 for v in np.ravel(values)]  # + 0.0 drops -0.0


def delta_e(lab1, lab2):
    return float(colour.delta_E(np.array(lab1, dtype=float), np.array(lab2, dtype=float), method="CIE 2000"))


def lab_pairs():
    rows = []
    for index, (lab1, lab2, published) in enumerate(SHARMA_PAIRS, start=1):
        computed = delta_e(lab1, lab2)
        if abs(computed - published) > PUBLISHED_TOLERANCE:
            sys.exit(f"pair {index}: colour-science {computed} vs published {published}")
        rows.append({"pair": index, "lab1": list(lab1), "lab2": list(lab2), "deltaE": rounded([computed])[0]})
    return rows


def p3_lab(encoded):
    xyz = colour.RGB_to_XYZ(colour.models.eotf_sRGB(np.array(encoded, dtype=float)), P3)
    return colour.XYZ_to_Lab(xyz, illuminant=P3.whitepoint)


def p3_pairs():
    rows = []
    for label, rgb1, rgb2 in P3_PAIRS:
        lab1, lab2 = p3_lab(rgb1), p3_lab(rgb2)
        rows.append({"label": label, "rgb1": rounded(rgb1), "rgb2": rounded(rgb2),
                     "lab1": rounded(lab1), "lab2": rounded(lab2), "deltaE": rounded([delta_e(lab1, lab2)])[0]})
    return rows


def chart24():
    chart = colour.CCS_COLOURCHECKERS["ColorChecker 2005"]
    rows = []
    for name, xyY in chart.data.items():
        linear = colour.XYZ_to_RGB(colour.xyY_to_XYZ(xyY), WORKING, illuminant=chart.illuminant,
                                   chromatic_adaptation_transform="Bradford")
        rows.append({"name": name, "linear": rounded(linear)})
    return rows


def main():
    header = {
        "generator": "Tools/color-references/generate_delta_e_references.py",
        "colourScience": colour.__version__,
        "lab": "CIELAB, D65 white of Display P3 (x 0.3127, y 0.3290), no chromatic adaptation",
        "chart24Source": "colour-science CCS_COLOURCHECKERS['ColorChecker 2005'], Bradford to linear Rec.709/D65",
    }
    tables = {"lab_pairs": lab_pairs(), "p3_pairs": p3_pairs(), "chart24": chart24()}
    lines = [f" {json.dumps(k)}: {json.dumps(v)}" for k, v in header.items()]
    for key, rows in tables.items():
        lines.append(f" {json.dumps(key)}: [\n" + ",\n".join("  " + json.dumps(row) for row in rows) + "\n ]")
    OUTPUT.write_text("{\n" + ",\n".join(lines) + "\n}\n")
    print(f"wrote {', '.join(f'{len(v)} {k}' for k, v in tables.items())} to {OUTPUT}", file=sys.stderr)


if __name__ == "__main__":
    main()
