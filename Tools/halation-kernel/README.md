# Halation kernel (offline reference)

Derives the radial point-spread function (PSF) of halation from base-reflection geometry, fits it with a
small sum of 2D Gaussians the engine can render as Gaussian blurs, and tabulates how an absorbing
undercoat changes it (MOV-32, `docs/FILM-THEORY.md` §6.1). Offline tool only: nothing here ships.

```bash
python3 -m venv .venv && .venv/bin/pip install -r Tools/halation-kernel/requirements.txt
.venv/bin/python -I Tools/halation-kernel/halation_kernel.py   # prints the report, writes halation-kernel.json
```

It writes the same JSON to `Packages/EmulsionCore/Tests/EmulsionCoreTests/References/halation-kernel.json`, which
`HalationTests` reads.

Deterministic (no random numbers, fixed optimizer starts); takes about two minutes.

## Derivation (single bounce, no backing)

1. A point in the emulsion sends light into the base Lambertian: power per solid angle ∝ cos θ, so the share in
   dθ is 2 cos θ sin θ dθ = d(sin²θ) (integrates to 1 over 0..π/2).
2. A ray at θ reflects at the back of a base of thickness t, index n, and returns at r = 2t tan θ;
   dr = 2t sec²θ dθ.
3. Back-surface reflectance R(θ): unpolarized Fresnel, base → air, below θc = arcsin(1/n); 1 (TIR) above.
   R rises continuously to 1 at θc (with infinite slope), so the profile has a steep edge, not a jump.
4. Power per unit emulsion area: h(r) = R · 2 cos θ sin θ dθ / (2πr dr) = R(θ) cos⁴θ / (4π t²) per unit light
   entering the base. This is irradiance on the emulsion plane.
5. Returned fraction F = ∫ R 2 cos θ sin θ dθ; TIR part = 1 − 1/n². The script divides h by F so ∫ h 2πr dr = 1.
   Tail: the energy beyond r is 1/(1 + (r/2t)²) of the light entering the base, finite and analytic.
6. Absorption in the layer re-exposed: a layer of normal optical depth τ absorbs (1 − e^(−τ/cos θ)) of the
   irradiance, so exposure ∝ R cos⁴θ (1 − e^(−τ sec θ)). Opaque layer: cos⁴θ (the primary profile,
   `irradiance`). Thin, weakly absorbing layer: R cos³θ (one cos *fewer*, not more; `thin_absorber`, kept as a
   sensitivity check: its energy tail falls only as 1/r, so 6.5 % lies beyond 40 t).
7. Undercoat: an absorbing layer of normal-incidence density d between emulsion and base is crossed twice at θ,
   so h is multiplied by 10^(−2d/cos θ). Oblique (TIR) light is cut hardest, so energy moves inward.
8. Gaussian fit: unit-volume 2D Gaussians, weights summing to 1, least squares on encircled energy
   E(r) = Σ w_k (1 − e^(−r²/2σ_k²)) over 400 log-spaced r from 0.05 t to 40 t. Positive fits solve the weights
   exactly for each σ set (active-set enumeration); signed fits (one negative weight, kernel ≥ 0 everywhere,
   |negative weight| ≤ 1 as an engineering bound) use Nelder–Mead with a penalty and a final feasibility repair.

## Engine choice (`recommended`)

The engine renders the 3-Gaussian fit with one negative weight (irradiance model): weights −0.99817, +1.72709,
+0.27108 at σ = 1.3078 t, 1.7311 t, 6.1046 t; max |ΔE| 0.0615 in encircled energy, ring at 2.64 t (exact 1.83 t),
centre value ≈ 0. The N = 4 fit is closer (0.0384) but relies on two nearly equal blurs (σ 0.65 t and 0.77 t,
weights +0.61 / −1.00) cancelling, which low-resolution blurs cannot reproduce. All candidates stay in the JSON.

Geometry (n = 1.48): returned fraction F = 0.584 (TIR 0.543 + Fresnel 0.041), r_c = 1.833 t, 50% of the energy
within 3.11 t and 90% within 8.03 t. Undercoat d = 0.5 keeps 1.85% (r50 2.13 t, r90 3.18 t).

## Inputs

- n = 1.48: cellulose triacetate, textbook value. Not from any film datasheet.
- t = 140 µm (only for the µm columns): typical triacetate camera-film base, an estimate. Kodak's VISION3
  sheets do not state it. Everything else is in units of t.
- Not modelled: multiple bounces (the emulsion/air front surface also traps light by TIR), the emulsion's own
  thickness and scatter (only the fit's smoothness stands in for them), index mismatch at emulsion/base, and
  absorption in the base itself.
