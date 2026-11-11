"""Proof plots of the traced stock data, drawn on our own axes (no chart artwork).

Offline helper, never shipped. Per stock and chart: tracing A (the reference data: --data, else
$EMULSION_REFERENCE_DATA, else ~/Documents/Emulsion Research/datasheet-tracings) as lines, tracing B
(--tracing-b, default <data>/crosscheck/tracing-b) as small markers, and A - B underneath. With --fit-dir, per
negative stock: the measured characteristic curves against both fits from
`<id>.negative-fit.csv`, with residuals and +-0.03 D guide lines underneath.

    python3 -I Tools/stock-digitizing/plot_curves.py --out <dir> [--data <dir>] [--fit-dir <dir>]
"""

import argparse
import csv
import pathlib
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

sys.dont_write_bytecode = True  # no __pycache__ in the repo
sys.path.insert(0, str(pathlib.Path(__file__).parent))  # python -I leaves the script's folder off the path
from compare_tracings import read, stocks, tracing_arguments, tracing_dirs  # noqa: E402

FIT_GUIDE = 0.03  # D: MOV-16 acceptance, drawn as guide lines on the fit residuals
COLOURS = {
    "red": "#c0392b", "green": "#27864a", "blue": "#2c5aa0",
    "yellow": "#c9a400", "yellow_forming_layer": "#c9a400",
    "magenta": "#b0308f", "magenta_forming_layer": "#b0308f",
    "cyan": "#1f9bb0", "cyan_forming_layer": "#1f9bb0",
    "midscale_neutral": "#333333", "visual_neutral": "#333333", "minimum_density": "#8a8a8a",
}
TITLES = {"characteristic": "characteristic curves", "spectralSensitivity": "spectral sensitivity", "spectralDyeDensity": "spectral dye density"}
X_LABELS = {"characteristic": "log10 exposure (lux-seconds)", "spectralSensitivity": "wavelength (nm)", "spectralDyeDensity": "wavelength (nm)"}
Y_LABELS = {"characteristic": "density", "spectralSensitivity": "log10 sensitivity", "spectralDyeDensity": "diffuse spectral density"}
METADATA = {"Software": None}  # keeps the PNGs free of the matplotlib version string


def two_panels(title, x_label, y_label, residual_label):
    figure, (top, bottom) = plt.subplots(2, 1, figsize=(8, 7), sharex=True, gridspec_kw={"height_ratios": [3, 1]})
    top.set_title(title)
    top.set_ylabel(y_label)
    bottom.set_ylabel(residual_label)
    bottom.set_xlabel(x_label)
    for axis in (top, bottom):
        axis.grid(True, color="#dddddd", linewidth=0.6)
    bottom.axhline(0, color="#999999", linewidth=0.8)
    return figure, top, bottom


def plot_tracings(tracing_a, tracing_b, stock, chart, filename, path):
    a_columns, b_columns = read(tracing_a / stock / filename), read(tracing_b / stock / filename)
    figure, top, bottom = two_panels(f"{stock}: {TITLES[chart]}", X_LABELS[chart], Y_LABELS[chart], "A - B")
    for name, a in a_columns.items():
        colour = COLOURS[name]
        xs = sorted(a)
        top.plot(xs, [a[x] for x in xs], color=colour, linewidth=1.4, label=name)
        b = b_columns.get(name, {})
        xb = sorted(b)
        top.plot(xb, [b[x] for x in xb], linestyle="none", marker="o", markersize=2.5, color=colour, alpha=0.7)
        common = sorted(set(a) & set(b))
        bottom.plot(common, [a[x] - b[x] for x in common], color=colour, linewidth=1, marker=".", markersize=3)
    top.plot([], [], linestyle="none", marker="o", markersize=2.5, color="#555555", label="tracing B (markers)")
    top.legend(fontsize=8, frameon=False)
    figure.tight_layout()
    figure.savefig(path, dpi=130, metadata=METADATA)
    plt.close(figure)


def plot_fit(stock, csv_path, path):
    with open(csv_path, newline="") as f:
        rows = list(csv.DictReader(f))
    figure, top, bottom = two_panels(f"{stock}: characteristic curves vs fits", X_LABELS["characteristic"], "density", "fit - measured")
    for layer in sorted({r["layer"] for r in rows}, key=["red", "green", "blue"].index):
        data = [r for r in rows if r["layer"] == layer]
        x = [float(r["log_exposure_lux_s"]) for r in data]
        measured = [float(r["measured"]) for r in data]
        shared = [float(r["fitted_shared_range"]) for r in data]
        per_layer = [float(r["fitted_per_layer_range"]) for r in data]
        colour = COLOURS[layer]
        top.plot(x, measured, linestyle="none", marker="o", markersize=2.5, color=colour, label=f"{layer} measured")
        top.plot(x, shared, color=colour, linewidth=1.2, label=f"{layer} fit, shared range")
        top.plot(x, per_layer, color=colour, linewidth=1.2, linestyle="--", label=f"{layer} fit, per-layer range")
        bottom.plot(x, [s - m for s, m in zip(shared, measured)], color=colour, linewidth=1)
        bottom.plot(x, [p - m for p, m in zip(per_layer, measured)], color=colour, linewidth=1, linestyle="--")
    for level in (-FIT_GUIDE, FIT_GUIDE):
        bottom.axhline(level, color="#999999", linewidth=0.8, linestyle=":")
    top.legend(fontsize=7, frameon=False, ncol=3)
    figure.tight_layout()
    figure.savefig(path, dpi=130, metadata=METADATA)
    plt.close(figure)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    tracing_arguments(parser)
    parser.add_argument("--out", type=pathlib.Path, required=True)
    parser.add_argument("--fit-dir", type=pathlib.Path)
    args = parser.parse_args()
    tracing_a, tracing_b = tracing_dirs(args)
    for stock, manifest in stocks(tracing_a):
        directory = args.out / stock
        directory.mkdir(parents=True, exist_ok=True)
        for chart, entry in manifest["charts"].items():
            plot_tracings(tracing_a, tracing_b, stock, chart, entry["file"], directory / f"{chart}.png")
        if args.fit_dir and manifest["filmType"] == "cameraNegative":
            fit = args.fit_dir / f"{stock}.negative-fit.csv"
            if fit.exists():
                plot_fit(stock, fit, directory / "negative-fit.png")
            else:
                print(f"{stock}: no {fit.name}; fit plot skipped")


if __name__ == "__main__":
    main()
