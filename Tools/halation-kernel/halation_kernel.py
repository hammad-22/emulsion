"""Halation point-spread function from base-reflection geometry, and its sum-of-Gaussians fit (MOV-32).

Single-bounce model, no backing: a point in the emulsion scatters light into the base
(Lambertian, index n, thickness t); the back surface reflects it with unpolarized Fresnel
reflectance below the critical angle and totally above it; it returns to the emulsion at
r = 2 t tan(theta). All radii are in units of t. Also tabulates the same profile behind an absorbing
undercoat of density d (light crosses it twice: x 10^(-2 d / cos theta)). See README.md for the derivation.

Offline tool only: nothing here ships. Run with:

    python3 -m venv .venv && .venv/bin/pip install -r Tools/halation-kernel/requirements.txt
    .venv/bin/python -I Tools/halation-kernel/halation_kernel.py

Deterministic (no random numbers); values in the JSON are rounded to 8 significant digits.
"""

import itertools
import json
import pathlib

import numpy as np

OUTPUT = pathlib.Path(__file__).resolve().parent / "halation-kernel.json"
# The engine's tests read the same document (Packages/EmulsionCore/Tests/EmulsionCoreTests/References).
TEST_REFERENCE = pathlib.Path(__file__).resolve().parents[2] / "Packages/EmulsionCore/Tests/EmulsionCoreTests/References/halation-kernel.json"
SIGNIFICANT_DIGITS = 8

BASE_INDEX = 1.48  # cellulose triacetate, textbook value; not stated on any film datasheet
BASE_THICKNESS_UM = 140.0  # typical triacetate camera-film base: an estimate, not a datasheet value

FIT_GRID = np.geomspace(0.05, 40.0, 400)  # r/t, where encircled energy is fitted
KERNEL_CHECK_GRID = np.concatenate([np.linspace(0.0, 10.0, 4001), np.geomspace(10.0, 1000.0, 2001)])  # final check
PENALTY_GRID = np.concatenate([np.linspace(0.0, 10.0, 501), np.geomspace(10.0, 1000.0, 201)])  # during fitting
LOG_SIGMA_MIN, LOG_SIGMA_MAX = np.log(1e-3), np.log(1e3)  # keeps sigma finite while searching
PROFILE_SAMPLES = np.round(np.concatenate([np.arange(0.0, 4.0, 0.1), np.arange(4.0, 10.0, 0.5), np.arange(10.0, 41.0, 5.0)]), 6)
ENCIRCLED_TABLE = [0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 5.0, 10.0, 20.0, 40.0, 100.0]
# The engine renders this fit (Renderer + Halation.swift). N = 4 fits better (max |dE| 0.038) but relies on two
# nearly equal blurs (sigma 0.65 t and 0.77 t, weights +0.61 / -1.00) cancelling, which low-resolution blurs cannot
# reproduce; N = 3 keeps the negative lobe on blurs a factor 1.3 apart.
ENGINE_FIT = ("one_negative", 3)
ENGINE_FIT_REASON = (
    "engine choice: N = 3 with one negative weight, max |dE| <= 0.07; the N = 4 fit relies on two nearly equal "
    "blurs cancelling (irradiance: sigma 0.65 t and 0.77 t), which low-resolution blurs cannot reproduce"
)
GAUSS_NODES = 96
# Engineering bound, not physics: |negative weight| <= 1 (sum |w| <= 3). Without it the optimizer builds
# near-cancelling pairs (e.g. +6.9 / -7.3 at sigma 0.71 t / 0.72 t) that approximate Gaussian blurs cannot reproduce.
MAX_NEGATIVE_WEIGHT = 1.0

# Absorption weighting of the returned light, h(r) ~ R cos^(3+m) theta.
# m = 1: irradiance on the emulsion plane (= exposure if the layer absorbs all of it). Primary.
# m = 0: exposure of a thin, weakly absorbing layer (path length sec(theta) adds 1/cos). Sensitivity check.
ABSORPTION_MODELS = {"irradiance": 1, "thin_absorber": 0}
PRIMARY_MODEL = "irradiance"
UNDERCOAT_DENSITIES = [0.0, 0.5, 1.0, 2.0]  # normal-incidence optical density; 0 = no backing (reference)


def fresnel_reflectance(sin_theta, n):
    """Unpolarized Fresnel reflectance from inside a medium of index n into air; 1 beyond the critical angle."""
    sin_theta = np.asarray(sin_theta, dtype=float)
    cos_i = np.sqrt(np.clip(1.0 - sin_theta**2, 0.0, 1.0))
    sin_t_sq = (n * sin_theta) ** 2
    cos_t = np.sqrt(np.clip(1.0 - sin_t_sq, 0.0, 1.0))
    rs = (n * cos_i - cos_t) / (n * cos_i + cos_t)
    rp = (cos_i - n * cos_t) / (cos_i + n * cos_t)
    return np.where(sin_t_sq >= 1.0, 1.0, 0.5 * (rs**2 + rp**2))


def undercoat_transmittance(cos_theta, density):
    """An absorbing layer of normal-incidence optical density d, crossed twice at angle theta: 10^(-2 d / cos theta)."""
    return 10.0 ** (-2.0 * density / np.asarray(cos_theta, dtype=float))


class Profile:
    """Exact radial PSF for one absorption weighting (and optional undercoat density), normalized to unit volume.

    Energy integrals are in s = sin^2 theta, where the integrand is R(s) (1 - s)^a T(s), a = (m - 1) / 2.
    """

    def __init__(self, n, m, undercoat_density=0.0):
        self.n, self.m, self.density = n, m, undercoat_density
        self.sin2_c = 1.0 / n**2
        self.cos_c = np.sqrt(1.0 - self.sin2_c)
        self.exponent = (m - 1) / 2
        self.nodes, self.weights = np.polynomial.legendre.leggauss(GAUSS_NODES)
        self.fresnel_total = self._fresnel_part(np.array([0.0]))[0]
        self.tir_total = self._tir_part(np.array([1.0]))[0]
        self.returned = self.fresnel_total + self.tir_total  # per unit light entering the base

    def _quadrature(self, low, high, integrand):
        low, high = np.asarray(low, dtype=float), np.asarray(high, dtype=float)
        half = (high - low) / 2.0
        x = low[:, None] + half[:, None] * (self.nodes[None, :] + 1.0)
        return half * (integrand(x) * self.weights[None, :]).sum(axis=1)

    def _fresnel_part(self, c_low):
        """Integral from s = 0 to s(c_low), in c = cos(theta_transmitted) = sqrt(1 - n^2 s).

        The substitution removes the square-root singularity of R at the critical angle.
        """

        def integrand(c):
            s = (1.0 - c**2) / self.n**2
            cos_theta = np.sqrt(1.0 - s)
            weight = fresnel_reflectance(np.sqrt(s), self.n) * cos_theta ** (2 * self.exponent)
            return weight * undercoat_transmittance(cos_theta, self.density) * 2.0 * c / self.n**2

        return self._quadrature(c_low, np.ones_like(c_low), integrand)

    def _tir_part(self, s):
        """Integral from s_c to s, in k = cos(theta): ds = -2 k dk, so the integrand is 2 k^(2a+1) T(k)."""
        k_low = np.sqrt(1.0 - np.asarray(s, dtype=float))
        integrand = lambda k: 2.0 * k ** (2 * self.exponent + 1) * undercoat_transmittance(k, self.density)
        return self._quadrature(k_low, np.full_like(k_low, self.cos_c), integrand)

    @staticmethod
    def sin2_at(r):
        u2 = (np.asarray(r, dtype=float) / 2.0) ** 2
        return u2 / (1.0 + u2)

    def h(self, r):
        """Normalized PSF h(r) t^2 = R cos^(3+m) theta T(theta) / (4 pi) / returned."""
        s = self.sin2_at(r)
        cos_theta = np.sqrt(1.0 - s)
        shape = fresnel_reflectance(np.sqrt(s), self.n) * cos_theta ** (3 + self.m) * undercoat_transmittance(cos_theta, self.density)
        return shape / (4.0 * np.pi) / self.returned

    def encircled(self, r):
        """Fraction of the returned energy inside radius r (exact, to quadrature precision)."""
        s = self.sin2_at(np.atleast_1d(r))
        inner = s < self.sin2_c
        out = np.empty_like(s)
        out[inner] = self._fresnel_part(np.sqrt(np.clip(1.0 - self.n**2 * s[inner], 0.0, 1.0)))
        out[~inner] = self.fresnel_total + self._tir_part(s[~inner])
        return out / self.returned


def gaussian_encircled(r, sigmas):
    return 1.0 - np.exp(-(np.asarray(r)[:, None] ** 2) / (2.0 * np.asarray(sigmas)[None, :] ** 2))


def gaussian_kernel(r, weights, sigmas):
    sig = np.asarray(sigmas)[None, :]
    return (np.asarray(weights)[None, :] * np.exp(-(np.asarray(r)[:, None] ** 2) / (2.0 * sig**2)) / (2.0 * np.pi * sig**2)).sum(axis=1)


def constrained_lstsq(a, b):
    """min |a w - b|^2 subject to sum(w) = 1."""
    k = a.shape[1]
    kkt = np.zeros((k + 1, k + 1))
    kkt[:k, :k] = a.T @ a
    kkt[:k, k] = kkt[k, :k] = 1.0
    rhs = np.concatenate([a.T @ b, [1.0]])
    solution = np.linalg.lstsq(kkt, rhs, rcond=None)[0]
    return solution[:k]


def positive_weights(a, b):
    """Nonnegative weights summing to 1, by enumerating active sets (N <= 4, so 15 subsets)."""
    k = a.shape[1]
    best, best_sse = None, np.inf
    for size in range(1, k + 1):
        for subset in itertools.combinations(range(k), size):
            w_sub = constrained_lstsq(a[:, subset], b)
            if np.any(w_sub < 0.0):
                continue
            w = np.zeros(k)
            w[list(subset)] = w_sub
            sse = float(np.sum((a @ w - b) ** 2))
            if sse < best_sse:
                best, best_sse = w, sse
    return best, best_sse


def minimize(f, x0):
    """Nelder-Mead restarted with shrinking steps until it stops improving."""
    x, value = nelder_mead(f, x0)
    for step in (0.1, 0.03, 0.1, 0.01, 0.03, 0.003):
        x_new, value_new = nelder_mead(f, x, step=step)
        if value_new < value:
            x, value = x_new, value_new
    return x, value


def nelder_mead(f, x0, step=0.3, iterations=4000, tolerance=1e-14):
    """Deterministic Nelder-Mead (standard coefficients)."""
    dim = len(x0)
    simplex = [np.array(x0, dtype=float)]
    for i in range(dim):
        vertex = np.array(x0, dtype=float)
        vertex[i] += step
        simplex.append(vertex)
    values = [f(v) for v in simplex]
    for _ in range(iterations):
        order = np.argsort(values, kind="stable")
        simplex = [simplex[i] for i in order]
        values = [values[i] for i in order]
        if abs(values[-1] - values[0]) <= tolerance * (abs(values[0]) + 1e-30):
            break
        centroid = np.mean(simplex[:-1], axis=0)
        reflected = centroid + (centroid - simplex[-1])
        fr = f(reflected)
        if fr < values[0]:
            expanded = centroid + 2.0 * (centroid - simplex[-1])
            fe = f(expanded)
            simplex[-1], values[-1] = (expanded, fe) if fe < fr else (reflected, fr)
        elif fr < values[-2]:
            simplex[-1], values[-1] = reflected, fr
        else:
            contracted = centroid + 0.5 * (simplex[-1] - centroid)
            fc = f(contracted)
            if fc < values[-1]:
                simplex[-1], values[-1] = contracted, fc
            else:
                for i in range(1, len(simplex)):
                    simplex[i] = simplex[0] + 0.5 * (simplex[i] - simplex[0])
                    values[i] = f(simplex[i])
    best = int(np.argmin(values))
    return simplex[best], values[best]


def kernel_violation(weights, sigmas, grid=KERNEL_CHECK_GRID):
    """Sum of squared negative kernel values (h t^2) on a grid, the far-field sign, and the negative-weight bound."""
    values = gaussian_kernel(grid, weights, sigmas)
    far_field = weights[int(np.argmax(sigmas))]
    excess = max(-float(np.min(weights)) - MAX_NEGATIVE_WEIGHT, 0.0)
    return float(np.sum(np.minimum(values, 0.0) ** 2)) + (far_field < 0.0) * far_field**2 + excess**2


def repair_negative_lobe(weights, sigmas):
    """Shrink the negative weight (rescaling the positive ones to keep the sum at 1) until every constraint holds."""
    weights = np.array(weights, dtype=float)
    negative = weights < 0.0
    if not negative.any() or kernel_violation(weights, sigmas) == 0.0:
        return weights

    def scaled(shrink):
        w = weights.copy()
        w[negative] *= shrink
        w[~negative] *= (1.0 - w[negative].sum()) / weights[~negative].sum()
        return w

    low, high = 0.0, 1.0  # scaled(low) is all-positive, so feasible
    for _ in range(60):
        mid = 0.5 * (low + high)
        low, high = (mid, high) if kernel_violation(scaled(mid), sigmas) == 0.0 else (low, mid)
    return scaled(low)


def start_sigmas(count):
    """Deterministic starting log-sigmas: every combination from a fixed ladder."""
    ladder = np.log([0.3, 0.7, 1.2, 1.8, 3.0, 6.0, 15.0])
    return [np.array(c) for c in itertools.combinations(ladder, count)]


def fit_positive(profile, count):
    target = profile.encircled(FIT_GRID)

    def objective(log_sigmas):
        a = gaussian_encircled(FIT_GRID, np.exp(np.clip(log_sigmas, LOG_SIGMA_MIN, LOG_SIGMA_MAX)))
        _, sse = positive_weights(a, target)
        return sse

    best = None
    for start in start_sigmas(count):
        x, value = minimize(objective, start)
        if best is None or value < best[1]:
            best = (x, value)
    sigmas = np.exp(np.clip(best[0], LOG_SIGMA_MIN, LOG_SIGMA_MAX))
    weights, _ = positive_weights(gaussian_encircled(FIT_GRID, sigmas), target)
    return weights, sigmas


def fit_signed(profile, count, positive_fit):
    """At most one negative weight, kernel >= 0 everywhere. Full-parameter Nelder-Mead with a penalty, then repair."""
    target = profile.encircled(FIT_GRID)

    def unpack(x):
        sigmas = np.exp(np.clip(x[:count], LOG_SIGMA_MIN, LOG_SIGMA_MAX))
        weights = np.append(x[count:], 1.0 - np.sum(x[count:]))
        return weights, sigmas

    def objective(x):
        weights, sigmas = unpack(x)
        sse = float(np.sum((gaussian_encircled(FIT_GRID, sigmas) @ weights - target) ** 2))
        extra_negatives = max(int(np.sum(weights < 0.0)) - 1, 0)
        return sse + 1e4 * kernel_violation(weights, sigmas, PENALTY_GRID) + extra_negatives * (1.0 + float(np.sum(np.minimum(weights, 0.0) ** 2)))

    starts = []
    for log_sigmas in start_sigmas(count):
        w = constrained_lstsq(gaussian_encircled(FIT_GRID, np.exp(log_sigmas)), target)
        starts.append(np.concatenate([log_sigmas, w[:-1]]))
    weights, sigmas = positive_fit
    starts.append(np.concatenate([np.log(sigmas), weights[:-1]]))

    best = None
    for start in starts:
        x, value = minimize(objective, start)
        if best is None or value < best[1]:
            best = (x, value)
    weights, sigmas = unpack(best[0])
    return repair_negative_lobe(weights, sigmas), sigmas


def ring_radius(r_grid, h_values):
    return float(r_grid[int(np.argmax(r_grid * h_values))])


def describe_fit(profile, weights, sigmas, kind):
    order = np.argsort(sigmas)
    weights, sigmas = np.asarray(weights)[order], np.asarray(sigmas)[order]
    dense = np.linspace(1e-4, 40.0, 400001)
    delta = gaussian_encircled(FIT_GRID, sigmas) @ weights - profile.encircled(FIT_GRID)
    kernel = gaussian_kernel(KERNEL_CHECK_GRID, weights, sigmas)
    return {
        "kind": kind,
        "count": len(sigmas),
        "weights": weights.tolist(),
        "sigmas_t": sigmas.tolist(),
        "sigmas_um_at_140um": (sigmas * BASE_THICKNESS_UM).tolist(),
        "max_abs_delta_encircled": float(np.max(np.abs(delta))),
        "rms_delta_encircled": float(np.sqrt(np.mean(delta**2))),
        "ring_radius_t": ring_radius(dense, gaussian_kernel(dense, weights, sigmas)),
        "centre_h_t2": float(gaussian_kernel(np.array([0.0]), weights, sigmas)[0]),
        "min_kernel_h_t2": float(kernel.min()),
        "sum_abs_weights": float(np.sum(np.abs(weights))),
    }


def recommend(candidates):
    """The fit the engine renders (ENGINE_FIT); every candidate stays listed for comparison."""
    chosen = next(c for c in candidates if (c["kind"], c["count"]) == ENGINE_FIT)
    return chosen, ENGINE_FIT_REASON


def analyse(name, m):
    profile = Profile(BASE_INDEX, m)
    check_normalization(profile)
    candidates = []
    for count in (2, 3, 4):
        positive = fit_positive(profile, count)
        candidates.append(describe_fit(profile, *positive, "positive"))
        candidates.append(describe_fit(profile, *fit_signed(profile, count, positive), "one_negative"))
    chosen, reason = recommend(candidates)
    r_c = 2.0 * np.tan(np.arcsin(1.0 / BASE_INDEX))
    return {
        "absorption_model": name,
        "h_formula": f"h(r) t^2 = R(theta) cos^{3 + m}(theta) / (4 pi F_model), tan(theta) = r / (2 t)",
        "returned_fraction": profile.returned if m == 1 else None,
        "model_normalization_F": profile.returned,
        "exact_ring_radius_t": float(r_c),
        "profile": {
            "r_t": PROFILE_SAMPLES.tolist(),
            "h_t2": profile.h(PROFILE_SAMPLES).tolist(),
            "encircled": profile.encircled(PROFILE_SAMPLES).tolist(),
        },
        "encircled_table": {f"{r:g}": float(profile.encircled(np.array([r]))[0]) for r in ENCIRCLED_TABLE},
        "candidates": candidates,
        "recommended": {**chosen, "reason": reason},
    }


def check_normalization(profile):
    """Independent check: integrate h 2 pi r dr by the midpoint rule over theta (r = 2 tan theta)."""
    theta = (np.arange(400000) + 0.5) * (np.pi / 2) / 400000
    r = 2.0 * np.tan(theta)
    total = float(np.sum(profile.h(r) * 2.0 * np.pi * r * 2.0 / np.cos(theta) ** 2) * (np.pi / 2) / 400000)
    assert abs(total - 1.0) < 1e-4, f"PSF volume {total}, expected 1"
    encircled = profile.encircled(FIT_GRID)
    assert np.all(np.diff(encircled) >= -1e-12), "encircled energy must not decrease"


def radius_at_encircled(profile, fraction):
    low, high = 0.0, 1e4
    for _ in range(100):
        mid = 0.5 * (low + high)
        low, high = (mid, high) if profile.encircled(np.array([mid]))[0] < fraction else (low, mid)
    return 0.5 * (low + high)


def analyse_undercoat():
    """Primary (irradiance) profile behind an absorbing undercoat of density d between emulsion and base."""
    reference = Profile(BASE_INDEX, ABSORPTION_MODELS[PRIMARY_MODEL])
    r_c = 2.0 * np.tan(np.arcsin(1.0 / BASE_INDEX))
    dense = np.linspace(1e-4, 40.0, 400001)
    rows = []
    for density in UNDERCOAT_DENSITIES:
        profile = Profile(BASE_INDEX, ABSORPTION_MODELS[PRIMARY_MODEL], density)
        check_normalization(profile)
        h_dense = profile.h(dense)
        rows.append(
            {
                "density": density,
                "returned_fraction": profile.returned,
                "surviving_relative_to_no_backing": profile.returned / reference.returned,
                "tir_share_of_returned": profile.tir_total / profile.returned,
                "ring_radius_t": ring_radius(dense, h_dense),
                "centre_to_ring_h_ratio": float(profile.h(np.array([0.0]))[0] / profile.h(np.array([r_c]))[0]),
                "encircled_at_rc": float(profile.encircled(np.array([r_c]))[0]),
                "r50_t": radius_at_encircled(profile, 0.5),
                "r90_t": radius_at_encircled(profile, 0.9),
                "encircled_table": {f"{r:g}": float(profile.encircled(np.array([r]))[0]) for r in ENCIRCLED_TABLE},
                "profile": {"r_t": PROFILE_SAMPLES.tolist(), "h_t2": profile.h(PROFILE_SAMPLES).tolist(), "encircled": profile.encircled(PROFILE_SAMPLES).tolist()},
            }
        )
    return {
        "description": "Irradiance model times 10^(-2 d / cos theta): an absorbing layer of normal-incidence density d between emulsion and base, crossed twice. Each profile is renormalized to unit volume; returned_fraction is per unit light entering the absorber.",
        "rows": rows,
    }


def rounded(value):
    if isinstance(value, float):
        return float(f"{value:.{SIGNIFICANT_DIGITS}g}")
    if isinstance(value, dict):
        return {k: rounded(v) for k, v in value.items()}
    if isinstance(value, list):
        return [rounded(v) for v in value]
    return value


def print_undercoat(undercoat):
    print("\n== undercoat (irradiance model x 10^(-2d/cos theta)), each profile renormalized")
    print(f"{'d':>4}{'returned':>10}{'vs none':>10}{'TIR share':>10}{'ring/t':>8}{'h0/h(rc)':>10}{'E(rc)':>8}{'r50/t':>8}{'r90/t':>8}")
    for row in undercoat["rows"]:
        print(
            f"{row['density']:>4g}{row['returned_fraction']:>10.3e}{row['surviving_relative_to_no_backing']:>10.3e}{row['tir_share_of_returned']:>10.4f}"
            f"{row['ring_radius_t']:>8.3f}{row['centre_to_ring_h_ratio']:>10.4f}{row['encircled_at_rc']:>8.4f}{row['r50_t']:>8.3f}{row['r90_t']:>8.3f}"
        )
        print("     E(r/t): " + "  ".join(f"{k}:{v:.4f}" for k, v in row["encircled_table"].items()))


def print_report(geometry, results):
    print(f"n = {BASE_INDEX}  theta_c = {geometry['critical_angle_deg']:.4f} deg  r_c/t = {geometry['critical_radius_t']:.5f}")
    print(f"returned fraction F = {geometry['returned_fraction']:.5f}  (TIR {geometry['tir_fraction']:.5f} + Fresnel {geometry['fresnel_fraction']:.5f})")
    print(f"normal-incidence R = {geometry['normal_reflectance']:.5f};  at t = {BASE_THICKNESS_UM:g} um, r_c = {geometry['critical_radius_t'] * BASE_THICKNESS_UM:.1f} um")
    for result in results:
        print(f"\n== {result['absorption_model']}: {result['h_formula']}")
        print("encircled energy E(r/t): " + "  ".join(f"{k}:{v:.4f}" for k, v in result["encircled_table"].items()))
        print(f"{'kind':<13}{'N':>2}  {'weights':<38}{'sigma/t':<34}{'sigma um@140':<34}{'max|dE|':>8}{'ring/t':>8}")
        for c in result["candidates"]:
            w = " ".join(f"{x:+.4f}" for x in c["weights"])
            s = " ".join(f"{x:.4f}" for x in c["sigmas_t"])
            um = " ".join(f"{x:.1f}" for x in c["sigmas_um_at_140um"])
            print(f"{c['kind']:<13}{c['count']:>2}  {w:<38}{s:<34}{um:<34}{c['max_abs_delta_encircled']:>8.4f}{c['ring_radius_t']:>8.3f}")
        rec = result["recommended"]
        print(f"exact ring radius {result['exact_ring_radius_t']:.3f} t; recommended: {rec['kind']} N={rec['count']} ({rec['reason']})")


def main():
    theta_c = np.arcsin(1.0 / BASE_INDEX)
    primary = Profile(BASE_INDEX, ABSORPTION_MODELS[PRIMARY_MODEL])
    geometry = {
        "base_index": BASE_INDEX,
        "base_index_source": "cellulose triacetate, textbook value; not from a film datasheet",
        "base_thickness_um_example": BASE_THICKNESS_UM,
        "base_thickness_source": "typical triacetate camera-film base, estimate; VISION3 sheets do not state it",
        "critical_angle_deg": float(np.degrees(theta_c)),
        "critical_radius_t": float(2.0 * np.tan(theta_c)),
        "critical_radius_um_at_140um": float(2.0 * np.tan(theta_c) * BASE_THICKNESS_UM),
        "normal_reflectance": float(fresnel_reflectance(0.0, BASE_INDEX)),
        "tir_fraction": float(1.0 - 1.0 / BASE_INDEX**2),
        "fresnel_fraction": float(primary.fresnel_total),
        "returned_fraction": float(primary.returned),
        "returned_fraction_formula": "F = integral_0^(pi/2) R(theta) 2 cos(theta) sin(theta) dtheta",
    }
    results = [analyse(name, m) for name, m in ABSORPTION_MODELS.items()]
    undercoat = analyse_undercoat()
    print_report(geometry, results)
    print_undercoat(undercoat)
    document = {
        "description": "Halation PSF of an unbacked base (single bounce), normalized to unit volume; radii in units of base thickness t. Generated by Tools/halation-kernel/halation_kernel.py.",
        "geometry": geometry,
        "primary_model": PRIMARY_MODEL,
        "models": results,
        "recommended": results[0]["recommended"],
        "undercoat": undercoat,
    }
    text = json.dumps(rounded(document), indent=2) + "\n"
    for path in (OUTPUT, TEST_REFERENCE):
        path.write_text(text)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
