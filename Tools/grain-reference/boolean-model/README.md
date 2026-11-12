# Boolean-model grain reference

An offline ground-truth simulator for film grain as the **Boolean model** of stochastic geometry: opaque disks of radius r whose centres form a homogeneous Poisson process of intensity λ (grains per µm²). It produces `grain-boolean-model.json`, a test reference for the engine's **aperture scaling (Selwyn's law), density-domain statistics and noise spectrum**.

What it is **not**: a claim about any real film stock. r = 0.5 µm and the three densities (0.3, 0.8, 1.5) are arbitrary test values. Real negatives are dye clouds in several layers, not opaque silver disks (`docs/FILM-THEORY.md` §6.2).

## Clean room and licence
- The model follows the published description in A. Newson, J. Delon, B. Galerne, "A Stochastic Film Grain Model for Resolution-Independent Rendering", *Computer Graphics Forum* 36(8), 2017. Their reference code is GPL. It was **not** opened, read or copied, and neither was any derivative.
- The closed-form statistics below are classical stochastic geometry, derived here. No patented real-time rendering method is used (for example Zhang–Pappas 2023).
- This code is Apache-2.0 like the repository. The only dependency is NumPy (BSD-3-Clause).

## Analytic model (derived)
Let `a = π r²` and `X` be the union of the disks. A point is uncovered when no centre lies within r of it. The number of centres in that disk is Poisson with mean λa, so

- open fraction `q = P(x ∉ X) = exp(−λa)`, and covered fraction `u = 1 − q`;
- diffuse density `D = −log10 q = log10(e)·λa`. This equals Nutting's `0.434·a·N/|A|` in the mean.

For two points h apart, both are uncovered when no centre lies in the union of the two r-disks. That union has area `2a − γ(h)`, where `γ(h) = 2r² acos(h/2r) − (h/2)·sqrt(4r² − h²)` is the overlap (lens) area. So `P = exp(−λ(2a − γ(h)))`, and the covariance of the transmittance T = 1 − 1_X is

    C(h) = q² (exp(λ γ(h)) − 1),   zero for h ≥ 2r.

- **Aperture variance.** `Var T̄_A = |A|⁻² ∫ C(h) g_A(h) dh`, where `g_A(h) = |A ∩ (A + h)|`.
  - Disk of radius R: g is the lens area with radius R.
  - Square of side p (with p ≥ 2r): the angular integral of `(p−|hx|)(p−|hy|)` is `2πp² − 8ph + 2h²`.
- **Density.** Linearize `δD = −log10(e)·δT/q`. Then `σ_D = log10(e)·σ_T/q` and `W_D = (log10(e)/q)² W_T`.
- **Wiener spectrum.** `W_T(f) = 2π ∫₀^{2r} h C(h) J0(2πfh) dh`.
  - `W_T(0) = ∫C`. For large apertures, `σ_T²·|A| → W_T(0)`, which is Selwyn's law.
  - The aperture correction is first order in r/p: `1 − 8⟨h⟩/(2πp)`. This is why Selwyn already fails by 7–9% in σ at p ≈ 6r (p = 3.1 µm).
- **Boolean vs Nutting.** `σ_D²|A| → log10(e)² ∫(e^{λγ} − 1)`, whereas Nutting gives `log10(e)² ∫λγ = log10(e)·a·D`. Since `e^x − 1 > x`, overlap makes the Boolean model grainier than Nutting, increasingly so with density.

## Simulation
- Poisson centres are generated in a window with an r margin.
- The coverage indicator is **point-sampled exactly** on a 0.1 µm lattice. Disks are rasterized as exact row runs, and the test checks this against brute force.
- Point samples have exactly the model's mean and covariance. The only approximation is that aperture means are lattice sums. Their exact expectation is computed (`*_analytic_lattice`) next to the continuous integral (`*_analytic_continuous`). For large apertures the variance bias is +0.06%, +0.14% and +0.41% at D = 0.3, 0.8 and 1.5.
- Apertures sit in cells 1 µm (one grain diameter) apart, so each placement is independent.
- Standard errors:
  - σ: bootstrap over placements (1000 resamples).
  - Spectrum: spread over independent fields.
- Seeds come from `SeedSequence(20171108, spawn_key=(density, experiment))`. Output is deterministic for a given NumPy version.

## Run
```bash
python3 -m venv .venv && .venv/bin/pip install -r Tools/grain-reference/boolean-model/requirements.txt
.venv/bin/python -I Tools/grain-reference/boolean-model/boolean_grain_reference.py --out Tools/grain-reference/boolean-model/grain-boolean-model.json   # about 2 min
.venv/bin/python -I Tools/grain-reference/boolean-model/boolean_grain_reference.py --out /tmp/quick.json --quick                                   # about 10 s
.venv/bin/python -I Tools/grain-reference/boolean-model/test_boolean_grain_reference.py
```
The checked-in JSON was generated with the pinned NumPy 2.5.4 (regenerating with 2.4.2 gave identical digits). A different NumPy version may change Monte-Carlo digits within the stated standard errors. `Packages/EmulsionCore/Tests/EmulsionCoreTests/References/grain-boolean-model.json` is a copy for the engine tests: copy it again after regenerating.
