"""Compare tracing A (the main tracing) with the independent tracing B (the cross-check).

Offline helper, never shipped. For every curve, over the grid points both tracings have:
n, RMS, mean and max |A - B| with its x. For characteristic curves the difference is also
expressed along log E (|dD| / local slope, only where the slope exceeds MIN_SLOPE D per log E).
Writes crosscheck/agreement.md (deterministic) and exits non-zero if a characteristic curve
exceeds the MOV-16 acceptance (MAX_DENSITY or MAX_LOG_EXPOSURE) at points tracing A actually
traced, i.e. outside its interpolatedSpans and sharedSpans (merges and bridges, where neither
tracing can resolve the channel; those points are still reported). Spectral curves are
reported, not gated; those above REPORT_ABOVE are listed with the likely reason.

The traced CSVs are not in the repository (docs/DECISIONS.md, 12 Nov 2026). Tracing A is read from
the reference data (--data, else $EMULSION_REFERENCE_DATA, else ~/Documents/Emulsion Research/datasheet-tracings)
and must match the SHA-256 its committed manifest pins; tracing B from --tracing-b
(default: <data>/crosscheck/tracing-b).

    python3 -I Tools/stock-digitizing/compare_tracings.py [--data <dir>] [--tracing-b <dir>]
"""

import argparse
import csv
import hashlib
import io
import json
import os
import pathlib
import sys

import numpy as np

HERE = pathlib.Path(__file__).parent
MANIFESTS = HERE.parents[1] / "Packages/EmulsionCore/Sources/EmulsionFit/Resources/StockData"
REPORT = HERE / "crosscheck" / "agreement.md"
REFERENCE_DATA_VARIABLE = "EMULSION_REFERENCE_DATA"
DEFAULT_REFERENCE_DATA = pathlib.Path("Documents/Emulsion Research/datasheet-tracings")  # under the home directory
MAX_DENSITY = 0.03  # MOV-16 acceptance for characteristic curves, density
MAX_LOG_EXPOSURE = 0.02  # MOV-16 acceptance for characteristic curves, log E
MIN_SLOPE = 0.2  # D per log E: below this a density difference says nothing about log E
REPORT_ABOVE = 0.03  # spectral curves with a larger max |A - B| are listed with a reason
STEEP = 0.05  # y change per grid step above which a point counts as on a steep flank


def tracing_arguments(parser):
    """Adds --data and --tracing-b; `tracing_dirs` resolves them."""
    parser.add_argument(
        "--data", type=pathlib.Path,
        help=f"reference data, tracing A: <stock>/<chart>.csv as digitize.py --out writes (default: ${REFERENCE_DATA_VARIABLE}, else ~/{DEFAULT_REFERENCE_DATA})",
    )
    parser.add_argument("--tracing-b", type=pathlib.Path, help="tracing B (default: <data>/crosscheck/tracing-b)")


RETRACE_HINT = f"re-trace the curves with Tools/stock-digitizing/digitize.py, then pass --data or set {REFERENCE_DATA_VARIABLE}"


def tracing_dirs(args):
    data = (args.data or pathlib.Path(os.environ.get(REFERENCE_DATA_VARIABLE) or pathlib.Path.home() / DEFAULT_REFERENCE_DATA)).expanduser()
    if not data.is_dir():
        sys.exit(f"No reference data at {data}: {RETRACE_HINT}.")
    return data, (args.tracing_b or data / "crosscheck" / "tracing-b").expanduser()


def read_bytes(path):
    """The file's bytes; exits with a one-line message when it is missing."""
    if not path.is_file():
        sys.exit(f"Missing file: {path}: {RETRACE_HINT}.")
    return path.read_bytes()


def stocks(tracing_a):
    """Stock ids with a committed manifest, sorted, each with its manifest. Exits if tracing A is not
    the tracing a manifest pins."""
    result = []
    for path in sorted(MANIFESTS.glob("*/manifest.json")):
        manifest = json.loads(path.read_text())
        for entry in manifest["charts"].values():
            csv_path = tracing_a / path.parent.name / entry["file"]
            digest = hashlib.sha256(read_bytes(csv_path)).hexdigest()
            if digest != entry["sha256"]:
                sys.exit(f"{csv_path}: SHA-256 {digest}, but {path} pins {entry['sha256']}")
        result.append((path.parent.name, manifest))
    return result


def read(path):
    rows = list(csv.reader(io.StringIO(read_bytes(path).decode(), newline="")))
    header, body = rows[0], rows[1:]
    columns = {}
    for j, name in enumerate(header[1:], 1):
        columns[name] = {round(float(r[0]), 2): float(r[j]) for r in body if r[j] != ""}
    return columns


def slope_at(curve, x, step):
    """Central-difference slope of `curve` at grid point x; a missing neighbour counts as x itself."""
    before, after = curve.get(round(x - step, 2), curve[x]), curve.get(round(x + step, 2), curve[x])
    return (after - before) / (2 * step)


def within(x, spans):
    return any(lo <= x <= hi for lo, hi in spans)


def compare(a, b, step, spans, name):
    xs = sorted(set(a) & set(b))
    if not xs:
        return None
    diff = np.array([a[x] - b[x] for x in xs])
    worst = int(np.argmax(np.abs(diff)))
    x_worst = xs[worst]
    slope = slope_at(a, x_worst, step)
    result = {
        "n": len(xs),
        "rms": float(np.sqrt((diff**2).mean())),
        "mean": float(diff.mean()),
        "max": float(abs(diff[worst])),
        "at": x_worst,
        "slope": slope,
    }
    reasons = []
    if abs(slope) * step > STEEP:
        reasons.append(f"steep flank ({slope:+.3g} per unit)")
    if within(x_worst, spans["interpolatedSpans"]):
        reasons.append("interpolated in A")
    if within(x_worst, spans.get("sharedSpans", [])):
        reasons.append("shared line in A")
    if name == "minimum_density":
        reasons.append("dashed line")
    result["reason"] = "; ".join(reasons) or "not explained by slope, span or dash"
    return result


def log_exposure_differences(a, b, step, xs=None):
    """|dD| / local slope of A, at common points (or `xs`) where that slope exceeds MIN_SLOPE."""
    out = []
    for x in sorted(set(a) & set(b)) if xs is None else xs:
        if round(x - step, 2) not in a or round(x + step, 2) not in a:
            continue
        slope = slope_at(a, x, step)
        if slope > MIN_SLOPE:
            out.append(abs(a[x] - b[x]) / slope)
    return np.array(out) if out else np.zeros(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    tracing_arguments(parser)
    tracing_a, tracing_b = tracing_dirs(parser.parse_args())
    lines = [
        "# Tracing A vs tracing B",
        "",
        "Generated by `Tools/stock-digitizing/compare_tracings.py` on the local tracings (the CSVs are not in the repository).",
        "A = the tracing the manifests in `Packages/EmulsionCore/Sources/EmulsionFit/Resources/StockData` pin by SHA-256;",
        "B = an independent tracing from 600-dpi page renders (see `Tools/stock-digitizing/crosscheck/tracing-b/report-b.md`).",
        f"Differences are A - B over the grid points both have. Characteristic curves must stay within {MAX_DENSITY} D and",
        f"{MAX_LOG_EXPOSURE} log E (|dD| / slope where the slope exceeds {MIN_SLOPE} D per log E). Spectral curves are reported only.",
        "",
        "Gate columns use only points outside A's interpolatedSpans and sharedSpans.",
        "",
        "| Stock | Chart | Curve | n | RMS | mean | max abs | at x | log E RMS | log E max | gated n | gated max D | gated max log E | Gate |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    listed, failures = [], []
    for stock, manifest in stocks(tracing_a):
        for chart, entry in manifest["charts"].items():
            a_columns, b_columns = read(tracing_a / stock / entry["file"]), read(tracing_b / stock / entry["file"])
            step = entry["gridStep"]
            for name, a in a_columns.items():
                spans = entry["curves"][name]
                result = compare(a, b_columns.get(name, {}), step, spans, name)
                if result is None:
                    lines.append(f"| {stock} | {chart} | {name} | 0 | | | | | | | | | | no common points |")
                    continue
                log_cells, gate = "| | | | ", "reported"
                if chart == "characteristic":
                    b = b_columns[name]
                    log_e = log_exposure_differences(a, b, step)
                    traced = [x for x in sorted(set(a) & set(b)) if not within(x, spans["interpolatedSpans"] + spans.get("sharedSpans", []))]
                    gated_d = max(abs(a[x] - b[x]) for x in traced)
                    gated_log = float(log_exposure_differences(a, b, step, traced).max())
                    log_cells = (
                        f"{float(np.sqrt((log_e**2).mean())):.4f} | {float(log_e.max()):.4f} | "
                        f"{len(traced)} | {gated_d:.4f} | {gated_log:.4f}"
                    )
                    passed = gated_d <= MAX_DENSITY and gated_log <= MAX_LOG_EXPOSURE
                    gate = "pass" if passed else "FAIL"
                    if not passed:
                        failures.append(f"{stock} {name}")
                elif result["max"] > REPORT_ABOVE:
                    listed.append(f"- {stock} {chart} {name}: max {result['max']:.4f} at {result['at']:g} ({result['reason']})")
                lines.append(
                    f"| {stock} | {chart} | {name} | {result['n']} | {result['rms']:.4f} | {result['mean']:+.4f} | "
                    f"{result['max']:.4f} | {result['at']:g} | {log_cells} | {gate} |"
                )
    lines += ["", f"## Spectral curves with max |A - B| above {REPORT_ABOVE}", ""]
    lines += listed or ["None."]
    lines += ["", "## Result", "", f"Characteristic-curve gate: {'FAIL: ' + ', '.join(failures) if failures else 'pass'}.", ""]
    REPORT.write_text("\n".join(lines))
    print("\n".join(lines))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
