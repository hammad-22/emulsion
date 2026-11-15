"""Digitize Kodak's diffuse rms granularity curves and 2383 MTF chart for Emulsion (grain v2).

Reads the chart rasters embedded in Kodak's technical-data PDFs (H-1-5207 250D, H-1-5219 500T,
H-1-2383 print film), calibrates each axis from its detected tick marks, traces the curves
column by column and writes:

- `<stock>.granularity.csv`: sigma_D (48 um aperture) and density per layer on a 0.1 grid of the
  chart's log relative exposure, with flags for spans that are bridged, shared or uncertain;
- `granularity.json`: sources, axis residuals, the 18% gray placement (camera stop 0) on the
  granularity chart, the 8-knot sigma_D table in log10 exposure relative to gray, interpolation
  errors, and the 2383 MTF 50% frequencies.

Offline tool only: nothing here ships, and the PDFs and chart artwork are never copied into
the repository (only numbers read from them). Run:

    python3 -m venv .venv && .venv/bin/pip install -r Tools/grain-reference/granularity/requirements.txt
    .venv/bin/python -I Tools/grain-reference/granularity/digitize_granularity.py \
        --pdf-dir <folder with the Kodak PDFs> --out Tools/grain-reference/granularity \
        [--overlays <scratch dir>]

Needs poppler's `pdfimages` on PATH. Output is deterministic for the pinned PDFs (SHA-256
checked) and the pinned NumPy/Pillow versions.

Method notes (details in README.md):
- The charts are embedded rasters (213-229 ppi), so they are read at native resolution with
  `pdfimages`; rendering the page at a higher dpi would only resample the same pixels.
- Each curve is traced inside a corridor around hand-placed guide waypoints (chart units,
  listed below) with a continuity predictor; the waypoints only decide *which* line a pixel run
  belongs to, the values come from the pixels (darkness-weighted run centres).
- Solid characteristic curves are traced first and erased, then the dashed/dotted granularity
  curves are traced on what remains. Dash gaps and crossings are bridged by linear
  interpolation; spans hidden under a solid curve take the solid curve's centre.
"""

import argparse
import csv
import hashlib
import json
import math
import pathlib
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw

DARK = 160  # 8-bit gray below which a pixel counts as ink (anti-aliased black line art on white)
GRID_STEP = 0.1  # output grid of the granularity chart's x axis (log relative exposure)
LOG10_2 = math.log10(2.0)  # log10 exposure per camera stop (a stop is a factor of 2)
KNOT_COUNT = 8
KNOT_TARGET = 2.4  # the engine's table covers -2.4 ... +2.4 log10 exposure about 18% gray
LAYERS = ("R", "G", "B")
GAUSSIAN_MTF_SIGMA_FACTOR = math.sqrt(math.log(2.0) / (2.0 * math.pi**2))  # FILM-THEORY 6.3: ~0.187

# --------------------------------------------------------------------------------------------
# Sources. Revision strings are as printed on the sheets (header and footer).
# --------------------------------------------------------------------------------------------
SOURCES = {
    "kodak-vision3-250d-5207": {
        "pdf": "KODAK-VISION3-250D-5207-7207-technical-information.pdf",
        "sha256": "70adb298a7aabb285d986b720e07c87c27eb2361f0925aea2b15903c08282e16",
        "publication": "KODAK Publication No. H-1-5207",
        "revision_as_printed": "header 'MARCH 2026 H-1-5207'; footer 'Revised 3-26'",
        "page": 3,
    },
    "kodak-vision3-500t-5219": {
        "pdf": "KODAK-VISION3-5219-7219-technical-information.pdf",
        "sha256": "6d037d8090373ee50d10bedfff3df14777a575dd107c50edcafc7ec5862d0972",
        "publication": "KODAK Publication No. H-1-5219",
        "revision_as_printed": "header 'MARCH 2026 H-1-5219'; footer 'Revised 3-26'",
        "page": 3,
    },
    "kodak-vision-2383": {
        "pdf": "KODAK-VISION-Color-Print-Film-2383-3383-technical-information.pdf",
        "sha256": "a72fa4482ebd891a9ac4a823cafe740e3587c56470f27e4dfd4391f5c3e5a207",
        "publication": "KODAK Publication No. H-1-2383",
        "revision_as_printed": "header 'AUGUST 2026 H-1-2383'; footer 'Revised 8-26'",
        "page": 4,
    },
}
APERTURE_STATEMENT = "Read with a microdensitometer, using a 48-micrometre aperture."
EQUIPMENT_NOTE = (
    "Note: This curve represents granularity based on modified measuring techniques. "
    "Sensitometric and Diffuse RMS Granularity curves are produced on different equipment. "
    "A slight variation in curve shape may be noticed."
)

# --------------------------------------------------------------------------------------------
# Chart specifications. Pixel positions are in the embedded raster's own pixels and only seed
# the tick search (+-3 px); the fitted positions come from the detected tick marks.
# Guides are (x, value) waypoints in chart units; they select which line a pixel run belongs to.
# --------------------------------------------------------------------------------------------
GRANULARITY_CHARTS = {
    "kodak-vision3-250d-5207": {
        "image": (0, (587, 557)),
        "frame": (62, 506, 61.5, 505.5),  # x of x=0, x of x=5, y of D=3, y of D=0 (seeds)
        "x_ticks": [(v, 62 + v * 88.8) for v in range(6)],
        "x_tick_band": "inside",
        "density_ticks": [(round(0.2 * i, 1), 505.5 - i * 29.6) for i in range(16)],
        "sigma_ticks": [  # (sigma_D, seed y, labelled on the chart)
            (0.10, 226, True), (0.05, 268, True), (0.04, 281.5, True), (0.03, 299, True),
            (0.02, 323.5, True), (0.01, 365.5, True), (0.009, 372, False), (0.008, 379.5, False),
            (0.007, 387.5, False), (0.006, 396.5, True), (0.005, 408, True), (0.004, 421, True),
            (0.003, 439, True), (0.002, 463, True), (0.001, 505.5, True),
        ],
        "masks": [  # text: "Process: ECN-2", the six curve letters, x-axis tick marks
            (77, 74, 206, 91), (426, 75, 439, 91), (456, 102, 471, 118), (474, 195, 487, 211),
            (380, 334, 392, 349), (379, 364, 394, 380), (382, 413, 395, 428), (63, 492, 505, 505),
        ],
        "solid_guides": {
            "B": [(0.0, 1.01), (0.9, 1.02), (1.0, 1.04), (1.2, 1.09), (1.4, 1.15), (1.6, 1.25),
                  (1.8, 1.35), (2.0, 1.49), (2.2, 1.61), (2.4, 1.73), (2.6, 1.85), (2.8, 1.98),
                  (3.0, 2.08), (3.2, 2.21), (3.4, 2.34), (3.6, 2.46), (3.8, 2.57), (4.0, 2.68),
                  (4.2, 2.77), (4.4, 2.86), (4.6, 2.92), (4.8, 2.98), (5.0, 3.0)],
            "G": [(0.0, 0.6), (0.9, 0.6), (1.0, 0.61), (1.2, 0.64), (1.3, 0.67), (1.4, 0.71),
                  (1.5, 0.75), (1.6, 0.81), (1.7, 0.88), (1.8, 0.94), (1.9, 1.0), (2.0, 1.07),
                  (2.2, 1.2), (2.4, 1.33), (2.6, 1.45), (2.8, 1.56), (3.0, 1.69), (3.2, 1.82),
                  (3.4, 1.95), (3.6, 2.08), (3.8, 2.2), (4.0, 2.33), (4.2, 2.44), (4.4, 2.54),
                  (4.6, 2.61), (4.8, 2.66), (5.0, 2.7)],
            "R": [(0.0, 0.23), (0.9, 0.23), (1.0, 0.24), (1.2, 0.26), (1.4, 0.32), (1.6, 0.41),
                  (1.8, 0.51), (2.0, 0.63), (2.2, 0.74), (2.4, 0.86), (2.6, 0.97), (2.8, 1.06),
                  (3.0, 1.17), (3.2, 1.27), (3.4, 1.38), (3.6, 1.49), (3.8, 1.59), (4.0, 1.69),
                  (4.2, 1.79), (4.4, 1.87), (4.6, 1.94), (4.8, 1.99), (5.0, 2.02)],
        },
        "grain_guides": {
            "B": [(0.0, 0.0117), (0.3, 0.0124), (0.5, 0.01185), (0.9, 0.0122), (1.0, 0.0149), (1.1, 0.0159),
                  (1.3, 0.0163), (1.5, 0.0157), (1.7, 0.0156), (1.8, 0.0153), (1.9, 0.0142), (2.0, 0.0136),
                  (2.1, 0.0129), (2.2, 0.0124), (2.5, 0.0129), (2.7, 0.0123), (2.9, 0.0137), (3.1, 0.0139),
                  (3.3, 0.0133), (3.5, 0.01265), (3.7, 0.012), (3.9, 0.0113), (4.0, 0.0109), (4.2, 0.01),
                  (4.4, 0.0091), (4.6, 0.00817), (4.8, 0.00705), (5.0, 0.0061)],
            "G": [(0.0, 0.0058), (0.3, 0.0059), (0.5, 0.0056), (0.7, 0.00545), (0.9, 0.0056), (1.0, 0.0067),
                  (1.1, 0.0075), (1.2, 0.0081), (1.3, 0.009), (1.5, 0.0102), (1.6, 0.0106), (1.7, 0.01),
                  (1.8, 0.0097), (1.9, 0.0084), (2.0, 0.0081), (2.1, 0.0076), (2.2, 0.00745), (2.3, 0.007),
                  (2.4, 0.0066), (2.5, 0.0063), (2.6, 0.0061), (2.8, 0.0062), (3.0, 0.0065), (3.2, 0.0067),
                  (3.5, 0.0071), (3.7, 0.0067), (3.8, 0.00655), (4.1, 0.00613), (4.2, 0.006), (4.5, 0.0053),
                  (4.6, 0.00524), (4.8, 0.00503), (4.9, 0.0048), (5.0, 0.0047)],
            "R": [(0.0, 0.0051), (0.3, 0.0051), (0.5, 0.00503), (0.6, 0.00511), (0.7, 0.0054), (0.9, 0.0055),
                  (1.0, 0.00593), (1.1, 0.00682), (1.2, 0.0078), (1.3, 0.0087), (1.5, 0.0096), (1.6, 0.0097),
                  (1.7, 0.0092), (1.8, 0.009), (1.9, 0.0084), (2.0, 0.0081), (2.1, 0.0076), (2.2, 0.00745),
                  (2.3, 0.007), (2.4, 0.0066), (2.5, 0.0063), (2.6, 0.006), (2.8, 0.00573), (2.9, 0.00564),
                  (3.1, 0.00541), (3.5, 0.00537), (3.6, 0.00519), (3.8, 0.00486), (4.0, 0.00463), (4.2, 0.00455),
                  (4.6, 0.00444), (4.7, 0.00423), (4.9, 0.00426), (5.0, 0.0044)],
        },
        "grain_style": "dashed",
        "grain_guide_tolerance_px": 4.0,  # G and R run 4-8 px apart; a wider corridor jumps lines
        # Spans where a granularity line is hidden under a solid curve: take the solid's centre.
        "on_solid": {"B": [("B", 0.0, 0.85)]},
        # Spans where G and R are separate lines but which is which cannot be read from the
        # chart (they touch at x ~ 0.72 and merge again from ~1.5 to ~2.5). See README.
        "identity_uncertain": {"G": [(0.0, 1.85)], "R": [(0.0, 1.85)]},
    },
    "kodak-vision3-500t-5219": {
        "image": (0, (587, 574)),
        "frame": (60.5, 507.5, 60.0, 506.5),
        "x_ticks": [(round(0.2 * i, 1), 60.5 + i * 17.88) for i in range(26)],
        "x_tick_band": "inside",
        "density_ticks": [(round(0.2 * i, 1), 506.5 - i * 29.77) for i in range(16)],
        "sigma_ticks": [
            (0.10, 225.5, True), (0.05, 267.5, True), (0.04, 281.5, True), (0.03, 298.5, True),
            (0.02, 323.5, True), (0.01, 365.5, True), (0.009, 372.5, False), (0.008, 379.5, False),
            (0.007, 387.5, False), (0.006, 397, True), (0.005, 408.5, True), (0.004, 421.5, True),
            (0.003, 439.5, True), (0.002, 464, True), (0.001, 506.5, True),
        ],
        "masks": [  # text, legend box, curve letters, x-axis tick marks
            (73, 68, 221, 86), (84, 102, 274, 236), (438, 76, 450, 91), (459, 123, 473, 138),
            (476, 195, 490, 210), (370, 304, 382, 319), (342, 360, 356, 375), (340, 403, 352, 417),
            (61, 494, 507, 506),
        ],
        "solid_guides": {
            "B": [(0.0, 0.9), (0.9, 0.92), (1.0, 0.94), (1.1, 0.97), (1.2, 1.0), (1.3, 1.05),
                  (1.4, 1.08), (1.5, 1.13), (1.6, 1.19), (1.7, 1.24), (1.8, 1.3), (1.9, 1.36),
                  (2.0, 1.42), (2.1, 1.49), (2.2, 1.55), (2.3, 1.61), (2.4, 1.67), (2.5, 1.73),
                  (2.6, 1.79), (2.8, 1.91), (3.0, 2.03), (3.2, 2.14), (3.4, 2.26), (3.6, 2.39),
                  (3.8, 2.49), (4.0, 2.6), (4.2, 2.7), (4.4, 2.79), (4.6, 2.87), (4.8, 2.92),
                  (5.0, 2.96)],
            "G": [(0.0, 0.6), (0.9, 0.6), (1.0, 0.62), (1.1, 0.64), (1.2, 0.67), (1.3, 0.7),
                  (1.4, 0.75), (1.5, 0.81), (1.6, 0.88), (1.7, 0.94), (1.8, 1.0), (1.9, 1.06),
                  (2.0, 1.12), (2.1, 1.19), (2.2, 1.26), (2.3, 1.33), (2.4, 1.4), (2.5, 1.46),
                  (2.6, 1.52), (2.8, 1.63), (3.0, 1.74), (3.2, 1.85), (3.4, 1.99), (3.6, 2.12),
                  (3.8, 2.25), (4.0, 2.37), (4.2, 2.47), (4.4, 2.56), (4.6, 2.62), (4.8, 2.68),
                  (5.0, 2.71)],
            "R": [(0.0, 0.22), (0.9, 0.23), (1.0, 0.23), (1.2, 0.27), (1.4, 0.34), (1.6, 0.44),
                  (1.8, 0.55), (2.0, 0.65), (2.2, 0.75), (2.4, 0.86), (2.6, 0.97), (2.8, 1.08),
                  (3.0, 1.2), (3.2, 1.31), (3.4, 1.41), (3.6, 1.52), (3.8, 1.61), (4.0, 1.7),
                  (4.2, 1.79), (4.4, 1.87), (4.6, 1.92), (4.8, 1.97), (5.0, 2.0)],
        },
        "grain_guides": {
            "B": [(0.0, 0.0273), (0.5, 0.0278), (1.0, 0.0293), (1.4, 0.031), (1.6, 0.0305), (1.8, 0.0281),
                  (2.0, 0.0242), (2.2, 0.0218), (2.4, 0.0197), (2.6, 0.0193), (3.0, 0.0196), (3.3, 0.0202),
                  (3.6, 0.0201), (3.8, 0.0193), (4.0, 0.0169), (4.2, 0.0152), (4.4, 0.0139), (4.6, 0.0125),
                  (4.8, 0.0112), (5.0, 0.0104)],
            "G": [(0.0, 0.0074), (0.5, 0.0075), (0.8, 0.0081), (1.0, 0.00966), (1.11, 0.011), (1.25, 0.0128),
                  (1.45, 0.0141), (1.69, 0.0116), (1.9, 0.01), (2.23, 0.0088), (2.5, 0.0077), (2.72, 0.0071),
                  (3.0, 0.0076), (3.5, 0.0083), (4.02, 0.0076), (4.58, 0.0065), (4.96, 0.0058), (5.0, 0.00575)],
            "R": [(0.0, 0.0056), (0.6, 0.0055), (0.93, 0.00653), (1.11, 0.0078), (1.34, 0.00966), (1.52, 0.0105),
                  (1.78, 0.0088), (2.0, 0.0076), (2.23, 0.007), (2.5, 0.0063), (2.7, 0.006), (3.2, 0.0064),
                  (3.5, 0.0061), (3.91, 0.00575), (4.58, 0.0052), (4.76, 0.0051), (4.96, 0.0054), (5.0, 0.00545)],
        },
        "grain_style": "dotted",
        "grain_guide_tolerance_px": 5.0,
        "on_solid": {"G": [("B", 0.95, 1.35)]},
        "identity_uncertain": {},
    },
}

SENSITOMETRY_CHARTS = {
    "kodak-vision3-250d-5207": {
        "image": (1, (664, 688)),
        "frame": (89.5, 630.5, 99.0, 639.5),  # x left, x right, y of D=3, y of D=0 (seeds)
        "stop_ticks": [(s, 89.5 + (s + 8) * 33.81) for s in range(-7, 8)],
        "log_h_ticks": [(round(-3.7 + 0.6 * i, 1), 90 + i * 67.6) for i in range(9)],
        "density_ticks": [(0.0, 639.5), (1.0, 459.5), (2.0, 279.0), (3.0, 99.0)],
        "masks": [(100, 118, 500, 200), (598, 128, 620, 150), (598, 192, 620, 215),
                  (598, 318, 620, 340), (91, 622, 629, 638)],
        "guides": {
            "B": [(-8, 0.84), (-6.5, 0.85), (-4, 0.95), (-3, 1.05), (-2, 1.25), (0, 1.62),
                  (2, 1.98), (4, 2.3), (6, 2.57), (8, 2.72)],
            "G": [(-8, 0.57), (-6, 0.6), (-4, 0.72), (-3, 0.85), (-2, 1.05), (0, 1.4),
                  (2, 1.75), (4, 2.08), (6, 2.37), (8, 2.53)],
            "R": [(-8, 0.17), (-6, 0.2), (-4, 0.3), (-3, 0.42), (-2, 0.58), (0, 0.9),
                  (2, 1.2), (4, 1.45), (6, 1.65), (8, 1.8)],
        },
    },
    "kodak-vision3-500t-5219": {
        "image": (1, (673, 732)),
        "frame": (85.0, 651.5, 101.5, 667.5),
        "stop_ticks": [(s, 85.0 + (s + 8) * 35.41) for s in range(-7, 8)],
        "log_h_ticks": [(-4.0, 85.0), (-3.0, 197.0), (-2.0, 305.5), (-1.0, 417.5), (0.0, 542.0),
                        (1.0, 651.5)],
        "density_ticks": [(0.0, 667.5), (1.0, 479.0), (2.0, 290.5), (3.0, 101.5)],
        "masks": [(100, 128, 470, 210), (618, 128, 640, 152), (618, 198, 640, 222),
                  (618, 330, 640, 352), (86, 650, 650, 666)],
        "guides": {
            "B": [(-8, 0.84), (-6.5, 0.85), (-4, 0.95), (-3, 1.05), (-2, 1.28), (0, 1.63),
                  (2, 1.98), (4, 2.3), (6, 2.57), (8, 2.72)],
            "G": [(-8, 0.58), (-6, 0.6), (-4, 0.72), (-3, 0.85), (-2, 1.07), (0, 1.42),
                  (2, 1.77), (4, 2.1), (6, 2.38), (8, 2.53)],
            "R": [(-8, 0.18), (-6, 0.21), (-4, 0.32), (-3, 0.44), (-2, 0.6), (0, 0.92),
                  (2, 1.2), (4, 1.45), (6, 1.66), (8, 1.82)],
        },
    },
}

MTF_CHART = {
    "image": (2, (525, 488)),  # third raster on page 4 (the first two are a chart and its mask)
    "freq_ticks": [(1, 78.5), (2, 123.5), (3, 150.5), (4, 169.5), (5, 183.5), (10, 229.5),
                   (20, 274.5), (50, 335.5), (100, 380.5), (200, 426.0), (600, 498.5)],
    "response_ticks": [(200, 81.5), (100, 122.5), (70, 144.5), (50, 164.5), (30, 194.5),
                       (20, 219.5), (10, 260.5), (7, 282.5), (5, 302.5), (3, 333.0), (1, 398.5)],
    "masks": [(330, 122, 350, 140), (330, 166, 350, 186), (330, 198, 350, 218)],
    "guides": {
        "G": [(2.7, 105), (5, 95), (10, 86), (20, 80), (40, 78), (60, 77), (70, 76), (80, 68)],
        "R": [(2.7, 103), (5, 94), (10, 85), (20, 78), (40, 70), (60, 62), (80, 56)],
        "B": [(2.7, 104), (5, 93), (10, 84), (20, 72), (40, 50), (60, 38), (80, 32)],
    },
    "conditions_verbatim": [
        "Exposure: Tungsten 3200 K",
        "Process: ECP-2D",
        "Densitometry: Status A",
        "35% Modulation Target",
    ],
}


# --------------------------------------------------------------------------------------------
# Image access
# --------------------------------------------------------------------------------------------
def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def page_images(pdf, page, scratch):
    """Embedded rasters of one page, in pdfimages order, as 8-bit gray arrays."""
    prefix = pathlib.Path(scratch) / f"p{page}"
    subprocess.run(
        ["pdfimages", "-png", "-f", str(page), "-l", str(page), str(pdf), str(prefix)],
        check=True,
    )
    files = sorted(pathlib.Path(scratch).glob(f"p{page}-*.png"))
    return [np.asarray(Image.open(f).convert("L"), dtype=np.float64) for f in files]


def chart_image(images, spec):
    index, size = spec["image"]
    gray = images[index]
    if (gray.shape[1], gray.shape[0]) != size:
        sys.exit(f"unexpected raster size {gray.shape[::-1]} for image {index}, expected {size}")
    return gray


# --------------------------------------------------------------------------------------------
# Axis calibration
# --------------------------------------------------------------------------------------------
def clusters(indices):
    groups = []
    for i in indices:
        if groups and i - groups[-1][-1] <= 1:
            groups[-1].append(i)
        else:
            groups.append([i])
    return [(g[0] + g[-1]) / 2.0 for g in groups]


def tick_centres_horizontal_marks(dark, column_lo, column_hi):
    """Rows where every pixel of the column band is ink: horizontal tick marks on a y axis."""
    return clusters(np.flatnonzero(dark[:, column_lo:column_hi].all(axis=1)))


def tick_centres_vertical_marks(dark, row_lo, row_hi):
    """Columns where every pixel of the row band is ink: vertical tick marks on an x axis."""
    return clusters(np.flatnonzero(dark[row_lo:row_hi, :].all(axis=0)))


def match_ticks(seeds, detected, tolerance=3.0):
    matched = []
    for value, seed in seeds:
        near = [d for d in detected if abs(d - seed) <= tolerance]
        if not near:
            sys.exit(f"tick {value} not found near pixel {seed}")
        matched.append((value, min(near, key=lambda d: abs(d - seed))))
    return matched


class Axis:
    """Linear map pixel -> value (or log10 value), least-squares fitted to matched ticks."""

    def __init__(self, name, ticks, log=False, check_ticks=()):
        self.name, self.log = name, log
        values = np.array([math.log10(v) if log else v for v, _ in ticks])
        pixels = np.array([p for _, p in ticks])
        self.slope, self.intercept = np.polyfit(pixels, values, 1)
        self.residuals = []
        for (v, p), fitted in zip(ticks + list(check_ticks), self._raw(np.array([p for _, p in ticks + list(check_ticks)]))):
            target = math.log10(v) if log else v
            self.residuals.append(
                {
                    "value": v,
                    "pixel": round(float(p), 2),
                    "used_in_fit": (v, p) in ticks,
                    "residual_units": round(float(fitted - target), 5),
                    "residual_px": round(float((fitted - target) / self.slope), 2),
                }
            )

    def _raw(self, pixel):
        return self.intercept + self.slope * pixel

    def value(self, pixel):
        raw = self._raw(np.asarray(pixel, dtype=np.float64))
        return 10.0**raw if self.log else raw

    def pixel(self, value):
        raw = np.log10(value) if self.log else np.asarray(value, dtype=np.float64)
        return (raw - self.intercept) / self.slope

    def summary(self):
        used = [r for r in self.residuals if r["used_in_fit"]]
        return {
            "axis": self.name,
            "scale": "log10" if self.log else "linear",
            "units_per_px": round(float(self.slope), 7),
            "max_abs_residual_px": round(max(abs(r["residual_px"]) for r in used), 2),
            "rms_residual_px": round(math.sqrt(sum(r["residual_px"] ** 2 for r in used) / len(used)), 2),
            "ticks": self.residuals,
        }


def frame_lines(dark):
    """Centres of the outermost long vertical and horizontal lines (the chart frame)."""
    columns = clusters(np.flatnonzero(dark.mean(axis=0) > 0.5))
    rows = clusters(np.flatnonzero(dark.mean(axis=1) > 0.5))
    return columns[0], columns[-1], rows[0], rows[-1]


# --------------------------------------------------------------------------------------------
# Curve tracing
# --------------------------------------------------------------------------------------------
def column_runs(column, lo, hi):
    ys = np.flatnonzero(column[lo:hi]) + lo
    if len(ys) == 0:
        return []
    breaks = np.flatnonzero(np.diff(ys) > 1)
    starts = np.r_[ys[0], ys[breaks + 1]]
    ends = np.r_[ys[breaks], ys[-1]]
    return list(zip(starts.tolist(), ends.tolist()))


def run_centre(gray_column, start, end):
    """Darkness-weighted centre of a run, including one anti-aliased pixel each side."""
    ys = np.arange(max(start - 1, 0), min(end + 2, len(gray_column)))
    weights = np.clip(255.0 - gray_column[ys], 0.0, None)
    return float((ys * weights).sum() / weights.sum())


def trace(gray, dark, guide_px, x_range, y_range, guide_tolerance, step_tolerance):
    """Follow one line column by column.

    guide_px: (xs, ys) pixel waypoints. A run is accepted if its centre is within
    guide_tolerance of the guide and within step_tolerance of the continuity prediction
    (linear fit to the last accepted samples within 12 columns). Returns {x: (centre, start, end)}.
    """
    gx, gy = guide_px
    samples = {}
    accepted = []
    for x in range(x_range[0], x_range[1] + 1):
        guide = float(np.interp(x, gx, gy))
        recent = [s for s in accepted[-8:] if x - s[0] <= 12]
        if len(recent) >= 3:
            xs, ys = zip(*[(s[0], s[1]) for s in recent])
            slope, intercept = np.polyfit(xs, ys, 1)
            prediction, limit = slope * x + intercept, step_tolerance
        elif recent:
            prediction, limit = recent[-1][1], step_tolerance + 1.0
        else:
            prediction, limit = guide, guide_tolerance
        best = None
        for start, end in column_runs(dark[:, x], *y_range):
            centre = run_centre(gray[:, x], start, end)
            if abs(centre - guide) > guide_tolerance:
                continue
            distance = abs(centre - prediction)
            if distance <= limit and (best is None or distance < best[0]):
                best = (distance, centre, start, end)
        if best:
            samples[x] = best[1:]
            accepted.append((x, best[1]))
    return samples


def smooth_solid(samples):
    """Drop columns whose run is much longer than its neighbours' (a crossing line merged in)."""
    xs = sorted(samples)
    lengths = np.array([samples[x][2] - samples[x][1] + 1 for x in xs], dtype=float)
    kept, merged = {}, []
    for i, x in enumerate(xs):
        window = lengths[max(0, i - 10) : i + 11]
        if lengths[i] > np.median(window) + 2.0:
            merged.append(x)
        else:
            kept[x] = samples[x]
    return kept, merged


def erase(dark, samples, margin=1):
    erased = np.zeros_like(dark)
    for x, (_, start, end) in samples.items():
        erased[max(start - margin, 0) : end + margin + 1, x] = True
    dark &= ~erased
    return erased


def touches(erased, x, start, end):
    return bool(erased[max(start - 1, 0) : end + 2, x].any())


# --------------------------------------------------------------------------------------------
# Granularity chart
# --------------------------------------------------------------------------------------------
def calibrate_granularity(gray, spec):
    dark = gray < DARK
    left, right, top, bottom = frame_lines(dark)
    b = int(round(bottom))
    x_detected = tick_centres_vertical_marks(dark, b - 6, b - 2) + [left, right]
    x_axis = Axis("log relative exposure", match_ticks(spec["x_ticks"], x_detected))
    l = int(round(left))
    d_detected = tick_centres_horizontal_marks(dark, l + 3, l + 6) + [top, bottom]
    density_axis = Axis("density", match_ticks(spec["density_ticks"], d_detected))
    edge = int(np.flatnonzero(dark.mean(axis=0) > 0.5)[-1])  # outer edge of the right frame line
    s_detected = tick_centres_horizontal_marks(dark, edge + 1, edge + 3) + [bottom]
    labelled = [(v, p) for v, p, lab in spec["sigma_ticks"] if lab]
    unlabelled = [(v, p) for v, p, lab in spec["sigma_ticks"] if not lab]
    sigma_axis = Axis(
        "granularity sigma_D",
        match_ticks(labelled, s_detected),
        log=True,
        check_ticks=match_ticks(unlabelled, s_detected),
    )
    return {"frame_px": (left, right, top, bottom), "x": x_axis, "density": density_axis, "sigma": sigma_axis}


def apply_masks(dark, masks):
    for x0, y0, x1, y1 in masks:
        dark[y0 : y1 + 1, x0 : x1 + 1] = False


def guide_pixels(guide, x_axis, y_axis):
    xs = x_axis.pixel(np.array([g[0] for g in guide]))
    ys = y_axis.pixel(np.array([g[1] for g in guide]))
    return xs, ys


def trace_granularity_chart(gray, spec, axes):
    left, right, top, bottom = axes["frame_px"]
    dark = gray < DARK
    apply_masks(dark, spec["masks"])
    x_range = (int(left) + 3, int(right) - 3)
    y_range = (int(top) + 3, int(bottom) - 2)
    solids, solid_merged, erased_all = {}, {}, np.zeros_like(dark)
    for layer in ("B", "G", "R"):
        guide = guide_pixels(spec["solid_guides"][layer], axes["x"], axes["density"])
        raw = trace(gray, dark, guide, x_range, y_range, guide_tolerance=12.0, step_tolerance=3.0)
        solids[layer], solid_merged[layer] = smooth_solid(raw)
    for layer in ("B", "G", "R"):
        erased_all |= erase(dark, solids[layer])
        # Columns where a crossing line merged: erase a band around the interpolated centre.
        xs = sorted(solids[layer])
        for x in solid_merged[layer]:
            centre = float(np.interp(x, xs, [solids[layer][k][0] for k in xs]))
            band = slice(int(math.floor(centre - 2.5)), int(math.ceil(centre + 2.5)) + 1)
            erased_all[band, x] = True
            dark[band, x] = False
    grains, crossing = {}, {}
    for layer in ("B", "G", "R"):
        guide = guide_pixels(spec["grain_guides"][layer], axes["x"], axes["sigma"])
        raw = trace(gray, dark, guide, x_range, y_range, guide_tolerance=spec["grain_guide_tolerance_px"], step_tolerance=2.5)
        grains[layer] = {x: s for x, s in raw.items() if not touches(erased_all, x, s[1], s[2])}
        crossing[layer] = sorted(set(raw) - set(grains[layer]))
    return solids, solid_merged, grains, crossing


def column_series(samples, x_axis, y_axis, log=False):
    xs = np.array(sorted(samples), dtype=float)
    ys = np.array([samples[int(x)][0] for x in xs])
    values = y_axis.value(ys)
    return x_axis.value(xs), (np.log10(values) if log else values), xs


def resample(chart_x, values, grid, window=0.03):
    """Mean of samples within +-window of each grid point; else linear interpolation.

    Returns values and the gap (chart units) to the nearest sample on each side.
    """
    out, gaps = [], []
    for g in grid:
        near = np.abs(chart_x - g) <= window
        if near.any():
            out.append(float(values[near].mean()))
            gaps.append(0.0)
            continue
        lower, upper = chart_x[chart_x < g], chart_x[chart_x > g]
        if len(lower) and len(upper):
            out.append(float(np.interp(g, chart_x, values)))
            gaps.append(float(upper.min() - lower.max()))
        else:  # beyond the last sample (the frame hides the end of the line): linear extension
            side = chart_x[np.argsort(np.abs(chart_x - g))[:8]]
            vals = values[np.argsort(np.abs(chart_x - g))[:8]]
            slope, intercept = np.polyfit(side, vals, 1)
            out.append(float(slope * g + intercept))
            gaps.append(float(np.abs(chart_x - g).min()) * 2.0)
    return np.array(out), np.array(gaps)


def build_granularity_table(stock, gray, spec, overlays):
    axes = calibrate_granularity(gray, spec)
    solids, solid_merged, grains, crossing = trace_granularity_chart(gray, spec, axes)
    grid = np.round(np.arange(0.0, 5.0 + 1e-9, GRID_STEP), 10)
    table = {"x": grid, "density": {}, "log_sigma": {}, "flags": {}}
    bridged_limit = 0.135  # chart units (~12 px): longer than any regular dash gap on these charts
    for layer in LAYERS:
        cx, density, _ = column_series(solids[layer], axes["x"], axes["density"])
        table["density"][layer], density_gap = resample(cx, density, grid)
        samples = dict(grains[layer])
        filled_from_solid = set()
        for solid_layer, x_lo, x_hi in spec["on_solid"].get(layer, []):
            px_lo, px_hi = axes["x"].pixel(x_lo), axes["x"].pixel(x_hi)
            have = sorted(samples)
            for x, sample in solids[solid_layer].items():
                if px_lo <= x <= px_hi and x not in samples:
                    near = [h for h in have if abs(h - x) <= 2]
                    if not near:
                        samples[x] = sample
                        filled_from_solid.add(x)
        gx, log_sigma, gpx = column_series(samples, axes["x"], axes["sigma"], log=True)
        table["log_sigma"][layer], gap = resample(gx, log_sigma, grid)
        flags = []
        solid_x = axes["x"].value(np.array(sorted(filled_from_solid), dtype=float)) if filled_from_solid else np.array([])
        cross_x = axes["x"].value(np.array(crossing[layer], dtype=float)) if crossing[layer] else np.array([])
        for i, g in enumerate(grid):
            f = []
            if len(solid_x) and np.any(np.abs(solid_x - g) <= 0.05):
                f.append("on_solid")
            if gap[i] > bridged_limit:
                f.append("bridged")
            if len(cross_x) and np.any(np.abs(cross_x - g) <= 0.05):
                f.append("crossing")
            if g <= 0.0 + 1e-9 or g >= 5.0 - 1e-9:
                f.append("edge")
            for lo, hi in spec["identity_uncertain"].get(layer, []):
                if lo - 1e-9 <= g <= hi + 1e-9:
                    f.append("identity_uncertain")
            if density_gap[i] > bridged_limit:
                f.append("density_bridged")
            flags.append(f)
        table["flags"][layer] = flags
        table.setdefault("samples", {})[layer] = (gx, log_sigma, cx, density)
    table["line_width_px"] = {
        layer: float(np.median([e - st + 1 for _, st, e in grains[layer].values()])) for layer in LAYERS
    }
    # Lines closer than one line width cannot be told apart on the chart: flag as shared.
    for a, b in (("G", "R"), ("B", "G"), ("B", "R")):
        width = max(table["line_width_px"][a], table["line_width_px"][b]) * abs(axes["sigma"].slope)
        close = np.abs(table["log_sigma"][a] - table["log_sigma"][b]) < width
        for i in np.flatnonzero(close):
            for x, y in ((a, b), (b, a)):
                if f"shared_with_{y}" not in table["flags"][x][i]:
                    table["flags"][x][i].append(f"shared_with_{y}")
    # Shared: G and R (or any pair) of granularity lines resolve to the same pixels.
    for a, b in (("G", "R"), ("B", "G"), ("B", "R")):
        same = [x for x in grains[a] if x in grains[b] and grains[a][x][1:] == grains[b][x][1:]]
        if same:
            sx = axes["x"].value(np.array(same, dtype=float))
            for i, g in enumerate(grid):
                share = np.sum(np.abs(sx - g) <= 0.05)
                if share >= 3:
                    table["flags"][a][i].append(f"shared_with_{b}")
                    table["flags"][b][i].append(f"shared_with_{a}")
    table["flags"] = {layer: [list(dict.fromkeys(f)) for f in flags] for layer, flags in table["flags"].items()}
    table["solid_line_width_px"] = {
        layer: float(np.median([e - st + 1 for _, st, e in solids[layer].values()])) for layer in LAYERS
    }
    if overlays:
        draw_granularity_overlay(gray, axes, spec, solids, grains, table, overlays / f"{stock}-granularity-overlay.png")
    return axes, table


# --------------------------------------------------------------------------------------------
# Sensitometric chart and the 18% gray placement
# --------------------------------------------------------------------------------------------
def build_sensitometry(stock, gray, spec, overlays):
    dark = gray < DARK
    left, right, top, bottom = frame_lines(dark)
    b = int(round(bottom))
    stop_axis = Axis("camera stops", match_ticks(spec["stop_ticks"], tick_centres_vertical_marks(dark, b - 6, b - 2)))
    t = int(round(top))
    log_h_detected = tick_centres_vertical_marks(dark, t + 2, t + 6) + [left, right]
    log_h_axis = Axis("log exposure (lux-seconds)", match_ticks(spec["log_h_ticks"], log_h_detected))
    l = int(round(left))
    density_axis = Axis(
        "density",
        match_ticks(spec["density_ticks"], tick_centres_horizontal_marks(dark, l + 2, l + 5) + [top, bottom]),
    )
    apply_masks(dark, spec["masks"])
    x_range = (int(left) + 3, int(right) - 3)
    y_range = (int(top) + 3, int(bottom) - 2)
    curves = {}
    for layer in ("B", "G", "R"):
        guide = guide_pixels(spec["guides"][layer], stop_axis, density_axis)
        raw = trace(gray, dark, guide, x_range, y_range, guide_tolerance=12.0, step_tolerance=3.0)
        curves[layer], _ = smooth_solid(raw)
    if overlays:
        draw_simple_overlay(gray, curves, overlays / f"{stock}-sensitometry-overlay.png")
    return {"stop": stop_axis, "log_h": log_h_axis, "density": density_axis, "frame_px": (left, right, top, bottom)}, curves


def fit_gray_placement(gran_axes, gran_table, sens_axes, sens_curves):
    """Find x_gray: the granularity-chart x of camera stop 0, by aligning characteristic curves.

    Sensitometric curve x is mapped to log10 exposure relative to stop 0 in two ways: through
    the stop ticks at log10(2) per stop (primary) and through the printed log-exposure axis.
    The granularity chart's curves are D(x); we minimise sum (D_sens(e) - D_gran(e + x_gray))^2
    over the overlapping range by a dense 1-D search (and a 2-D search for variants).
    """
    stop0_px = float(sens_axes["stop"].pixel(0.0))
    log_h_stop0 = float(sens_axes["log_h"].value(stop0_px))
    log_h_per_stop = float(sens_axes["log_h"].slope / sens_axes["stop"].slope)
    gx_by_layer = {}
    for layer in LAYERS:
        _, _, cx, density = gran_table["samples"][layer]
        gx_by_layer[layer] = (cx, density)

    cache = {}

    def sens_points(layer, mapping):
        if (layer, mapping) not in cache:
            cache[(layer, mapping)] = _sens_points(layer, mapping)
        return cache[(layer, mapping)]

    def _sens_points(layer, mapping):
        xs = np.array(sorted(sens_curves[layer]), dtype=float)
        d = sens_axes["density"].value(np.array([sens_curves[layer][int(x)][0] for x in xs]))
        if mapping == "stops":
            e = sens_axes["stop"].value(xs) * LOG10_2
        else:
            e = sens_axes["log_h"].value(xs) - log_h_stop0
        return e, d

    def cost(layers, mapping, shift, scale=1.0, offset=False):
        residuals = []
        for layer in layers:
            e, d = sens_points(layer, mapping)
            cx, cd = gx_by_layer[layer]
            x = shift + scale * e
            inside = (x >= cx.min()) & (x <= cx.max())
            r = d[inside] - np.interp(x[inside], cx, cd)
            if offset:
                r = r - r.mean()
            residuals.append(r)
        r = np.concatenate(residuals)
        return float(np.sqrt(np.mean(r**2))), r

    def best_shift(layers, mapping, scale=1.0, offset=False):
        centre, step = 2.5, 0.05
        shifts = np.arange(0.5, 4.5 + 1e-9, step)
        while True:
            costs = [cost(layers, mapping, s, scale, offset)[0] for s in shifts]
            i = int(np.argmin(costs))
            centre = float(shifts[i])
            if step <= 0.0005:
                return round(centre, 4), costs[i]
            step /= 10.0
            shifts = centre + np.arange(-10, 11) * step

    results = {}
    for mapping in ("stops", "printed_log_exposure_axis"):
        rows = {}
        for layers in [("R",), ("G",), ("B",), LAYERS]:
            name = "combined" if len(layers) == 3 else layers[0]
            shift, rms = best_shift(layers, mapping)
            _, r = cost(layers, mapping, shift)
            shift_o, rms_o = best_shift(layers, mapping, offset=True)
            rows[name] = {
                "x_gray": round(shift, 3),
                "rms_density_residual": round(rms, 4),
                "max_abs_density_residual": round(float(np.abs(r).max()), 4),
                "x_gray_with_free_density_offset": round(shift_o, 3),
                "rms_with_free_density_offset": round(rms_o, 4),
            }
        results[mapping] = rows
    # Free horizontal scale (and optionally a density offset) about stop 0, per layer and
    # combined: the granularity chart's curves are steeper than the sensitometric ones
    # (Kodak: "different equipment"), so a pure shift is a compromise across the curve.
    free = {}
    for layers in [("R",), ("G",), ("B",), LAYERS]:
        name = "combined" if len(layers) == 3 else layers[0]
        for offset in (False, True):
            best = None
            for scale in np.arange(0.70, 1.30 + 1e-9, 0.01):
                shift, rms = best_shift(layers, "stops", scale=scale, offset=offset)
                if best is None or rms < best[2]:
                    best = (float(scale), shift, rms)
            free[name + ("_with_density_offset" if offset else "")] = {
                "x_gray": round(best[1], 3),
                "scale_vs_log10_2_per_stop": round(best[0], 2),
                "rms_density_residual": round(best[2], 4),
            }
    results["free_scale"] = free
    # Kodak's reading instruction is by density: find the density on the characteristic curve,
    # then read sigma_D above it. Density match at stop 0: x where D_gran(x) = D_sens(stop 0).
    match = {}
    for layer in LAYERS:
        e, d = sens_points(layer, "stops")
        d0 = float(np.interp(0.0, e, d))
        cx, cd = gx_by_layer[layer]
        rising = cd > cd.min() + 0.05
        order = np.argsort(cd[rising])
        match[layer] = {
            "status_m_density_at_stop0": round(d0, 3),
            "x_gray": round(float(np.interp(d0, cd[rising][order], cx[rising][order])), 3),
        }
    results["density_match_at_stop0"] = match
    return {
        "stop0_pixel": round(stop0_px, 2),
        "printed_log_h_at_stop0": round(log_h_stop0, 3),
        "log10_exposure_per_stop_from_printed_axes": round(log_h_per_stop, 4),
        "fits": results,
    }


# --------------------------------------------------------------------------------------------
# Knot table
# --------------------------------------------------------------------------------------------
def interpolation_errors(knots, grid_e, sigma, valid):
    """Max/RMS relative error of piecewise-linear interpolation through knots vs the 0.1 grid."""
    k_sigma = np.interp(knots, grid_e, sigma)
    lin = np.interp(grid_e[valid], knots, k_sigma)
    logi = 10.0 ** np.interp(grid_e[valid], knots, np.log10(k_sigma))
    truth = sigma[valid]
    rel_lin = np.abs(lin / truth - 1.0)
    rel_log = np.abs(logi / truth - 1.0)
    return k_sigma, {
        "linear_sigma": {"max": float(rel_lin.max()), "rms": float(np.sqrt(np.mean(rel_lin**2)))},
        "linear_log_sigma": {"max": float(rel_log.max()), "rms": float(np.sqrt(np.mean(rel_log**2)))},
    }


def knot_table(table, x_gray, scale=1.0):
    """8-knot table in log_e; the chart x of log_e is x_gray + scale * log_e."""
    grid_e = (table["x"] - x_gray) / scale
    lo = max(-KNOT_TARGET, float(grid_e.min()))
    hi = min(KNOT_TARGET, float(grid_e.max()))
    valid = (grid_e >= lo - 1e-9) & (grid_e <= hi + 1e-9)
    result = {"log_e_range": [round(lo, 3), round(hi, 3)], "layers": {}}
    for count in range(4, 25):
        knots = np.linspace(lo, hi, count)
        worst = 0.0
        for layer in LAYERS:
            sigma = 10.0 ** table["log_sigma"][layer]
            _, errors = interpolation_errors(knots, grid_e, sigma, valid)
            worst = max(worst, errors["linear_sigma"]["max"])
        if worst <= 0.10:
            result["min_knots_for_10pct_max_error_linear_sigma"] = count
            break
    knots = np.linspace(lo, hi, KNOT_COUNT)
    result["log_e_knots"] = [round(float(k), 4) for k in knots]
    for layer in LAYERS:
        sigma = 10.0 ** table["log_sigma"][layer]
        k_sigma, errors = interpolation_errors(knots, grid_e, sigma, valid)
        result["layers"][layer] = {
            "sigma_d": [round(float(s), 5) for s in k_sigma],
            "interpolation_error_vs_0p1_grid": {
                k: {m: round(v, 4) for m, v in e.items()} for k, e in errors.items()
            },
        }
    return result


# --------------------------------------------------------------------------------------------
# MTF (2383)
# --------------------------------------------------------------------------------------------
def build_mtf(gray, overlays):
    dark = gray < DARK
    left, right, top, bottom = frame_lines(dark)
    # Grid lines run the full frame, so tick search uses long vertical/horizontal lines too.
    columns = clusters(np.flatnonzero(dark[int(bottom) - 6 : int(bottom) - 2, :].all(axis=0)))
    rows = clusters(np.flatnonzero(dark[:, int(left) + 2 : int(left) + 5].all(axis=1)))
    f_axis = Axis("spatial frequency (cycles/mm)", match_ticks(MTF_CHART["freq_ticks"], columns), log=True)
    m_axis = Axis("response (%)", match_ticks(MTF_CHART["response_ticks"], rows + [bottom]), log=True)
    apply_masks(dark, MTF_CHART["masks"])
    # Remove grid lines: rows/columns that are ink across most of the frame.
    grid_rows = [int(round(r)) for r in clusters(np.flatnonzero(dark.mean(axis=1) > 0.4))]
    grid_cols = [int(round(c)) for c in clusters(np.flatnonzero(dark.mean(axis=0) > 0.4))]
    curves = {}
    results = {}
    erased_dark = dark.copy()
    for r in grid_rows:
        erased_dark[r - 2 : r + 3, :] = False
    for c in grid_cols:
        erased_dark[:, c - 2 : c + 3] = False
    for layer in ("G", "R", "B"):
        guide = guide_pixels(MTF_CHART["guides"][layer], f_axis, m_axis)
        x_lo = int(f_axis.pixel(2.5))
        x_hi = int(f_axis.pixel(95))
        raw = trace(gray, erased_dark, guide, (x_lo, x_hi), (int(top) + 3, int(bottom) - 3), 8.0, 3.0)
        curves[layer] = raw
        xs = np.array(sorted(raw), dtype=float)
        ys = np.array([raw[int(x)][0] for x in xs])
        f = f_axis.value(xs)
        m = m_axis.value(ys)
        below = np.flatnonzero(m <= 50.0)
        entry = {"traced_frequency_range": [round(float(f.min()), 1), round(float(f.max()), 1)],
                 "response_at_end_percent": round(float(np.mean(m[-4:])), 1)}
        # Half the line width in response terms gives the reading band.
        half_width = 1.5 * abs(m_axis.slope)  # log10 response units
        if len(below):
            i = int(below[0])
            f50 = float(10 ** np.interp(math.log10(50.0), [math.log10(m[i]), math.log10(m[i - 1])], [math.log10(f[i]), math.log10(f[i - 1])]))
            lo_m, hi_m = 50.0 * 10**half_width, 50.0 / 10**half_width
            order = np.argsort(f)
            # Frequencies where the trace crosses 50% +- half a line width.
            f_lo = float(np.interp(-lo_m, -m[order], f[order]))
            f_hi = float(np.interp(-hi_m, -m[order], f[order]))
            entry.update({"f50_cycles_per_mm": round(f50, 1), "f50_range_from_line_width": [round(f_lo, 1), round(f_hi, 1)]})
            entry["gaussian_sigma_um"] = round(GAUSSIAN_MTF_SIGMA_FACTOR / f50 * 1000.0, 2)
            entry["gaussian_sigma_um_range"] = [round(GAUSSIAN_MTF_SIGMA_FACTOR / f_hi * 1000.0, 2), round(GAUSSIAN_MTF_SIGMA_FACTOR / f_lo * 1000.0, 2)]
        else:
            entry["f50_cycles_per_mm"] = None
            entry["note"] = f"response stays above 50% to the end of the plotted curve ({entry['traced_frequency_range'][1]} c/mm)"
            entry["f50_lower_bound_cycles_per_mm"] = entry["traced_frequency_range"][1]
            entry["gaussian_sigma_um_upper_bound"] = round(GAUSSIAN_MTF_SIGMA_FACTOR / entry["traced_frequency_range"][1] * 1000.0, 2)
        # Gaussian MTF through the last plotted point (normalised to 100% at 0 c/mm). Only a rough
        # extrapolation: the plotted curves are not Gaussian (compare B's measured f50).
        end_f, end_m = float(np.mean(f[-4:])), entry["response_at_end_percent"]
        f50_gauss = end_f * math.sqrt(math.log(2.0) / -math.log(end_m / 100.0))
        entry["f50_gaussian_through_last_point_cycles_per_mm"] = round(f50_gauss, 1)
        entry["gaussian_sigma_um_through_last_point"] = round(GAUSSIAN_MTF_SIGMA_FACTOR / f50_gauss * 1000.0, 2)
        entry["samples"] = [[round(float(a), 2), round(float(b), 1)] for a, b in zip(f[::4], m[::4])]
        results[layer] = entry
    if overlays:
        draw_simple_overlay(gray, curves, overlays / "kodak-vision-2383-mtf-overlay.png")
    return {"frequency_axis": f_axis.summary(), "response_axis": m_axis.summary()}, results


# --------------------------------------------------------------------------------------------
# Overlays (scratch only)
# --------------------------------------------------------------------------------------------
COLOURS = {"R": (230, 0, 0), "G": (0, 170, 0), "B": (0, 80, 255)}
ZOOM = 3


def base_image(gray):
    rgb = Image.fromarray(np.uint8(np.clip(gray * 0.55 + 115, 0, 255))).convert("RGB")
    return rgb.resize((rgb.width * ZOOM, rgb.height * ZOOM), Image.NEAREST)


def draw_simple_overlay(gray, curves, path):
    image = base_image(gray)
    draw = ImageDraw.Draw(image)
    for layer, samples in curves.items():
        for x, (y, *_rest) in samples.items():
            cx, cy = (x + 0.5) * ZOOM, (y + 0.5) * ZOOM
            draw.point((cx, cy), fill=COLOURS[layer])
            draw.point((cx, cy + 1), fill=COLOURS[layer])
    image.save(path)


def draw_granularity_overlay(gray, axes, spec, solids, grains, table, path):
    image = base_image(gray)
    draw = ImageDraw.Draw(image)
    for layer in LAYERS:
        colour = COLOURS[layer]
        faint = tuple(int(c * 0.35 + 255 * 0.65) for c in colour)
        for guides, y_axis in ((spec["solid_guides"], axes["density"]), (spec["grain_guides"], axes["sigma"])):
            gx, gy = guide_pixels(guides[layer], axes["x"], y_axis)
            draw.line([((a + 0.5) * ZOOM, (b + 0.5) * ZOOM) for a, b in zip(gx, gy)], fill=faint)
        for x, (y, *_rest) in solids[layer].items():
            draw.point(((x + 0.5) * ZOOM, (y + 0.5) * ZOOM), fill=colour)
        for x, (y, *_rest) in grains[layer].items():
            draw.point(((x + 0.5) * ZOOM, (y + 0.5) * ZOOM), fill=colour)
            draw.point(((x + 0.5) * ZOOM, (y + 0.5) * ZOOM + 1), fill=colour)
        gx = axes["x"].pixel(table["x"])
        gy = axes["sigma"].pixel(10.0 ** table["log_sigma"][layer])
        dy = axes["density"].pixel(table["density"][layer])
        for i, (px, py, pd) in enumerate(zip(gx, gy, dy)):
            flags = table["flags"][layer][i]
            ring = (255, 0, 255) if any(f.startswith("shared") or f == "identity_uncertain" for f in flags) else (
                (255, 140, 0) if flags else colour)
            r = 4 if flags else 3
            cx, cy = (px + 0.5) * ZOOM, (py + 0.5) * ZOOM
            draw.ellipse((cx - r, cy - r, cx + r, cy + r), outline=ring)
            cx, cy = (px + 0.5) * ZOOM, (pd + 0.5) * ZOOM
            draw.rectangle((cx - 2, cy - 2, cx + 2, cy + 2), outline=colour)
    image.save(path)


# --------------------------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------------------------
def write_csv(path, table):
    with open(path, "w", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow([
            "log_relative_exposure", "sigma_d_red", "sigma_d_green", "sigma_d_blue",
            "density_red", "density_green", "density_blue", "flags",
        ])
        for i, x in enumerate(table["x"]):
            flags = ";".join(
                f"{layer}:{f}" for layer in LAYERS for f in table["flags"][layer][i]
            )
            writer.writerow(
                [f"{x:.1f}"]
                + [f"{10.0 ** table['log_sigma'][layer][i]:.5f}" for layer in LAYERS]
                + [f"{table['density'][layer][i]:.3f}" for layer in LAYERS]
                + [flags]
            )


def sigma_at_stops(table, x_gray, stops, scale=1.0):
    out = {}
    for layer in LAYERS:
        values = {}
        for s in stops:
            x = x_gray + scale * s * LOG10_2
            if table["x"][0] - 1e-9 <= x <= table["x"][-1] + 1e-9:
                values[str(s)] = round(float(10 ** np.interp(x, table["x"], table["log_sigma"][layer])), 5)
            else:
                values[str(s)] = None
        out[layer] = values
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--pdf-dir", required=True, type=pathlib.Path)
    parser.add_argument("--out", required=True, type=pathlib.Path)
    parser.add_argument("--overlays", type=pathlib.Path)
    args = parser.parse_args()
    if args.overlays:
        args.overlays.mkdir(parents=True, exist_ok=True)
    if shutil.which("pdfimages") is None:
        sys.exit("pdfimages (poppler) not found on PATH")
    report = {
        "tool": "Tools/grain-reference/granularity/digitize_granularity.py",
        "grid_step": GRID_STEP,
        "conventions": {
            "log_e": "log10 exposure relative to an 18% gray card at normal exposure (camera stop 0): log_e = x - x_gray",
            "sigma_d": "diffuse rms granularity sigma_D at Kodak's 48 um aperture (multiply by 1000 for Kodak's rms value)",
            "stop": f"one camera stop = log10(2) = {LOG10_2:.5f} in log_e",
        },
        "stocks": {},
    }
    with tempfile.TemporaryDirectory() as scratch:
        for stock in GRANULARITY_CHARTS:
            source = SOURCES[stock]
            pdf = args.pdf_dir / source["pdf"]
            digest = sha256_of(pdf)
            if digest != source["sha256"]:
                sys.exit(f"{pdf}: SHA-256 {digest} does not match the pinned {source['sha256']}")
            page_dir = pathlib.Path(scratch) / stock
            page_dir.mkdir()
            images = page_images(pdf, source["page"], page_dir)
            gran_gray = chart_image(images, GRANULARITY_CHARTS[stock])
            axes, table = build_granularity_table(stock, gran_gray, GRANULARITY_CHARTS[stock], args.overlays)
            write_csv(args.out / f"{stock}.granularity.csv", table)
            sens_gray = chart_image(images, SENSITOMETRY_CHARTS[stock])
            sens_axes, sens_curves = build_sensitometry(stock, sens_gray, SENSITOMETRY_CHARTS[stock], args.overlays)
            placement = fit_gray_placement(axes, table, sens_axes, sens_curves)
            report["stocks"][stock] = {
                "source": {
                    "file": source["pdf"],
                    "sha256": digest,
                    "publication": source["publication"],
                    "revision_as_printed": source["revision_as_printed"],
                    "page": source["page"],
                    "charts": "'Diffuse rms Granularity Curves' and 'Sensitometric Curves' (embedded rasters)",
                    "aperture_statement": APERTURE_STATEMENT,
                    "equipment_note": EQUIPMENT_NOTE,
                },
                "axes": {
                    "granularity_chart": [axes[k].summary() for k in ("x", "density", "sigma")],
                    "sensitometric_chart": [sens_axes[k].summary() for k in ("stop", "log_h", "density")],
                },
                "gray_placement": placement,
                "_table": table,
                "_axes": axes,
            }
        mtf_source = SOURCES["kodak-vision-2383"]
        pdf = args.pdf_dir / mtf_source["pdf"]
        digest = sha256_of(pdf)
        if digest != mtf_source["sha256"]:
            sys.exit(f"{pdf}: SHA-256 {digest} does not match the pinned {mtf_source['sha256']}")
        page_dir = pathlib.Path(scratch) / "2383"
        page_dir.mkdir()
        images = page_images(pdf, mtf_source["page"], page_dir)
        mtf_axes, mtf = build_mtf(chart_image(images, MTF_CHART), args.overlays)
    report["kodak-vision-2383-mtf"] = {
        "source": {k: v for k, v in mtf_source.items() if k != "pdf"} | {"file": mtf_source["pdf"], "chart": "'Modulation-Transfer Function Curves' (embedded raster)"},
        "conditions_verbatim": MTF_CHART["conditions_verbatim"],
        "axes": mtf_axes,
        "layers": mtf,
    }
    return report, args


def interpolation_error_profile(knots, values, grid_e, sigma):
    """Relative error of piecewise-linear interpolation through (knots, values) at the grid points."""
    return np.abs(np.interp(grid_e, knots, values) / sigma - 1.0)


def minimax_values(knots, grid_e, sigma, iterations=400):
    """Knot values minimising the maximum relative error (Lawson's iteratively reweighted LS)."""
    basis = np.stack([np.interp(grid_e, knots, np.eye(len(knots))[k]) for k in range(len(knots))], axis=1)
    a = basis / sigma[:, None]  # relative-error design: a @ v - 1
    weights = np.full(len(grid_e), 1.0 / len(grid_e))
    best_values, best_error = np.interp(knots, grid_e, sigma), np.inf
    for _ in range(iterations):
        w = np.sqrt(weights)
        values = np.linalg.lstsq(a * w[:, None], w, rcond=None)[0]
        residual = np.abs(a @ values - 1.0)
        if residual.max() < best_error:
            best_values, best_error = values, residual.max()
        weights = weights * residual
        total = weights.sum()
        if total <= 0:
            break
        weights /= total
    return best_values


def shared_knot_search(grid_e, sigmas, count, lo, hi, step=0.01):
    """Deterministic search for interior knot positions shared by all layers.

    Objective: max over layers and grid points of the relative error of piecewise-linear
    interpolation through the trace values at the knots. Coordinate descent on a 0.01 grid
    from the uniform layout and 24 fixed-seed random layouts; the best result wins.
    """
    candidates = np.round(np.arange(lo + step, hi - step / 2, step), 6)

    def objective(interior):
        knots = np.r_[lo, np.sort(interior), hi]
        if np.any(np.diff(knots) < 2 * step):
            return np.inf
        return max(interpolation_error_profile(knots, np.interp(knots, grid_e, s), grid_e, s).max() for s in sigmas)

    rng = np.random.default_rng(20261112)
    starts = [np.linspace(lo, hi, count)[1:-1]]
    starts += [np.sort(rng.choice(candidates, count - 2, replace=False)) for _ in range(24)]
    best = (np.inf, None)
    for start in starts:
        interior = np.round(np.array(start, dtype=float) / step) * step
        current = objective(interior)
        improved = True
        while improved:
            improved = False
            for k in range(len(interior)):
                for c in candidates:
                    trial = interior.copy()
                    trial[k] = c
                    value = objective(trial)
                    if value < current - 1e-12:
                        interior, current, improved = np.sort(trial), value, True
        if current < best[0] - 1e-12:
            best = (current, interior)
    return np.r_[lo, best[1], hi]


def engine_table(table, x_gray, scale):
    """Shared non-uniform knots (same log_e positions for R, G, B) for the engine's 8-value rows."""
    grid_e = (table["x"] - x_gray) / scale
    lo = max(-KNOT_TARGET, float(grid_e.min()))
    hi = min(KNOT_TARGET, float(grid_e.max()))
    inside = (grid_e >= lo - 1e-9) & (grid_e <= hi + 1e-9)
    # Grid samples inside the range plus the trace at the range ends.
    e_eval = np.r_[lo, grid_e[inside], hi]
    sigmas = {layer: 10.0 ** np.interp(e_eval, grid_e, table["log_sigma"][layer]) for layer in LAYERS}
    names = {"R": "red", "G": "green", "B": "blue"}
    result = {
        "mapping": f"primary (density-matched): granularity chart x = {x_gray} + {scale} * log_exposure",
        "log_exposure": "log10 exposure relative to an 18% gray card at normal exposure (camera stop 0); the engine clamps outside the end knots",
        "x_gray": x_gray,
        "scale": scale,
        "aperture": "sigma_D at Kodak's 48 um microdensitometer aperture",
        "error_reference": "relative error of piecewise-linear interpolation of sigma_D at the 0.1-step chart grid points inside the knot range (and the two end points)",
    }
    by_count = {}
    for count in (8, 9, 10):
        knots = shared_knot_search(e_eval, [sigmas[l] for l in LAYERS], count, lo, hi)
        entry = {"log_exposure_knots": [round(float(k), 3) for k in knots]}
        for mode in ("trace_values", "minimax_values"):
            values, errors = {}, {}
            for layer in LAYERS:
                trace = np.interp(knots, e_eval, sigmas[layer])
                v = trace if mode == "trace_values" else minimax_values(knots, e_eval, sigmas[layer])
                err = interpolation_error_profile(knots, v, e_eval, sigmas[layer])
                values[names[layer]] = [round(float(x), 5) for x in v]
                errors[names[layer]] = {
                    "max": round(float(err.max()), 4),
                    "rms": round(float(np.sqrt(np.mean(err**2))), 4),
                    "max_at_log_exposure": round(float(e_eval[int(np.argmax(err))]), 3),
                }
            entry[mode] = {"sigma_d_48um": values, "relative_error": errors,
                           "max_over_layers": max(e["max"] for e in errors.values())}
        by_count[str(count)] = entry
    eight = by_count["8"]
    chosen = "minimax_values" if eight["minimax_values"]["max_over_layers"] < eight["trace_values"]["max_over_layers"] else "trace_values"
    result["log_exposure_knots"] = eight["log_exposure_knots"]
    result["sigma_d_48um"] = eight[chosen]["sigma_d_48um"]
    result["values_are"] = chosen
    result["relative_error"] = eight[chosen]["relative_error"]
    result["meets_10pct_max"] = eight[chosen]["max_over_layers"] <= 0.10
    result["knot_search"] = (
        "end knots fixed at the range ends; 6 interior positions shared by all layers, chosen by "
        "coordinate descent on a 0.01 log_e grid (uniform start + 24 fixed-seed random starts) "
        "minimising the max relative error over the three layers with trace values at the knots; "
        "minimax_values then re-fits the 8 values per layer (Lawson IRLS) for those positions"
    )
    result["by_knot_count"] = by_count
    return result


def choose_gray(placement):
    """Primary x_gray: free horizontal scale and free density offset, all layers combined.

    Uncertainty: the largest departure of the other offset-aware fits (per-layer free-scale fits
    and the combined pure-shift fit) from it.
    """
    fits = placement["fits"]
    free = fits["free_scale"]
    primary = free["combined_with_density_offset"]
    others = [free[f"{layer}_with_density_offset"]["x_gray"] for layer in LAYERS]
    others.append(fits["stops"]["combined"]["x_gray_with_free_density_offset"])
    spread = max(abs(v - primary["x_gray"]) for v in others)
    return primary["x_gray"], round(max(spread, 0.02), 3), primary["scale_vs_log10_2_per_stop"]


def reading_uncertainty(stock_axes, table):
    sigma_slope = abs(stock_axes["sigma"].slope)  # log10 sigma per px
    out = {}
    for layer in LAYERS:
        half = table["line_width_px"][layer] / 2.0
        out[layer] = {
            "granularity_line_width_px": table["line_width_px"][layer],
            "half_width_log10_sigma": round(half * sigma_slope, 4),
            "half_width_relative": round(10 ** (half * sigma_slope) - 1.0, 3),
        }
    out["sigma_axis_calibration_rms_px"] = stock_axes["sigma"].summary()["rms_residual_px"]
    out["px_per_decade_sigma"] = round(1.0 / sigma_slope, 1)
    out["notes"] = [
        "Values are darkness-weighted centres of the printed line; the half line width bounds where inside the line the true curve lies.",
        "on_solid: the granularity line is hidden under a characteristic curve and takes that curve's centre (+- one line width).",
        "shared_with_X: two granularity lines print as one; both layers get the same value.",
        "identity_uncertain: two separate lines whose layer assignment cannot be read from the chart (assigned by keeping G above R, as on the labelled right-hand side).",
        "bridged: gap longer than a normal dash gap, filled by linear interpolation; crossing: samples dropped where another line crosses.",
        "edge: the frame line hides the last pixels; value extended linearly from the nearest samples.",
    ]
    return out


def finish(report, args):
    for stock, entry in report["stocks"].items():
        table = entry.pop("_table")
        axes = entry.pop("_axes")
        x_gray, x_gray_unc, scale = choose_gray(entry["gray_placement"])
        entry["x_gray"] = x_gray
        entry["x_gray_uncertainty"] = x_gray_unc
        entry["x_gray_method"] = (
            "least-squares alignment of the granularity chart's three characteristic curves with the "
            "sensitometric chart's curves (stop axis at log10(2) per stop), free horizontal scale and "
            "free density offset, layers combined; see gray_placement.fits for every variant"
        )
        entry["granularity_chart_x_per_log10_exposure_from_fit"] = scale
        entry["mapping"] = {
            "primary": f"density-matched: chart x = x_gray + {scale} * log_e",
            "primary_reason": (
                "Kodak's reading procedure is by density (density -> characteristic curve on the "
                "granularity chart -> sigma_D), and the sensitometric chart's camera-stop axis is the "
                "trustworthy exposure axis; the granularity chart's characteristic curves only match it "
                f"with the stop spacing scaled by {scale} (plus a density offset, which does not enter "
                "the x mapping)"
            ),
            "alternative": "unit scale: chart x = x_gray + log_e (granularity chart x taken as true log10 exposure)",
        }
        entry["knots_uniform_primary_density_matched"] = knot_table(table, x_gray, scale)
        entry["knots_uniform_alternative_unit_scale"] = knot_table(table, x_gray)
        stops = [-4, -2, 0, 2, 4]
        entry["sigma_d_at_camera_stops"] = sigma_at_stops(table, x_gray, stops, scale)
        entry["sigma_d_at_camera_stops_alternative_unit_scale"] = sigma_at_stops(table, x_gray, stops)
        entry["engine_table"] = engine_table(table, x_gray, scale)
        entry["reading_uncertainty"] = reading_uncertainty(axes, table)
        spans = {}
        for layer in LAYERS:
            flagged = {}
            for x, flags in zip(table["x"], table["flags"][layer]):
                for f in flags:
                    flagged.setdefault(f, []).append(round(float(x), 1))
            spans[layer] = flagged
        entry["flagged_grid_points"] = spans
    path = args.out / "granularity.json"
    with open(path, "w") as handle:
        json.dump(report, handle, indent=2, sort_keys=False)
        handle.write("\n")


if __name__ == "__main__":
    report, args = main()
    finish(report, args)
