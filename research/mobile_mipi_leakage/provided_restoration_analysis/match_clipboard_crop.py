from pathlib import Path
from PIL import Image
import numpy as np

ROOT = Path(__file__).resolve().parent
pairs = [
    (ROOT / "iphone6s" / "iphone6s_P001_Coherent_HSV_median_off.png", ROOT / "inputs" / "input_01.png"),
    (ROOT / "iphone6s" / "iphone6s_P200_Coherent_HSV_median_off.png", ROOT / "inputs" / "input_02.png"),
    (ROOT / "lgx2" / "lgx2_P001_Coherent_HSV_median_off.png", ROOT / "inputs" / "input_03.png"),
    (ROOT / "lgx2" / "lgx2_P200_Coherent_HSV_median_off.png", ROOT / "inputs" / "input_04.png"),
    (ROOT / "galaxy_s4_lte_111p9M" / "galaxy_s4_lte_111p9M_P001_Coherent_HSV_median_off.png", ROOT / "inputs" / "input_05.png"),
    (ROOT / "galaxy_s4_lte_111p9M" / "galaxy_s4_lte_111p9M_P200_Coherent_HSV_median_off.png", ROOT / "inputs" / "input_06.png"),
]


def standard(a):
    a = np.asarray(a, dtype=np.float32)
    a = (a - a.mean((0, 1), keepdims=True)) / (a.std((0, 1), keepdims=True) + 1e-6)
    return a


for src_path, target_path in pairs:
    src = Image.open(src_path).convert("RGB")
    target = Image.open(target_path).convert("RGB")
    # Test full frame and all horizontal crops that reproduce the clipboard aspect.
    candidates = []
    widths = sorted(set([src.width, round(src.height * target.width / target.height)]))
    for crop_w in widths:
        crop_w = min(crop_w, src.width)
        for x in range(0, src.width - crop_w + 1, max(1, (src.width - crop_w) // 40 or 1)):
            crop = src.crop((x, 0, x + crop_w, src.height))
            for method_name, method in [("bilinear", Image.Resampling.BILINEAR), ("bicubic", Image.Resampling.BICUBIC), ("lanczos", Image.Resampling.LANCZOS)]:
                rendered = crop.resize(target.size, method)
                corr = float(np.mean(standard(rendered) * standard(target)))
                candidates.append((corr, x, crop_w, method_name, rendered.copy()))
    corr, x, crop_w, method_name, rendered = max(candidates, key=lambda row: row[0])
    print(target_path.name, src_path.name, f"corr={corr:.4f}", f"x={x}", f"crop_w={crop_w}", method_name)
    rendered.save(ROOT / f"matched_{target_path.stem}.jpg", quality=92)
