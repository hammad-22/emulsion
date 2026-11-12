"""Digitize film datasheet charts (characteristic curves, spectral sensitivity, dye density).

Offline helper, never shipped. Reads the publisher's PDFs, extracts the embedded chart rasters
with poppler's `pdfimages`, calibrates each chart's axes from its tick marks, follows every
curve's centreline, and writes fixed-grid CSVs plus a provenance manifest per stock.
All chart-specific choices (tick guesses, masks, seed points) live in `charts.json`.

The traced CSVs are not published in the repository (docs/DECISIONS.md, 12 Nov 2026): write them
to the local reference-data folder (~/Documents/Emulsion Research/datasheet-tracings, or wherever
EMULSION_REFERENCE_DATA points). The manifests, which pin each CSV by its SHA-256, are committed;
`--manifests` writes them there too.

    python3 -m venv venv && venv/bin/pip install -r Tools/stock-digitizing/requirements.txt
    venv/bin/python -I Tools/stock-digitizing/digitize.py --pdf-dir <dir with the PDFs> \
        --out ~/"Documents/Emulsion Research/datasheet-tracings" \
        --manifests Packages/EmulsionCore/Sources/EmulsionFit/Resources/StockData \
        [--overlays <dir>] [--traces <dir>] [--only <stock id>]

The output is deterministic: two runs give byte-identical CSVs and manifests.
"""

import argparse
import csv
import hashlib
import io
import json
import pathlib
import re
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw
from scipy.interpolate import PchipInterpolator
from scipy.ndimage import map_coordinates

CONFIG = pathlib.Path(__file__).with_name("charts.json")
TRACINGS_NOTE = (
    "Not published in this repository. Re-trace them from the public datasheet PDF with Tools/stock-digitizing/digitize.py; "
    "each chart's sha256 is the digest of the CSV this manifest describes."
)
INK = 0.3  # darkness (0 white … 1 black) above which a pixel counts as line ink
PROFILE_STEP = 0.25  # px between samples across the line
SMOOTHING = np.array([1, 4, 6, 4, 1]) / 16  # binomial filter along the trace, sigma = 1 px
OVERLAY_SCALE = 3
END_TOLERANCE = 3.0  # px: a trace must pass this close to each configured waypoint
WAYPOINT_MISS = 15.0  # px: moving this far back out from a waypoint's closest approach means it was missed
CORNER_PROBES = (4.0, 6.0, 8.0)  # px from the last measured point at which a sharp corner's new heading is probed
# Per-point trace flags.
COASTED = 0  # hidden (gap, crossing, frame): bridged by interpolation
MEASURED = 1  # centre of the drawn line, measured across it
CORNER = 2  # apex of a sharp corner hidden by a grid line: where the two measured arms meet
SHARED = 3  # one drawn line that several curves run along; they cannot be told apart there
ON_AXIS = 4  # curve lying on the axis line: read from its upper edge (edge + half the line width)
VERTEX_SLOPE = 2.0  # |dy/dx| both arms must exceed for an extreme to count as a drawn vertex
VERTEX_REACH = 3  # trace points either side of a vertex replaced by the arms' lines (~3 px)
VERTEX_ARM = 10  # trace points either side used to fit each arm
VERTEX_MIN_REACH = 1.5  # px the tip must lie beyond the traced extreme to call it a hidden vertex
FRAME_REACH = 6  # px: a curve lost this close to the frame, and heading into it, is continued straight to it
FRAME_COAST = 20  # px: the longest such straight continuation (steep curves meet the frame at a slant)


class TraceError(RuntimeError):
    pass


# MARK: - Source


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def extract_images(pdf, directory):
    subprocess.run(["pdfimages", "-png", str(pdf), str(directory / "img")], check=True)
    return {int(p.stem.split("-")[1]): p for p in directory.glob("img-*.png")}


def check_revision(pdf, expected):
    text = subprocess.run(["pdftotext", str(pdf), "-"], check=True, capture_output=True, text=True).stdout
    if expected not in " ".join(text.split()):
        raise SystemExit(f"{pdf.name}: revision text {expected!r} not found")


def poppler_version():
    """Version of poppler's pdfimages, which wrote the PNGs that imageSHA256 hashes."""
    banner = subprocess.run(["pdfimages", "-v"], capture_output=True, text=True)
    return re.search(r"version (\S+)", banner.stdout + banner.stderr).group(1)


def darkness(png):
    return 1 - np.asarray(Image.open(png).convert("L"), float) / 255


# MARK: - Axis calibration


def refine_frame(dark, approx):
    """Sub-pixel centre of each frame line, from the mean darkness profile near the guess."""
    left, top, right, bottom = approx
    rows = slice(top + (bottom - top) // 5, bottom - (bottom - top) // 5)
    cols = slice(left + (right - left) // 5, right - (right - left) // 5)

    def centre(profile, guess):
        window = np.arange(guess - 3, guess + 4)
        weights = np.clip(profile[window] - 0.5, 0, None)
        return float((window * weights).sum() / weights.sum())

    return [
        centre(dark[rows].mean(0), left),
        centre(dark[:, cols].mean(1), top),
        centre(dark[rows].mean(0), right),
        centre(dark[:, cols].mean(1), bottom),
    ]


def tick_profile(dark, frame, side, strip):
    """Darkness along an axis, keeping only features that cross the whole strip (ticks, grid)."""
    near, far = strip
    left, top, right, bottom = (round(v) for v in frame)
    band = {
        "top": lambda: dark[top + near : top + far + 1, :],
        "bottom": lambda: dark[bottom - far : bottom - near + 1, :],
        "left": lambda: dark[:, left + near : left + far + 1].T,
        "right": lambda: dark[:, right - far : right - near + 1].T,
    }[side]()
    return band.min(0)


def locate_tick(profile, guess, max_width):
    window = np.arange(round(guess) - 5, round(guess) + 6)
    values = profile[window]
    peak = int(values.argmax())
    if values[peak] < 0.5:
        return None, "no tick found"
    lo = peak
    while lo > 0 and values[lo - 1] > values[peak] / 2:
        lo -= 1
    hi = peak
    while hi < len(values) - 1 and values[hi + 1] > values[peak] / 2:
        hi += 1
    if hi - lo + 1 > max_width:
        return None, f"obscured (feature {hi - lo + 1} px wide)"
    span = window[lo : hi + 1]
    weights = values[lo : hi + 1]
    return float((span * weights).sum() / weights.sum()), None


def calibrate(dark, frame, spec):
    profile = tick_profile(dark, frame, spec["side"], spec["strip"])
    anchors, excluded = [], []
    for guess, value in spec["ticks"]:
        pixel, problem = locate_tick(profile, guess, spec.get("maxTickWidth", 5))
        if problem:
            excluded.append(f"tick {value} near px {guess}: {problem}")
        else:
            anchors.append((pixel, value))
    pixels, values = np.array(anchors).T
    slope, offset = np.polyfit(values, pixels, 1)
    residuals = pixels - (offset + slope * values)
    return {
        "anchors": anchors,
        "slope": slope,
        "offset": offset,
        "residualRMS": float(np.sqrt((residuals**2).mean())),
        "residualMax": float(np.abs(residuals).max()),
        "residuals": residuals.tolist(),
        "excluded": excluded,
    }


def to_data(calibration, pixels):
    return (np.asarray(pixels) - calibration["offset"]) / calibration["slope"]


def to_pixels(calibration, values):
    return calibration["offset"] + calibration["slope"] * np.asarray(values)


# MARK: - Curve following


def erase(dark, chart, frame, x_cal, y_cal):
    """Remove everything that is not a curve.

    The frame, tick marks and configured text boxes become unknown (NaN): a line profile that
    touches them is not trusted, since part of the line may be hidden. Grid lines, which curves
    cross at an angle, are simply blanked so the tracer coasts over them.
    """
    cleaned = dark.copy()
    left, top, right, bottom = frame
    pad = chart.get("frameHalfWidth", 2.0)
    for v in (left, right):
        cleaned[:, max(0, round(v - pad)) : round(v + pad) + 1] = np.nan
    for v in (top, bottom):
        cleaned[max(0, round(v - pad)) : round(v + pad) + 1, :] = np.nan
    half = chart.get("tickHalfWidth", 1.5)
    for axis, cal in (("xAxis", x_cal), ("yAxis", y_cal)):
        spec = chart[axis]
        depth = spec["strip"][1] + 2
        for _, value in spec["ticks"]:
            c = float(to_pixels(cal, value))
            across = slice(max(0, round(c - half)), round(c + half) + 1)
            if chart.get("grid"):
                along, fill = slice(None), 0.0
            elif spec["side"] in ("top", "left"):
                along, fill = slice(round(frame[1 if spec["side"] == "top" else 0]), round(frame[1 if spec["side"] == "top" else 0] + depth)), np.nan
            else:
                edge = frame[3 if spec["side"] == "bottom" else 2]
                along, fill = slice(round(edge - depth), round(edge) + 1), np.nan
            if spec["side"] in ("top", "bottom"):
                cleaned[along, across] = fill
            else:
                cleaned[across, along] = fill
    for x0, y0, x1, y1 in chart.get("masks", []):
        cleaned[y0 : y1 + 1, x0 : x1 + 1] = np.nan
    return cleaned


def cross_section(dark, point, direction, radius):
    """The ink run across `direction` nearest `point`: (offset, width) in px, or None if there is no ink."""
    normal = np.array([-direction[1], direction[0]])
    t = np.arange(-radius, radius + PROFILE_STEP / 2, PROFILE_STEP)
    xs, ys = point[0] + normal[0] * t, point[1] + normal[1] * t
    values = map_coordinates(dark, [ys, xs], order=1, mode="constant")
    unknown = np.isnan(values)
    values[unknown] = 0
    runs = runs_of(values > INK, True)
    if not runs:
        return None
    lo, hi = min(runs, key=lambda r: 0 if t[r[0]] <= 0 <= t[r[1] - 1] else min(abs(t[r[0]]), abs(t[r[1] - 1])))
    weights = values[lo:hi]
    width = float(weights.sum() * PROFILE_STEP)
    margin = int(1 / PROFILE_STEP)
    if lo == 0 or hi == len(t) or unknown[max(0, lo - margin) : hi + margin].any():
        width = np.inf  # cut off by the search window or by an erased area: its centre is unreliable
    return float((t[lo:hi] * weights).sum() / weights.sum()), width


def clean_line(found, max_width, max_lateral):
    return found is not None and found[1] <= max_width and abs(found[0]) <= max_lateral


def line_direction(dark, point, heading, settings):
    """The line's local direction at a seed: the angle across which it looks narrowest, signed along `heading`."""
    best = None
    for degrees in range(0, 180, 3):
        angle = np.radians(degrees)
        direction = np.array([np.cos(angle), np.sin(angle)])
        found = cross_section(dark, point, direction, settings["radius"])
        if clean_line(found, settings["maxWidth"], settings["maxLateral"]) and (best is None or found[1] < best[0]):
            best = (found[1], direction)
    if best is None:
        raise TraceError(f"no line at seed {point.tolist()}")
    return best[1] if best[1] @ heading >= 0 else -best[1]


def rotate(vector, degrees):
    c, s = np.cos(np.radians(degrees)), np.sin(np.radians(degrees))
    return np.array([c * vector[0] - s * vector[1], s * vector[0] + c * vector[1]])


def turn_search(dark, origin, direction, settings, traced):
    """Find where a line went after a sharp corner: probe a fan of headings from the last measured point.

    A hit on the stretch just traced (the line doubling back on itself) does not count.
    """
    recent = np.array(traced[-40:])
    for distance in CORNER_PROBES:
        for degrees in sorted(range(-120, 121, 10), key=abs)[1:]:
            heading = rotate(direction, degrees)
            probe = origin + heading * distance
            found = cross_section(dark, probe, heading, settings["radius"])
            if clean_line(found, settings["maxWidth"], settings["maxLateral"]):
                hit = probe + np.array([-heading[1], heading[0]]) * found[0]
                if np.min(np.linalg.norm(recent - hit, axis=1)) > CORNER_PROBES[0] - 1:
                    return hit, heading, found[1]
    return None


def trace_segment(dark, waypoints, box, settings, free_end=False, heading=None):
    """Follow a line through `waypoints`, one px per step; with `free_end`, carry on past the last one.

    The trace must pass within END_TOLERANCE of each waypoint; moving WAYPOINT_MISS px away again
    without having come that close is an error, which catches a swap onto another curve at a crossing. Steps where the cross-section is unclear (crossing, grid line, dash gap)
    coast straight on and are flagged unmeasured. If the line simply vanishes ahead, it may have
    turned a sharp corner (a peak drawn as a vertex): a fan search from the last measured point
    picks it up again. Losing the line for more than `maxGap` steps is an error between waypoints;
    past them (`free_end`) it is the curve's end, and the trace stops at the last measured point.
    A single waypoint with a `heading` starts a free trace straight away.
    """
    waypoints = [np.array(w, float) for w in waypoints]
    leg, closest = 0, np.inf
    free = len(waypoints) == 1
    if not free:
        heading = waypoints[1] - waypoints[0]
    direction = line_direction(dark, waypoints[0], heading, settings)
    snapped = cross_section(dark, waypoints[0], direction, settings["radius"])
    point = waypoints[0] + np.array([-direction[1], direction[0]]) * snapped[0]
    points, measured, widths, coasting, settled = [point], [MEASURED], [snapped[1]], 0, 0

    def lost(candidate):
        return TraceError(f"lost the line near {candidate.round(1).tolist()} heading to {waypoints[leg + 1].tolist()}")

    while True:
        candidate = point + direction
        if not (box[0] < candidate[0] < box[2] and box[1] < candidate[1] < box[3]):
            if hidden_by_frame(points[-1 - coasting], direction, box):
                points.append(point + direction * edge_distance(point, direction, box))
                measured.append(COASTED)
            elif not free:
                raise lost(candidate)
            else:  # a free end that stopped short of the frame
                del points[len(points) - coasting :], measured[len(measured) - coasting :]
            break
        if not free:
            distance = np.linalg.norm(point - waypoints[leg + 1])
            closest = min(closest, distance)
            if distance > closest + 1 and closest <= END_TOLERANCE:  # passed the waypoint
                leg, closest = leg + 1, np.inf
                if leg + 1 == len(waypoints):
                    if not free_end:
                        break
                    free = True
            elif distance > closest + WAYPOINT_MISS:
                raise TraceError(f"trace passed {waypoints[leg + 1].tolist()} at {closest:.1f} px, near {point.round(1).tolist()}")
        # Once a lost line is running into the frame, coast to it rather than search for it.
        entering_frame = coasting > 0 and hidden_by_frame(points[-1 - coasting], direction, box)
        # After a gap the line may have bent away from the straight prediction: widen the search.
        found = None if entering_frame else cross_section(dark, candidate, direction, settings["radius"] + coasting)
        if clean_line(found, settings["maxWidth"], settings["maxLateral"] + 0.5 * coasting):
            coasting = 0
            candidate = candidate + np.array([-direction[1], direction[0]]) * found[0]
            widths.append(found[1])
        else:
            blob = found is not None and found[1] > settings["maxWidth"]  # a crossing: coast through it
            entering_frame = entering_frame or hidden_by_frame(points[-1 - coasting], direction, box)
            turned = None if blob or entering_frame else turn_search(dark, points[-1 - coasting], direction, settings, points[: len(points) - coasting - 1] or points[:1])
            if turned:
                del points[len(points) - coasting :], measured[len(measured) - coasting :]
                corner = apex(points[-1], direction, turned[0], turned[1])
                if corner is not None:
                    points.append(corner)
                    measured.append(CORNER)
                candidate, direction, width = turned
                widths.append(width)
                coasting, settled = 0, 0  # the old heading no longer applies after the corner
            else:
                coasting += 1
                if coasting > settings["maxGap"] and not hidden_by_frame(points[-coasting], direction, box):
                    if not free:
                        raise lost(candidate)
                    del points[len(points) - coasting + 1 :], measured[len(measured) - coasting + 1 :]
                    break
        points.append(candidate)
        measured.append(MEASURED if coasting == 0 else COASTED)
        point = candidate
        settled += 1
        if coasting == 0 and settled > settings["memory"] and all(m == MEASURED for m in measured[-settings["memory"] - 1 :]):
            chord = points[-1] - points[-1 - settings["memory"]]
            direction = chord / np.linalg.norm(chord)
    return np.array(points), np.array(measured), widths


def apex(before, incoming, after, outgoing):
    """Where the straight arms into and out of a sharp corner meet, if that is within a few px."""
    matrix = np.column_stack([incoming, -outgoing])
    if abs(np.linalg.det(matrix)) < 0.1:
        return None
    along_in, back_out = np.linalg.solve(matrix, after - before)
    if 0 < along_in < CORNER_PROBES[-1] and 0 < back_out < CORNER_PROBES[-1]:
        return before + incoming * along_in
    return None


def hidden_by_frame(last_measured, direction, box):
    """Whether a line lost at `last_measured` is running into the frame, which hides its last pixels."""
    to_frame = min(last_measured[0] - box[0], box[2] - last_measured[0], last_measured[1] - box[1], box[3] - last_measured[1])
    return to_frame <= FRAME_REACH and edge_distance(last_measured, direction, box) <= FRAME_COAST


def edge_distance(point, direction, box):
    """Distance along `direction` from `point` (inside `box`) to the box edge."""
    limits = []
    for axis, (lo, hi) in enumerate(((box[0], box[2]), (box[1], box[3]))):
        if direction[axis] > 1e-9:
            limits.append((hi - point[axis]) / direction[axis])
        elif direction[axis] < -1e-9:
            limits.append((lo - point[axis]) / direction[axis])
    return min(limits)


def smooth(points, measured):
    out = points.copy()
    for lo, hi in runs_of(measured == MEASURED, True) + runs_of(measured == SHARED, True):
        if hi - lo >= len(SMOOTHING):
            for axis in range(2):
                padded = np.pad(points[lo:hi, axis], 2, mode="reflect", reflect_type="odd")
                out[lo:hi, axis] = np.convolve(padded, SMOOTHING, mode="valid")
    return out


def runs_of(flags, value):
    runs, i = [], 0
    while i < len(flags):
        if flags[i] == value:
            j = i
            while j < len(flags) and flags[j] == value:
                j += 1
            runs.append((i, j))
            i = j
        else:
            i += 1
    return runs


def fill_gaps(points, measured):
    """Replace every interior coasted run with a PCHIP bridge over its known neighbours."""
    points = points.copy()
    known = measured != COASTED
    for lo, hi in runs_of(measured == COASTED, True):
        if lo == 0 or hi == len(points):
            continue
        before = points[max(0, lo - 6) : lo][known[max(0, lo - 6) : lo]]
        after = points[hi : hi + 6][known[hi : hi + 6]]
        anchors = np.vstack([before, after])
        span = np.abs(after[0] - before[-1])
        axis = 0 if span[0] >= span[1] else 1
        order = np.argsort(anchors[:, axis])
        keys, unique = np.unique(anchors[order, axis], return_index=True)
        bridge = PchipInterpolator(keys, anchors[order][unique, 1 - axis])
        steps = np.linspace(before[-1][axis], after[0][axis], hi - lo + 2)[1:-1]
        points[lo:hi, axis] = steps
        points[lo:hi, 1 - axis] = bridge(steps)
    return points


def sharpen_vertices(points, measured, drawn):
    """Restore peaks and troughs drawn as sharp vertices.

    Across a vertex the two arms merge into one blob whose centre lies inside the angle, so the
    traced extreme falls short of the drawn apex. Where both arms are steep (|dy/dx| > VERTEX_SLOPE)
    and of opposite sign and their fitted lines (3-10 px out) meet within VERTEX_REACH px, the apex
    is found by walking from the traced extreme's height straight towards that intersection on the original chart
    (`drawn`, grid lines included) for as long as there is more ink across the walk than at its
    far end (where only a grid line, if any, remains). The stretch within VERTEX_REACH px of the
    extreme is replaced by straight lines to that apex and flagged CORNER; a rounded peak gives
    no apex beyond the extreme and is left alone.
    """
    points, measured = points.copy(), measured.copy()
    x, y = points[:, 0], points[:, 1]
    for i in range(VERTEX_ARM, len(points) - VERTEX_ARM):
        window = y[i - VERTEX_REACH : i + VERTEX_REACH + 1]
        if not (y[i] == window.min() or y[i] == window.max()):
            continue
        left = slice(i - VERTEX_ARM, i - VERTEX_REACH)
        right = slice(i + VERTEX_REACH + 1, i + VERTEX_ARM + 1)
        if not ((measured[left] == MEASURED).all() and (measured[right] == MEASURED).all()):
            continue
        # Steep arms: fit x as a function of y, which stays well conditioned as they near vertical.
        run_l, start_l = np.polyfit(y[left], x[left], 1)
        run_r, start_r = np.polyfit(y[right], x[right], 1)
        if max(abs(run_l), abs(run_r)) > 1 / VERTEX_SLOPE or np.sign(run_l) == np.sign(run_r):
            continue
        meet_y = (start_r - start_l) / (run_l - run_r)
        meet = np.array([start_l + run_l * meet_y, meet_y])
        if abs(meet[0] - x[i]) > VERTEX_REACH or np.linalg.norm(meet - points[i]) < 0.5:
            continue
        arm = np.array([run_l, 1.0]) / np.hypot(run_l, 1.0)
        line = cross_section(drawn, points[i - VERTEX_ARM], arm, 4.0)
        if line is None or not np.isfinite(line[1]):
            continue
        # Walk vertically from the extreme's height at the arms' intersection x, towards the tip.
        apex = ink_apex(drawn, np.array([meet[0], y[i]]), np.array([0.0, np.sign(meet[1] - y[i])]), line[1] / 2)
        if apex is None:
            continue
        before, after = points[i - VERTEX_REACH], points[i + VERTEX_REACH]
        for j in range(i - VERTEX_REACH + 1, i + VERTEX_REACH):
            a, b = (before, apex) if x[j] <= apex[0] else (apex, after)
            points[j, 1] = a[1] + (x[j] - a[0]) / (b[0] - a[0]) * (b[1] - a[1])
            measured[j] = CORNER
        points[min(range(i - VERTEX_REACH + 1, i + VERTEX_REACH), key=lambda j: abs(x[j] - apex[0]))] = apex
    return points, measured


def ink_apex(drawn, start, toward, half_width):
    """Centre of the line's tip: the last point along `toward` with more ink across it than far
    beyond, moved back by the line's half width (that point is the outer edge of the stroke)."""
    normal = np.array([-toward[1], toward[0]])
    across = np.arange(-4, 4.25, PROFILE_STEP)

    def ink(t):
        centre = start + toward * t
        samples = map_coordinates(drawn, [centre[1] + normal[1] * across, centre[0] + normal[0] * across], order=1)
        return samples.sum() * PROFILE_STEP

    background = min(ink(t) for t in (14, 15, 16))
    reach = 0.0
    for t in np.arange(0.5, 12.5, 0.5):
        if ink(t) - background < 0.5:
            break
        reach = t
    # A rounded extreme only has the line's own half width of ink beyond its centre.
    reach -= half_width
    return start + toward * reach if reach >= VERTEX_MIN_REACH else None


def on_axis(drawn, start, end, box, settings, side="top"):
    """A stroke lying on (or just above) the bottom axis line, column by column from x = `start` to `end`.

    Scanning up from the axis line, the stroke's upper edge is where darkness falls below one half;
    its lower edge is the same crossing below it, or the axis line where they merge. With `side`
    "top" the curve is the upper edge plus half the line width, with "bottom" the lower edge minus
    it: two curves overlapping in one stroke (or lying on the axis) are read from the edges each
    one forms. Columns at tick marks are flagged for bridging.
    """
    points, flags = [], []
    rows = np.arange(int(np.floor(box[3] - settings["frameHalfWidth"])), 0, -1)[:12]
    half = settings["lineHalfWidth"]
    for x in range(int(round(start)), int(round(end)) + 1):
        profile = drawn[rows, x]
        dark = profile >= 0.5
        first = int(np.argmax(dark))
        if not dark[first] or first > 3 or dark.all():
            continue
        k = first + int(np.argmax(~dark[first:]))  # first light row above the stroke
        upper = rows[k] + (0.5 - profile[k]) / (profile[k - 1] - profile[k])
        if first == 0:
            lower = rows[0] + 0.5  # merged with the axis line
        else:
            lower = rows[first] + (profile[first] - 0.5) / (profile[first] - profile[first - 1])
        points.append((float(x), upper + half if side == "top" else lower - half))
        at_tick = any(abs(x - t) <= settings["tickHalfWidth"] + 1 for t in settings["bottomTicks"])
        flags.append(COASTED if at_tick else ON_AXIS)
    return np.array(points), np.array(flags), []


def trace_curve(dark, drawn, curve, box, settings):
    """Trace each configured segment and join them.

    A segment is a chain of waypoints, or a dict: {"waypoints": [...], "shared": true} for a line
    several curves share, or {"onAxis": [x0, x1], "side": "top" | "bottom", "shared": bool} for a
    stretch lying on the axis line (see on_axis). Joins between segments and coasted stretches become interpolated. `extendStart` and
    `extendEnd` follow the line beyond the first/last waypoint until it ends or meets the frame.
    """
    all_points, all_measured, all_widths = [], [], []
    specs = [s if isinstance(s, dict) else {"waypoints": s} for s in curve["segments"]]
    if curve.get("extendStart"):
        first = [np.array(p, float) for p in specs[0]["waypoints"]]
        backwards = -line_direction(dark, first[0], first[1] - first[0], settings)
        back = trace_segment(dark, [first[0]], box, settings, heading=backwards)
        if len(back[0]) > 1:
            all_points.append(back[0][:0:-1])
            all_measured.append(back[1][:0:-1])
            all_widths += back[2]
    for index, spec in enumerate(specs):
        if "onAxis" in spec:
            points, measured, widths = on_axis(drawn, *spec["onAxis"], box, settings, spec.get("side", "top"))
        else:
            free_end = curve.get("extendEnd", False) and index == len(specs) - 1
            points, measured, widths = trace_segment(dark, spec["waypoints"], box, settings, free_end=free_end)
        measured = np.asarray(measured)
        if spec.get("shared"):
            measured = np.where(measured == COASTED, COASTED, SHARED)
        if all_points:
            gap_from, gap_to = all_points[-1][-1], points[0]
            count = int(round(np.linalg.norm(gap_to - gap_from))) - 1
            if count > 0:
                all_points.append(np.linspace(gap_from, gap_to, count + 2)[1:-1])
                all_measured.append(np.full(count, COASTED))
        all_points.append(points)
        all_measured.append(measured)
        all_widths += widths
    points, measured = np.vstack(all_points), np.concatenate(all_measured).astype(int)
    points, measured = sharpen_vertices(fill_gaps(smooth(points, measured), measured), measured, drawn)
    return points, measured, all_widths


# MARK: - Resampling


def resample(xs, ys, grid, tolerance):
    """Value at each grid x from the polyline (samples ~1 px apart): mean of all crossings.

    A grid x up to `tolerance` beyond a curve end (half a pixel: the frame line hides the
    last pixel of curves drawn to the edge) takes that end's value.
    """
    values = []
    for g in grid:
        hits = []
        for i in range(len(xs) - 1):
            a, b = xs[i], xs[i + 1]
            if (a - g) * (b - g) <= 0 and a != b:
                hits.append(ys[i] + (g - a) / (b - a) * (ys[i + 1] - ys[i]))
        if not hits:
            end = int(np.argmin(np.abs(xs - g)))
            hits = [ys[end]] if abs(xs[end] - g) <= tolerance else []
        values.append(float(np.mean(hits)) if hits else None)
    return values


def merge_spans(spans, gap):
    """Sorted spans, with any that overlap or lie within `gap` of each other joined."""
    merged = []
    for lo, hi in sorted(spans):
        if merged and lo - merged[-1][1] <= gap:
            merged[-1][1] = max(merged[-1][1], hi)
        else:
            merged.append([lo, hi])
    return merged


def grid_indices(lo, hi, step):
    return range(int(np.ceil(lo / step - 1e-9)), int(np.floor(hi / step + 1e-9)) + 1)


def format_number(value, decimals):
    text = f"{value:.{decimals}f}"
    return text[1:] if text.startswith("-") and float(text) == 0 else text


# MARK: - Charts


def digitize_chart(png, chart, stock_id, name, overlay_dir, trace_dir):
    dark = darkness(png)
    frame = refine_frame(dark, chart["frame"])
    x_cal, y_cal = calibrate(dark, frame, chart["xAxis"]), calibrate(dark, frame, chart["yAxis"])
    cleaned = erase(dark, chart, frame, x_cal, y_cal)
    box = frame  # curves run into the frame line; the last px under it are a straight continuation
    settings = {
        "radius": chart.get("searchRadius", 4.0),
        "maxWidth": chart.get("maxLineWidth", 4.5),
        "maxLateral": chart.get("maxLateral", 1.2),
        "maxGap": chart.get("maxGap", 8),
        "memory": chart.get("memory", 4),
        "frameHalfWidth": chart.get("frameHalfWidth", 2.0),
        "tickHalfWidth": chart.get("tickHalfWidth", 1.5),
        "lineHalfWidth": chart.get("onAxisHalfWidth", 1.0),
        "bottomTicks": to_pixels(x_cal, [v for _, v in chart["xAxis"]["ticks"]]) if chart["xAxis"]["side"] == "bottom" else [],
    }
    step, x_decimals = chart["gridStep"], chart["xDecimals"]
    traces, widths, curve_meta, columns = {}, [], {}, {}
    interpolated_flags = [COASTED, CORNER, ON_AXIS]
    tolerance = 0.5 / abs(x_cal["slope"])
    for curve_name, curve in chart["curves"].items():
        # A curve drawn in separate pieces (it leaves the plot and comes back) lists them under "pieces".
        pieces, spans, shared, columns[curve_name] = [], [], [], {}
        for piece in curve.get("pieces", [curve]):
            points, measured, piece_widths = trace_curve(cleaned, dark, piece, box, settings)
            widths += piece_widths
            data_x, data_y = to_data(x_cal, points[:, 0]), to_data(y_cal, points[:, 1])
            if data_x[-1] < data_x[0]:
                points, measured, data_x, data_y = points[::-1], measured[::-1], data_x[::-1], data_y[::-1]
            pieces.append((points, measured, data_x, data_y))
            bridge = piece.get("bridgePixels", chart.get("bridgePixels", 4))
            for flags, out, minimum in ((np.isin(measured, interpolated_flags), spans, bridge), (measured == SHARED, shared, 0)):
                for lo, hi in runs_of(flags, True):
                    a, b = max(lo - 1, 0), min(hi, len(points) - 1)
                    if np.linalg.norm(points[b] - points[a]) > minimum:
                        span = sorted((float(data_x[a]), float(data_x[b])))
                        out.append([round(span[0], 3), round(span[1], 3)])
            indices = grid_indices(data_x.min() - tolerance, data_x.max() + tolerance, step)
            values = resample(data_x, data_y, [k * step for k in indices], tolerance)
            columns[curve_name] |= {k: v for k, v in zip(indices, values) if v is not None}
        traces[curve_name] = pieces
        every_x = np.concatenate([piece[2] for piece in pieces])
        curve_meta[curve_name] = {
            "xRange": [round(float(every_x.min()), 3), round(float(every_x.max()), 3)],
            "interpolatedSpans": merge_spans(spans, 2 / abs(x_cal["slope"])),
            "sharedSpans": merge_spans(shared, 2 / abs(x_cal["slope"])),
        }
    all_indices = sorted(set().union(*columns.values()))
    rows = []
    for k in all_indices:
        x_text = format_number(k * step, x_decimals)
        cells = [columns[c].get(k) for c in chart["curves"]]
        rows.append([x_text] + ["" if v is None else format_number(v, 4) for v in cells])

    line_width = float(np.median(widths))
    sigma_x = (line_width / 2 + x_cal["residualMax"]) / abs(x_cal["slope"])
    sigma_y = (line_width / 2 + y_cal["residualMax"]) / abs(y_cal["slope"])
    slopes = []
    for _, _, data_x, data_y in (piece for pieces in traces.values() for piece in pieces):
        dx, dy = np.diff(data_x), np.diff(data_y)
        ok = np.abs(dx) > 1e-9
        slopes.append(np.abs(dy[ok] / dx[ok]))
    steep = float(np.percentile(np.concatenate(slopes), 95))
    flank_y = float(np.hypot(sigma_y, steep * sigma_x))
    uncertainty = {
        "x": round(sigma_x, 4),
        "y": round(sigma_y, 4),
        "note": (
            f"1-sigma per point = half the drawn line width ({line_width / 2:.2f} px) plus that axis's largest "
            f"tick-fit residual (x {x_cal['residualMax']:.2f} px, y {y_cal['residualMax']:.2f} px), in data units; "
            "the residual term covers unevenly drawn ticks. "
            f"Where the curve is steep the y error grows with slope: at the 95th-percentile slope of these "
            f"curves ({steep:.2f} y-units per x-unit) a point's y uncertainty is {flank_y:.4f}. "
            "Does not include any error in how the publisher drew the chart."
        ),
    }

    def axis_entry(spec, cal):
        return {
            "quantity": spec["quantity"],
            "anchors": [[round(p, 2), v] for p, v in cal["anchors"]],
            "pixelsPerUnit": round(abs(cal["slope"]), 3),
            "fitResidualPixels": round(cal["residualRMS"], 3),
            "anchorResidualsPixels": [round(r, 2) for r in cal["residuals"]],
        }

    notes = list(chart.get("notes", []))
    for axis, cal in (("x", x_cal), ("y", y_cal)):
        notes += [f"{axis} axis {e}; excluded from the fit" for e in cal["excluded"]]
        notes.append(f"{axis} axis fit: RMS residual {cal['residualRMS']:.3f} px, max {cal['residualMax']:.3f} px")
    entry = {
        "file": chart["file"],
        "page": chart["page"],
        "figureTitle": chart["figureTitle"],
        "figureCode": chart["figureCode"],
        "imageIndex": chart["imageIndex"],
        "imageSizePixels": list(Image.open(png).size),
        "imageSHA256": sha256(png.read_bytes()),
        "conditions": chart["conditions"],
        "gridStep": step,
        "xAxis": axis_entry(chart["xAxis"], x_cal),
        "yAxis": axis_entry(chart["yAxis"], y_cal),
        "lineWidthPixels": round(line_width, 2),
        "uncertainty": uncertainty,
        "curves": curve_meta,
    }
    if "cameraStops" in chart:
        entry["cameraStops"] = camera_stops(dark, frame, chart["cameraStops"], x_cal)
    entry["notes"] = notes

    if overlay_dir:
        draw_overlay(png, traces, columns, step, x_cal, y_cal, overlay_dir / f"{stock_id}_{name}.png")
    if trace_dir:
        write_traces(traces, trace_dir / stock_id / name)
    header = [chart["xColumn"]] + list(chart["curves"])
    return entry, header, rows


def camera_stops(dark, frame, spec, x_cal):
    cal = calibrate(dark, frame, spec)
    pixels, stops = np.array(cal["anchors"]).T
    log_exposure = to_data(x_cal, pixels)
    per_stop, zero = np.polyfit(stops, log_exposure, 1)
    return {
        "anchors": [[round(p, 2), int(s)] for p, s in cal["anchors"]],
        "stopZeroLogExposure": round(float(zero), 4),
        "logExposurePerStop": round(float(per_stop), 4),
    }


COLOURS = [(220, 30, 30), (20, 160, 40), (30, 70, 230), (200, 0, 200), (0, 160, 160)]  # interpolated stretches are orange


def draw_overlay(png, traces, columns, step, x_cal, y_cal, path):
    base = Image.open(png).convert("RGB")
    image = base.resize((base.width * OVERLAY_SCALE, base.height * OVERLAY_SCALE), Image.NEAREST)
    draw = ImageDraw.Draw(image)

    def scaled(x, y):
        return (x + 0.5) * OVERLAY_SCALE, (y + 0.5) * OVERLAY_SCALE

    for colour, (name, pieces) in zip(COLOURS, traces.items()):
        for points, measured, _, _ in pieces:
            for i in range(len(points) - 1):
                if measured[i] == measured[i + 1] == MEASURED:
                    fill = colour
                else:
                    fill = (120, 120, 120) if SHARED in (measured[i], measured[i + 1]) else (255, 170, 0)
                draw.line([scaled(*points[i]), scaled(*points[i + 1])], fill=fill, width=1)
        for k, value in columns[name].items():
            if value is not None:
                x, y = scaled(float(to_pixels(x_cal, k * step)), float(to_pixels(y_cal, value)))
                draw.ellipse([x - 2, y - 2, x + 2, y + 2], outline=colour)
    for cal, horizontal in ((x_cal, True), (y_cal, False)):
        for pixel, _ in cal["anchors"]:
            c = (pixel + 0.5) * OVERLAY_SCALE
            if horizontal:
                draw.line([(c, 0), (c, 12)], fill=(0, 200, 220), width=1)
            else:
                draw.line([(0, c), (12, c)], fill=(0, 200, 220), width=1)
    image.save(path)


def write_traces(traces, prefix):
    prefix.parent.mkdir(parents=True, exist_ok=True)
    for name, pieces in traces.items():
        with open(f"{prefix}_{name}.csv", "w", newline="") as f:
            out = csv.writer(f, lineterminator="\n")
            out.writerow(["piece", "pixel_x", "pixel_y", "flag", "x", "y"])  # flag: 1 measured, 0 interpolated, 2 corner apex, 3 shared line, 4 on axis
            for index, (points, measured, data_x, data_y) in enumerate(pieces):
                for (px, py), m, x, y in zip(points, measured, data_x, data_y):
                    out.writerow([index, f"{px:.3f}", f"{py:.3f}", int(m), f"{x:.5f}", f"{y:.5f}"])


def to_json(value):
    """Indented JSON with every list of plain values (anchors, ranges, segments) kept on one line."""
    text = json.dumps(value, indent=2, ensure_ascii=False)
    flat_list = re.compile(r"\[[^\[\]{}]*\]")
    text = flat_list.sub(lambda m: re.sub(r"\s+", " ", m.group()).replace("[ ", "[").replace(" ]", "]"), text)
    nested = re.compile(r"\[\s*((?:\[[^\[\]{}]*\],?\s*)+)\]")
    text = nested.sub(lambda m: "[" + re.sub(r"\],\s*\[", "], [", m.group(1).strip()) + "]", text)
    return text + "\n"


def write_csv(path, header, rows):
    """Writes the CSV and returns the SHA-256 of its bytes."""
    buffer = io.StringIO()
    out = csv.writer(buffer, lineterminator="\n")
    out.writerow(header)
    out.writerows(rows)
    data = buffer.getvalue().encode()
    path.write_bytes(data)
    return sha256(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--pdf-dir", type=pathlib.Path, required=True)
    parser.add_argument("--out", type=pathlib.Path, required=True, help="folder for the traced CSVs and manifests")
    parser.add_argument("--manifests", type=pathlib.Path, help="also write each manifest.json here (the repository's StockData)")
    parser.add_argument("--overlays", type=pathlib.Path)
    parser.add_argument("--traces", type=pathlib.Path)
    parser.add_argument("--only", help="digitize just this stock id")
    args = parser.parse_args()
    config = json.loads(CONFIG.read_text())
    for directory in (args.overlays, args.traces):
        if directory:
            directory.mkdir(parents=True, exist_ok=True)
    poppler = poppler_version()
    for stock in config["stocks"]:
        if args.only and stock["id"] != args.only:
            continue
        pdf = args.pdf_dir / stock["pdf"]
        digest = sha256(pdf.read_bytes())
        if digest != stock["source"]["pdfSHA256"]:
            raise SystemExit(f"{pdf.name}: SHA-256 {digest} does not match charts.json")
        check_revision(pdf, stock["revisionText"])
        out_dir = args.out / stock["id"]
        out_dir.mkdir(parents=True, exist_ok=True)
        charts = {}
        with tempfile.TemporaryDirectory() as scratch:
            images = extract_images(pdf, pathlib.Path(scratch))
            for name, chart in stock["charts"].items():
                png = images[chart["imageIndex"]]
                if list(Image.open(png).size) != chart["imageSizePixels"]:
                    raise SystemExit(f"{stock['id']} {name}: unexpected image size")
                print(f"{stock['id']}: {name}", file=sys.stderr)
                entry, header, rows = digitize_chart(png, chart, stock["id"], name, args.overlays, args.traces)
                digest = write_csv(out_dir / chart["file"], header, rows)
                charts[name] = {"file": entry["file"], "sha256": digest} | {k: v for k, v in entry.items() if k != "file"}
        manifest = {
            "formatVersion": 1,
            "stock": stock["id"],
            "filmType": stock["filmType"],
            "source": stock["source"],
            "tracings": TRACINGS_NOTE,
            "charts": charts,
            "method": config["method"],
            "tool": "Tools/stock-digitizing/digitize.py",
            "popplerVersion": poppler,
            "tracedOn": config["tracedOn"],
        }
        for directory in (out_dir, args.manifests and args.manifests / stock["id"]):
            if directory:
                directory.mkdir(parents=True, exist_ok=True)
                (directory / "manifest.json").write_text(to_json(manifest))


if __name__ == "__main__":
    main()
