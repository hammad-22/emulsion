"""Offline ground-truth grain reference: the Boolean model of opaque disk grains.

Grains are opaque disks of constant radius whose centres form a homogeneous Poisson point
process of intensity lambda (grains per square micrometre). This is the classical Boolean model
of stochastic geometry, the model behind Newson, Delon and Galerne, "A Stochastic Film Grain
Model for Resolution-Independent Rendering", Computer Graphics Forum 36(8), 2017. It is
implemented here from that published description only (clean room: no reference code was read).

For uniform patches at three diffuse densities the script measures, each with a Monte-Carlo
standard error:
  1. sigma_D through Kodak's 48 um circular aperture;
  2. sigma_D through square pixel apertures, and the ratio to Selwyn's law;
  3. the radially averaged Wiener spectrum of the (linearized) density field;
  4. the Nutting thin-absorber check, sigma_D^2 = 0.434 a D / |A|;
and compares every number with the model's analytic covariance
  C(h) = q^2 (exp(lambda gamma(h)) - 1),   q = exp(-lambda a),
where gamma(h) is the overlap area of two grain disks whose centres are h apart.

Sampling: the coverage indicator is point-sampled exactly on a 0.1 um lattice (a lattice point
is covered iff some centre lies within r of it; disks are rasterized row by row analytically).
Point samples of a stationary field are unbiased and have exactly the model's covariance; the
only approximation is that aperture means are lattice (midpoint-rule) sums rather than
integrals. That bias is computed exactly and reported ("lattice" vs "continuous" analytic).

Test reference only: r = 0.5 um and the densities are arbitrary test values, not a measurement
of any film stock. Offline tool; nothing here ships.

    python -I boolean_grain_reference.py --out grain-boolean-model.json [--quick]
"""

import argparse
import json
import math
import pathlib
import time

import numpy as np

VERSION = "boolean-grain-reference/1.0"

LOG10_E = 1.0 / math.log(10.0)  # 0.4343: dD = -log10(e) dT / T
GRAIN_RADIUS_UM = 0.5  # arbitrary test value, not a film measurement
GRAIN_AREA_UM2 = math.pi * GRAIN_RADIUS_UM**2
TARGET_DENSITIES = (0.3, 0.8, 1.5)  # diffuse density of the patch, -log10(q)
SAMPLE_PITCH_UM = 0.1  # lattice pitch; makes every pixel side below an integer number of samples
CIRCLE_DIAMETER_UM = 48.0  # Kodak's microdensitometer aperture (H-1-5207, H-1-5219)
# Engine pixel pitches for an assumed 24.89 mm frame width, rounded to 0.1 um so each side is a
# whole number of lattice samples (exact: 3.087, 6.173, 9.738, 15.556, 21.111 um).
FRAME_WIDTH_MM = 24.89
PIXEL_COUNTS = (8064, 4032, 2556, 1600, 1179)
PIXEL_SIDES_UM = (3.1, 6.2, 9.7, 15.6, 21.1)
# Apertures sit in cells separated by 1 um (= one grain diameter), so no grain touches two.
APERTURE_GAP_UM = 1.0
SELWYN_TOLERANCE = 0.05
TILE_SAMPLES = 2500  # target tile side in lattice samples (memory bound)
SPECTRUM_FIELD_SAMPLES = 2048  # periodogram field side: 204.8 um at 0.1 um
SPECTRUM_MAX_CYCLES_PER_MM = 2000.0
SPECTRUM_BINS = 64
PLATEAU_MAX_CYCLES_PER_MM = 50.0  # analytic W drops < 0.5% below this
BOOTSTRAP_RESAMPLES = 1000
BASE_SEED = 20171108
SIGNIFICANT_DIGITS = 6

FULL = {"placements": 10000, "spectrum_fields": 64}
QUICK = {"placements": 400, "spectrum_fields": 4}


# MARK: Geometry and analytic model


def lens_area(h, radius):
    """Overlap area of two disks of `radius` whose centres are `h` apart (gamma(h))."""
    h = np.minimum(np.abs(np.asarray(h, dtype=float)), 2 * radius)
    return 2 * radius**2 * np.arccos(h / (2 * radius)) - 0.5 * h * np.sqrt(
        np.maximum(4 * radius**2 - h**2, 0.0)
    )


class BooleanModel:
    """Opaque disks of radius r with Poisson centres of intensity lam (per um^2)."""

    def __init__(self, target_density, radius=GRAIN_RADIUS_UM):
        self.radius = radius
        self.grain_area = math.pi * radius**2
        self.lam = target_density / (LOG10_E * self.grain_area)
        self.open_fraction = math.exp(-self.lam * self.grain_area)  # q = 1 - u
        self.density = -math.log10(self.open_fraction)

    def covariance(self, h):
        """Covariance of the transmittance (= of the coverage indicator) at lag h um."""
        return self.open_fraction**2 * np.expm1(self.lam * lens_area(h, self.radius))

    def _radial_nodes(self, count=400):
        nodes, weights = np.polynomial.legendre.leggauss(count)
        h = self.radius * (nodes + 1.0)  # [0, 2r]
        return h, weights * self.radius

    def covariance_integral(self):
        """Integral of C over the plane = W_T(0), the transmittance Wiener spectrum at 0."""
        h, w = self._radial_nodes()
        return float(np.sum(w * 2 * np.pi * h * self.covariance(h)))

    def transmittance_variance_circle(self, diameter):
        """Var of the mean transmittance over a disk aperture (continuous integral)."""
        big = diameter / 2
        area = math.pi * big**2
        h, w = self._radial_nodes()
        return float(np.sum(w * 2 * np.pi * h * self.covariance(h) * lens_area(h, big))) / area**2

    def transmittance_variance_square(self, side):
        """Var of the mean transmittance over a square aperture of `side` (needs side >= 2r).

        Angular integral of the set covariance (p-|hx|)(p-|hy|) is 2 pi p^2 - 8 p h + 2 h^2.
        """
        assert side >= 2 * self.radius
        h, w = self._radial_nodes()
        angular = 2 * np.pi * side**2 - 8 * side * h + 2 * h**2
        return float(np.sum(w * h * self.covariance(h) * angular)) / side**4

    def spectrum_continuous(self, cycles_per_um):
        """W_T(f) = 2 pi int h C(h) J0(2 pi f h) dh (Hankel transform), in T^2 um^2."""
        h, w = self._radial_nodes()
        theta, tw = np.polynomial.legendre.leggauss(96)
        theta = 0.5 * np.pi * (theta + 1.0)
        tw = 0.5 * np.pi * tw
        f = np.atleast_1d(np.asarray(cycles_per_um, dtype=float))
        arg = 2 * np.pi * f[:, None, None] * h[None, :, None] * np.sin(theta)[None, None, :]
        bessel_j0 = np.sum(np.cos(arg) * tw, axis=2) / np.pi
        return np.sum(w * 2 * np.pi * h * self.covariance(h) * bessel_j0, axis=1)

    def lattice_lags(self, pitch):
        """Integer lattice lags (kx, ky) with nonzero covariance, and C at each lag."""
        reach = int(math.ceil(2 * self.radius / pitch))
        k = np.arange(-reach, reach + 1)
        kx, ky = np.meshgrid(k, k, indexing="xy")
        distance = pitch * np.hypot(kx, ky)
        keep = distance < 2 * self.radius
        return kx[keep], ky[keep], self.covariance(distance[keep])

    def transmittance_variance_lattice(self, mask, pitch):
        """Exact Var of the mean of point samples over `mask` (what the simulation measures)."""
        kx, ky, c = self.lattice_lags(pitch)
        n = mask.sum()
        total = 0.0
        for dx, dy, value in zip(kx, ky, c):
            total += value * pair_count(mask, int(dx), int(dy))
        return total / n**2


def pair_count(mask, dx, dy):
    """Number of point pairs (x, x + (dx, dy)) both inside a boolean mask."""
    rows, cols = mask.shape
    a = mask[max(0, -dy) : rows - max(0, dy), max(0, -dx) : cols - max(0, dx)]
    b = mask[max(0, dy) : rows - max(0, -dy), max(0, dx) : cols - max(0, -dx)]
    return int(np.count_nonzero(a & b))


# MARK: Simulation


def poisson_centres(rng, lam, width, height, margin):
    """Poisson centres on [-margin, width + margin] x [-margin, height + margin] (um)."""
    count = rng.poisson(lam * (width + 2 * margin) * (height + 2 * margin))
    x = rng.uniform(-margin, width + margin, count)
    y = rng.uniform(-margin, height + margin, count)
    return x, y


def coverage_counts(x, y, radius, columns, rows, pitch):
    """Number of disks covering each lattice point ((i + 1/2) pitch, (j + 1/2) pitch).

    Exact for point samples: each disk is a set of row runs [i0, i1] computed from the chord
    half-width; runs are accumulated with a difference array.
    """
    rows_per_disk = int(math.floor(2 * radius / pitch)) + 2
    first_row = np.ceil((y - radius) / pitch - 0.5).astype(np.int64)
    j = first_row[:, None] + np.arange(rows_per_disk)[None, :]
    dy = (j + 0.5) * pitch - y[:, None]
    half_width_sq = radius**2 - dy**2
    valid = (half_width_sq >= 0) & (j >= 0) & (j < rows)
    half_width = np.sqrt(np.where(valid, half_width_sq, 0.0))
    i0 = np.ceil((x[:, None] - half_width) / pitch - 0.5).astype(np.int64)
    i1 = np.floor((x[:, None] + half_width) / pitch - 0.5).astype(np.int64)
    i0 = np.clip(i0, 0, columns)
    i1 = np.clip(i1, -1, columns - 1)
    valid &= i1 >= i0
    stride = columns + 1
    size = rows * stride
    starts = np.bincount((j * stride + i0)[valid], minlength=size)
    ends = np.bincount((j * stride + i1 + 1)[valid], minlength=size)
    diff = (starts - ends).astype(np.int32).reshape(rows, stride)
    return np.cumsum(diff, axis=1)[:, :columns]


def open_field(rng, model, columns, rows, pitch):
    """Transmittance (1 open, 0 covered) on the lattice, plus the grain centres (um)."""
    x, y = poisson_centres(rng, model.lam, columns * pitch, rows * pitch, model.radius)
    counts = coverage_counts(x, y, model.radius, columns, rows, pitch)
    return counts == 0, x, y


class Aperture:
    """A circular or square aperture laid out on the lattice in a grid of independent cells."""

    def __init__(self, kind, size_um, pitch=SAMPLE_PITCH_UM):
        self.kind = kind
        self.size_um = size_um
        self.pitch = pitch
        self.extent = int(round(size_um / pitch))
        assert abs(self.extent * pitch - size_um) < 1e-9, "aperture must be whole samples"
        self.cell = self.extent + int(round(APERTURE_GAP_UM / pitch))
        centres = (np.arange(self.extent) + 0.5) * pitch
        if kind == "circle":
            rel = centres - size_um / 2
            self.mask = rel[None, :] ** 2 + rel[:, None] ** 2 <= (size_um / 2) ** 2
            self.area_um2 = math.pi * (size_um / 2) ** 2
        else:
            self.mask = np.ones((self.extent, self.extent), dtype=bool)
            self.area_um2 = size_um**2
        self.samples = int(self.mask.sum())
        self.cells_per_tile = max(1, TILE_SAMPLES // self.cell)

    def inside(self, u, v):
        """Whether cell-local positions (um) lie inside the continuous aperture."""
        if self.kind == "circle":
            half = self.size_um / 2
            return (u - half) ** 2 + (v - half) ** 2 < half**2
        return (u >= 0) & (u < self.size_um) & (v >= 0) & (v < self.size_um)

    def measure_tile(self, rng, model):
        """Mean transmittance (lattice) and grain-centre count (continuous) per cell."""
        k = self.cells_per_tile
        side = k * self.cell
        is_open, x, y = open_field(rng, model, side, side, self.pitch)
        blocks = is_open.reshape(k, self.cell, k, self.cell)[:, : self.extent, :, : self.extent]
        open_samples = np.einsum("aibj,ij->ab", blocks.astype(np.float64), self.mask)
        mean_transmittance = (open_samples / self.samples).ravel()

        cell_um = self.cell * self.pitch
        cx = np.floor(x / cell_um).astype(np.int64)
        cy = np.floor(y / cell_um).astype(np.int64)
        in_tile = (cx >= 0) & (cx < k) & (cy >= 0) & (cy < k)
        u = x - cx * cell_um
        v = y - cy * cell_um
        hit = in_tile & self.inside(u, v)
        counts = np.bincount((cy * k + cx)[hit], minlength=k * k)
        return mean_transmittance, counts

    def measure(self, rng, model, placements):
        transmittances, counts = [], []
        total = 0
        while total < placements:
            t, n = self.measure_tile(rng, model)
            transmittances.append(t)
            counts.append(n)
            total += t.size
        return np.concatenate(transmittances), np.concatenate(counts)


def bootstrap_std(rng, values):
    """Sample standard deviation and its bootstrap standard error."""
    n = values.size
    replicates = np.empty(BOOTSTRAP_RESAMPLES)
    for b in range(BOOTSTRAP_RESAMPLES):
        replicates[b] = values[rng.integers(0, n, n)].std(ddof=1)
    return float(values.std(ddof=1)), float(replicates.std(ddof=1))


def estimate(value, se):
    return {"value": value, "se": se}


def ratio_se(a, a_se, b, b_se):
    """Standard error of a / b for independent a, b (first order)."""
    r = a / b
    return r, abs(r) * math.hypot(a_se / a, b_se / b)


def measure_aperture(rng, boot_rng, model, aperture, placements):
    t, counts = aperture.measure(rng, model, placements)
    q = model.open_fraction
    sigma_t, sigma_t_se = bootstrap_std(boot_rng, t)
    lattice_var = model.transmittance_variance_lattice(aperture.mask, aperture.pitch)
    if aperture.kind == "circle":
        continuous_var = model.transmittance_variance_circle(aperture.size_um)
    else:
        continuous_var = model.transmittance_variance_square(aperture.size_um)

    zeros = int(np.count_nonzero(t == 0))
    if zeros == 0:
        log_sigma, log_sigma_se = bootstrap_std(boot_rng, -np.log10(t))
        log_readout = estimate(log_sigma, log_sigma_se)
    else:
        log_readout = None  # some apertures fully covered: D = infinity

    nutting_density = LOG10_E * model.grain_area * counts / aperture.area_um2
    nutting_sigma, nutting_se = bootstrap_std(boot_rng, nutting_density)
    nutting_exact = math.sqrt(LOG10_E * model.grain_area * model.density / aperture.area_um2)

    return {
        "placements": int(t.size),
        "lattice_samples": aperture.samples,
        "area_um2": aperture.area_um2,
        "mean_transmittance": estimate(float(t.mean()), float(t.std(ddof=1) / math.sqrt(t.size))),
        "sigma_d_linearized": estimate(LOG10_E * sigma_t / q, LOG10_E * sigma_t_se / q),
        "sigma_d_log_readout": log_readout,
        "fully_covered_placements": zeros,
        "sigma_d_analytic_lattice": LOG10_E * math.sqrt(lattice_var) / q,
        "sigma_d_analytic_continuous": LOG10_E * math.sqrt(continuous_var) / q,
        "nutting": {
            "sigma_d": estimate(nutting_sigma, nutting_se),
            "sigma_d_exact": nutting_exact,
        },
    }


# MARK: Wiener spectrum


def radial_bins(n, pitch):
    f = np.fft.fftfreq(n, d=pitch) * 1000.0  # cycles/mm
    fx, fy = np.meshgrid(f, f, indexing="xy")
    radius = np.hypot(fx, fy)
    width = SPECTRUM_MAX_CYCLES_PER_MM / SPECTRUM_BINS
    index = np.floor(radius / width).astype(np.int64)
    index[0, 0] = -1  # DC carries no information once the mean is removed
    index[index >= SPECTRUM_BINS] = -1
    return fx, fy, radius, index


def binned_mean(values, index):
    keep = index >= 0
    sums = np.bincount(index[keep], weights=values[keep], minlength=SPECTRUM_BINS)
    counts = np.bincount(index[keep], minlength=SPECTRUM_BINS)
    return sums / counts


def expected_periodogram(model, fx, fy, n, pitch, mask):
    """Exact E[periodogram] of the lattice-sampled transmittance at the masked frequencies.

    E|DFT|^2 s^2 / N^2 = s^2 sum_k C(k s) (1 - |kx|/N)(1 - |ky|/N) cos(2 pi f.k s); removing the
    sample mean leaves non-zero Fourier frequencies unchanged.
    """
    kx, ky, c = model.lattice_lags(pitch)
    weight = c * (1 - np.abs(kx) / n) * (1 - np.abs(ky) / n) * pitch**2
    gx = fx[mask] / 1000.0 * pitch  # cycles per sample
    gy = fy[mask] / 1000.0 * pitch
    out = np.zeros(gx.size)
    chunk = 20000
    for start in range(0, gx.size, chunk):
        phase = 2 * np.pi * (np.outer(gx[start : start + chunk], kx) + np.outer(gy[start : start + chunk], ky))
        out[start : start + chunk] = np.cos(phase) @ weight
    return out


def half_power_frequency(frequencies, spectrum, plateau):
    """First frequency where the spectrum falls to half the plateau (linear interpolation)."""
    below = np.nonzero(spectrum <= 0.5 * plateau)[0]
    if below.size == 0 or below[0] == 0:
        return None
    i = below[0]
    f0, f1 = frequencies[i - 1], frequencies[i]
    w0, w1 = spectrum[i - 1], spectrum[i]
    return float(f0 + (0.5 * plateau - w0) * (f1 - f0) / (w1 - w0))


def measure_spectrum(rng, boot_rng, model, fields, sigma_48, aperture_48):
    n = SPECTRUM_FIELD_SAMPLES
    pitch = SAMPLE_PITCH_UM
    to_density = (LOG10_E / model.open_fraction) ** 2  # W_D = (log10 e / q)^2 W_T
    fx, fy, radius, index = radial_bins(n, pitch)
    plateau_mask = (radius > 0) & (radius <= PLATEAU_MAX_CYCLES_PER_MM)

    profiles = np.empty((fields, SPECTRUM_BINS))
    plateaus = np.empty(fields)
    for field in range(fields):
        is_open, _, _ = open_field(rng, model, n, n, pitch)
        t = is_open.astype(np.float64)
        t -= t.mean()
        periodogram = np.abs(np.fft.fft2(t)) ** 2 * pitch**2 / n**2 * to_density
        profiles[field] = binned_mean(periodogram, index)
        plateaus[field] = periodogram[plateau_mask].mean()

    profile = profiles.mean(axis=0)
    profile_se = profiles.std(axis=0, ddof=1) / math.sqrt(fields)
    plateau = float(plateaus.mean())
    plateau_se = float(plateaus.std(ddof=1) / math.sqrt(fields))

    width = SPECTRUM_MAX_CYCLES_PER_MM / SPECTRUM_BINS
    centres = (np.arange(SPECTRUM_BINS) + 0.5) * width
    # Bin-averaged frequency, so the analytic curves compare like-for-like.
    keep = index >= 0
    mean_freq = np.bincount(index[keep], weights=radius[keep], minlength=SPECTRUM_BINS) / np.bincount(
        index[keep], minlength=SPECTRUM_BINS
    )

    analytic_mask = index >= 0
    expected = np.zeros_like(radius)
    expected[analytic_mask] = expected_periodogram(model, fx, fy, n, pitch, analytic_mask) * to_density
    analytic_lattice_profile = binned_mean(expected, index)
    expected_plateau = float(
        expected_periodogram(model, fx, fy, n, pitch, plateau_mask).mean() * to_density
    )
    continuous_profile = model.spectrum_continuous(mean_freq / 1000.0) * to_density
    w0_continuous = model.covariance_integral() * to_density
    kx, ky, c = model.lattice_lags(pitch)
    w0_lattice = float(c.sum() * pitch**2 * to_density)

    f50 = half_power_frequency(mean_freq, profile, plateau)
    f50_boot = []
    for _ in range(BOOTSTRAP_RESAMPLES):
        pick = boot_rng.integers(0, fields, fields)
        value = half_power_frequency(mean_freq, profiles[pick].mean(axis=0), plateaus[pick].mean())
        if value is not None:
            f50_boot.append(value)
    f50_se = float(np.std(f50_boot, ddof=1)) if len(f50_boot) > 1 else None

    selwyn = sigma_48["value"] ** 2 * aperture_48.area_um2
    selwyn_se = 2 * sigma_48["value"] * sigma_48["se"] * aperture_48.area_um2
    agreement, agreement_se = ratio_se(plateau, plateau_se, selwyn, selwyn_se)

    return {
        "fields": fields,
        "field_side_um": n * pitch,
        "sample_pitch_um": pitch,
        "units": "W in D^2 um^2 (linearized density, dD = -log10(e) dT / q); f in cycles/mm",
        "frequency_resolution_cycles_per_mm": 1000.0 / (n * pitch),
        "plateau_band_cycles_per_mm": [0.0, PLATEAU_MAX_CYCLES_PER_MM],
        "w0_simulated_plateau": estimate(plateau, plateau_se),
        "w0_plateau_analytic_lattice": expected_plateau,
        "w0_analytic_lattice": w0_lattice,
        "w0_analytic_continuous": w0_continuous,
        "sigma48_squared_times_area": estimate(selwyn, selwyn_se),
        "plateau_over_sigma48_squared_area": estimate(agreement, agreement_se),
        "half_power_frequency_cycles_per_mm": {
            "simulated": estimate(f50, f50_se),
            "analytic_lattice": half_power_frequency(mean_freq, analytic_lattice_profile, w0_lattice),
            "analytic_continuous": half_power_frequency(mean_freq, continuous_profile, w0_continuous),
        },
        "radial": {
            "bin_width_cycles_per_mm": width,
            "bin_centre_cycles_per_mm": centres.tolist(),
            "bin_mean_cycles_per_mm": mean_freq.tolist(),
            "w_simulated": profile.tolist(),
            "w_simulated_se": profile_se.tolist(),
            "w_analytic_lattice": analytic_lattice_profile.tolist(),
            "w_analytic_continuous": continuous_profile.tolist(),
        },
    }


# MARK: Driver


def seed_for(density_index, experiment):
    return np.random.default_rng(np.random.SeedSequence(BASE_SEED, spawn_key=(density_index, experiment)))


def run_density(density_index, target, settings, log):
    model = BooleanModel(target)
    boot_rng = seed_for(density_index, 99)
    started = time.time()

    circle = Aperture("circle", CIRCLE_DIAMETER_UM)
    a48 = measure_aperture(seed_for(density_index, 0), boot_rng, model, circle, settings["placements"])
    sigma_48 = a48["sigma_d_linearized"]
    log(f"  D={target}: 48 um done ({time.time() - started:.0f} s)")

    pixels = []
    for p_index, (side, count) in enumerate(zip(PIXEL_SIDES_UM, PIXEL_COUNTS)):
        result = measure_aperture(
            seed_for(density_index, 1 + p_index), boot_rng, model, Aperture("square", side), settings["placements"]
        )
        selwyn_prediction = sigma_48["value"] * math.sqrt(circle.area_um2) / side
        selwyn_prediction_se = sigma_48["se"] * math.sqrt(circle.area_um2) / side
        sigma = result["sigma_d_linearized"]
        ratio, ratio_err = ratio_se(sigma["value"], sigma["se"], selwyn_prediction, selwyn_prediction_se)
        analytic_ratio = (
            result["sigma_d_analytic_continuous"]
            * side
            / (a48["sigma_d_analytic_continuous"] * math.sqrt(circle.area_um2))
        )
        result.update(
            {
                "side_um": side,
                "pixel_count_across_frame": count,
                "exact_pitch_um": FRAME_WIDTH_MM * 1000.0 / count,
                "selwyn_prediction": estimate(selwyn_prediction, selwyn_prediction_se),
                "ratio_to_selwyn": estimate(ratio, ratio_err),
                "ratio_to_selwyn_analytic_continuous": analytic_ratio,
                "selwyn_within_5_percent": abs(ratio - 1) <= SELWYN_TOLERANCE,
            }
        )
        pixels.append(result)
    log(f"  D={target}: pixels done ({time.time() - started:.0f} s)")

    spectrum = measure_spectrum(
        seed_for(density_index, 50), boot_rng, model, settings["spectrum_fields"], sigma_48, circle
    )
    log(f"  D={target}: spectrum done ({time.time() - started:.0f} s)")

    return {
        "target_density": target,
        "lambda_per_um2": model.lam,
        "covered_fraction": 1 - model.open_fraction,
        "open_fraction_q": model.open_fraction,
        "lambda_times_grain_area": model.lam * model.grain_area,
        "aperture_48um": a48,
        "pixels": pixels,
        "spectrum": spectrum,
        "nutting_over_boolean_variance_large_aperture": (
            LOG10_E * model.grain_area * model.density / (model.covariance_integral() * (LOG10_E / model.open_fraction) ** 2)
        ),
    }


def lattice_bias(model):
    """Ratio of the lattice sum s^2 sum C(ks) to the integral of C (large-aperture variance)."""
    _, _, c = model.lattice_lags(SAMPLE_PITCH_UM)
    return float(c.sum() * SAMPLE_PITCH_UM**2 / model.covariance_integral())


def round_floats(value):
    if isinstance(value, float):
        return float(f"{value:.{SIGNIFICANT_DIGITS}g}")
    if isinstance(value, dict):
        return {k: round_floats(v) for k, v in value.items()}
    if isinstance(value, list):
        return [round_floats(v) for v in value]
    return value


def build_reference(quick, log=print):
    settings = QUICK if quick else FULL
    densities = []
    for i, target in enumerate(TARGET_DENSITIES):
        densities.append(run_density(i, target, settings, log))
    return round_floats(
        {
            "version": VERSION,
            "what": (
                "Boolean-model grain reference (opaque disks, Poisson centres). Test reference for the "
                "engine's aperture scaling, density-domain statistics and spectrum; not a claim about any "
                "real film stock."
            ),
            "model": "Newson, Delon, Galerne, Computer Graphics Forum 36(8), 2017 (clean-room, from the paper's description)",
            "quick": quick,
            "parameters": {
                "grain_radius_um": GRAIN_RADIUS_UM,
                "grain_radius_note": "arbitrary test value, not a film measurement",
                "grain_area_um2": GRAIN_AREA_UM2,
                "target_densities": list(TARGET_DENSITIES),
                "sample_pitch_um": SAMPLE_PITCH_UM,
                "circle_diameter_um": CIRCLE_DIAMETER_UM,
                "pixel_sides_um": list(PIXEL_SIDES_UM),
                "frame_width_mm": FRAME_WIDTH_MM,
                "pixel_counts": list(PIXEL_COUNTS),
                "aperture_gap_um": APERTURE_GAP_UM,
                "placements_min": settings["placements"],
                "bootstrap_resamples": BOOTSTRAP_RESAMPLES,
            },
            "seeds": {
                "base_seed": BASE_SEED,
                "scheme": "numpy SeedSequence(base_seed, spawn_key=(density_index, experiment)); experiment 0 = 48 um, 1..5 = pixels, 50 = spectrum, 99 = bootstrap",
                "numpy_version": np.__version__,
            },
            "definitions": {
                "sigma_d_linearized": "log10(e) * std(mean transmittance over aperture) / q, q = exp(-lambda a)",
                "sigma_d_log_readout": "std(-log10(mean transmittance over aperture)); null if any aperture is fully covered",
                "sigma_d_analytic_lattice": "exact model value for the 0.1 um point-sampled aperture mean (what is simulated)",
                "sigma_d_analytic_continuous": "exact model value for the continuous aperture integral",
                "nutting": "D = log10(e) a N / |A|, N = Poisson count of centres in the aperture; exact sigma^2 = log10(e) a D / |A|",
                "selwyn_prediction": "sigma_48 * sqrt(pi 24^2) / p",
                "covariance": "C(h) = q^2 (exp(lambda gamma(h)) - 1), gamma = disk overlap area",
            },
            "sampling_error": {
                "method": "coverage indicator point-sampled exactly at 0.1 um; aperture means are midpoint lattice sums",
                "large_aperture_variance_ratio_lattice_over_continuous": [
                    lattice_bias(BooleanModel(t)) for t in TARGET_DENSITIES
                ],
            },
            "densities": densities,
        }
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--out",
        type=pathlib.Path,
        default=pathlib.Path(__file__).resolve().parent / "grain-boolean-model.json",
    )
    parser.add_argument("--quick", action="store_true", help="fewer placements and spectrum fields")
    args = parser.parse_args()
    started = time.time()
    reference = build_reference(args.quick)
    args.out.write_text(json.dumps(reference, indent=1) + "\n")
    print(f"wrote {args.out} in {time.time() - started:.0f} s")


if __name__ == "__main__":
    main()
