from pathlib import Path
from PIL import Image, ImageOps
import numpy as np
import os

INPUT_DIR = Path(__file__).parent / "inputs"
ROOT = Path(os.environ.get("TEMPEST_LEGACY_OUTPUT_ROOT", Path(__file__).parent)).expanduser()


def trim_alpha(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    # Keep the full raster. Clipboard images have only a very small plotting margin;
    # trimming by colour would also remove a real white phone background.
    return im.convert("RGB")


def dct_hash(im: Image.Image, n=32, k=12):
    a = np.asarray(ImageOps.fit(trim_alpha(im).convert("L"), (n, n), method=Image.Resampling.LANCZOS), dtype=float)
    x = np.arange(n)
    u = np.arange(k)[:, None]
    C = np.cos(np.pi * (2 * x + 1)[None, :] * u / (2 * n))
    d = C @ a @ C.T
    vals = d[:k, :k].ravel()[1:]
    return vals > np.median(vals)


def thumb(im: Image.Image, w=32, h=64):
    a = np.asarray(ImageOps.fit(trim_alpha(im), (w, h), method=Image.Resampling.LANCZOS), dtype=np.float32) / 255
    # Remove global colour/exposure but retain spatial structure.
    a = (a - a.mean((0, 1), keepdims=True)) / (a.std((0, 1), keepdims=True) + 1e-5)
    return a


inputs = []
for p in sorted(INPUT_DIR.glob("input_*.png")):
    with Image.open(p) as im:
        inputs.append((p.name, dct_hash(im), thumb(im), im.width / im.height))

best = {name: [] for name, *_ in inputs}
files = [p for p in ROOT.rglob("*") if p.suffix.lower() in {".png", ".jpg", ".jpeg"}]
for j, p in enumerate(files):
    try:
        with Image.open(p) as im:
            ratio = im.width / im.height
            # All supplied images are portrait. Allow a wide range because source
            # figures can have small margins or a native-resolution export.
            if not 0.32 <= ratio <= 0.72:
                continue
            h = dct_hash(im)
            t = thumb(im)
    except Exception:
        continue
    for name, ih, it, ir in inputs:
        ham = float(np.mean(h != ih))
        corr = float(np.mean(t * it))
        aspect_penalty = abs(np.log(ratio / ir))
        score = corr - 0.8 * ham - 0.15 * aspect_penalty
        row = (score, corr, ham, str(p))
        arr = best[name]
        arr.append(row)
        arr.sort(reverse=True)
        del arr[12:]

for name, rows in best.items():
    print(f"\n## {name}")
    for score, corr, ham, p in rows:
        print(f"{score: .4f} corr={corr: .4f} ham={ham:.3f} {p}")
