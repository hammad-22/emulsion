"""Self-tests for boolean_grain_reference.py. Run: python -I test_boolean_grain_reference.py"""

import importlib.util
import math
import pathlib

import numpy as np

_path = pathlib.Path(__file__).resolve().parent / "boolean_grain_reference.py"
_spec = importlib.util.spec_from_file_location("boolean_grain_reference", _path)
ref = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ref)

PITCH = ref.SAMPLE_PITCH_UM


def test_rasterization_matches_brute_force():
    rng = np.random.default_rng(1)
    model = ref.BooleanModel(0.8)
    columns, rows = 120, 90
    x, y = ref.poisson_centres(rng, model.lam, columns * PITCH, rows * PITCH, model.radius)
    counts = ref.coverage_counts(x, y, model.radius, columns, rows, PITCH)
    px = (np.arange(columns) + 0.5) * PITCH
    py = (np.arange(rows) + 0.5) * PITCH
    d2 = (px[None, :, None] - x[None, None, :]) ** 2 + (py[:, None, None] - y[None, None, :]) ** 2
    brute = np.count_nonzero(d2 <= model.radius**2, axis=2)
    assert np.array_equal(counts, brute)


def test_overlap_area_integrates_to_grain_area_squared():
    # Integral of gamma(h) over the plane is a^2 (each disk's area times the other's).
    model = ref.BooleanModel(0.3)
    h, w = model._radial_nodes()
    integral = float(np.sum(w * 2 * np.pi * h * ref.lens_area(h, model.radius)))
    assert abs(integral / model.grain_area**2 - 1) < 1e-9


def test_mean_coverage_matches_poisson_law():
    # Covered fraction of the Boolean model: u = 1 - exp(-lambda pi r^2).
    rng = np.random.default_rng(2)
    side = 1000
    for target in ref.TARGET_DENSITIES:
        model = ref.BooleanModel(target)
        fields = [ref.open_field(rng, model, side, side, PITCH)[0].mean() for _ in range(4)]
        se = math.sqrt(model.transmittance_variance_lattice(np.ones((side, side), bool), PITCH) / 4)
        covered = 1 - float(np.mean(fields))
        expected = 1 - math.exp(-model.lam * math.pi * model.radius**2)
        assert abs(covered - expected) < 4 * se, (target, covered, expected, se)


def test_nutting_variance_is_exact():
    # D = 0.434 a N / |A| with Poisson N: sigma_D^2 = 0.434 a D / |A| exactly.
    rng = np.random.default_rng(3)
    model = ref.BooleanModel(1.5)
    aperture = ref.Aperture("square", 9.7)
    _, counts = aperture.measure(rng, model, 3000)
    density = ref.LOG10_E * model.grain_area * counts / aperture.area_um2
    expected = ref.LOG10_E * model.grain_area * model.density / aperture.area_um2
    measured = density.var(ddof=1)
    se = expected * math.sqrt(2 / (density.size - 1))
    assert abs(measured - expected) < 4 * se, (measured, expected, se)
    assert abs(density.mean() / model.density - 1) < 0.01


def test_lattice_and_continuous_variance_agree_for_large_apertures():
    model = ref.BooleanModel(0.8)
    aperture = ref.Aperture("square", 15.6)
    lattice = model.transmittance_variance_lattice(aperture.mask, PITCH)
    continuous = model.transmittance_variance_square(15.6)
    assert abs(lattice / continuous - 1) < 0.01


if __name__ == "__main__":
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
        print(f"ok  {test.__name__}")
    print(f"{len(tests)} passed")
