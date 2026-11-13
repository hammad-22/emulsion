"""Generate SSIM reference values for the Swift `StructuralSimilarity` tests (MOV-146).

The planes are defined by formulas that `StructuralSimilarityTests` rebuilds, so only the scores are
stored. scikit-image's `structural_similarity` is the independent implementation, configured as
Wang et al. (2004): Gaussian window σ 1.5 (11 taps), K1 0.01, K2 0.03, population covariance, and
the mean taken over pixels whose window lies inside the image.

Run: .venv/bin/python -I Tools/color-references/generate_ssim_references.py
"""

import json
import pathlib

import numpy as np
import skimage
from skimage.metrics import structural_similarity

WIDTH, HEIGHT = 48, 40
DATA_RANGE = 100.0

OUTPUT = pathlib.Path(__file__).resolve().parents[2] / (
    "Packages/EmulsionCore/Tests/EmulsionCoreTests/References/ssim.json"
)


def base(i, j):
    """L*-like plane: smooth waves plus a deterministic texture."""
    return 50 + 25 * np.sin(0.3 * i) * np.cos(0.2 * j) + 10 * (((7 * i + 13 * j) % 11) / 11)


VARIANTS = {
    "identical": lambda i, j: base(i, j),
    "contrast and offset": lambda i, j: 0.9 * base(i, j) + 5,
    "added pattern": lambda i, j: base(i, j) + 8 * np.sin(1.7 * i + 0.9 * j),
    "flattened": lambda i, j: 0 * base(i, j) + 50,
    "texture removed": lambda i, j: 50 + 25 * np.sin(0.3 * i) * np.cos(0.2 * j) + 5,
}


def main():
    j, i = np.meshgrid(np.arange(WIDTH, dtype=np.float64), np.arange(HEIGHT, dtype=np.float64))
    x = base(i, j)
    cases = []
    for name, variant in VARIANTS.items():
        y = variant(i, j)
        score = structural_similarity(
            x, y, data_range=DATA_RANGE, gaussian_weights=True, sigma=1.5, use_sample_covariance=False,
            K1=0.01, K2=0.03,
        )
        cases.append({"name": name, "ssim": float(score)})
    document = {
        "source": f"scikit-image {skimage.__version__} structural_similarity (Wang et al. 2004 settings), "
        f"{WIDTH}x{HEIGHT} planes defined in generate_ssim_references.py",
        "width": WIDTH,
        "height": HEIGHT,
        "cases": cases,
    }
    OUTPUT.write_text(json.dumps(document, indent=1) + "\n")
    print(json.dumps(document, indent=1))


if __name__ == "__main__":
    main()
