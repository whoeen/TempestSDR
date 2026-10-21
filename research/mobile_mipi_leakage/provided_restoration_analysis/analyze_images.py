from __future__ import annotations

import csv
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parent
P_VALUES = (1, 32, 100, 200)
DEVICES = {
    "iphone6s": {
        "title": "iPhone 6s",
        "original": ROOT / "iphone6s_original.png",
        "folder": ROOT / "iphone6s",
    },
    "lgx2": {
        "title": "LG X2 (2019)",
        "original": ROOT / "lgx2_original.png",
        "folder": ROOT / "lgx2",
    },
    "galaxy_s4_lte_111p9M": {
        "title": "Galaxy S4 LTE (111.9 MHz)",
        "original": ROOT / "galaxy_original.png",
        "folder": ROOT / "galaxy_s4_lte_111p9M",
    },
}


def font(size: int, bold: bool = False):
    paths = [
        Path(r"C:\Windows\Fonts") / ("arialbd.ttf" if bold else "arial.ttf"),
        Path(r"C:\Windows\Fonts") / ("malgunbd.ttf" if bold else "malgun.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
    ]
    for path in paths:
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def hsv_arrays(im: Image.Image):
    hsv = np.asarray(im.convert("RGB").convert("HSV"), dtype=np.float32) / 255.0
    return hsv[:, :, 0], hsv[:, :, 1], hsv[:, :, 2]


def circular_increment(h: np.ndarray, w: np.ndarray, axis: int):
    z = np.exp(2j * np.pi * h)
    if axis == 1:
        pair_w = np.sqrt(w[:, :-1] * w[:, 1:])
        dz = np.conj(z[:, :-1]) * z[:, 1:]
    else:
        pair_w = np.sqrt(w[:-1, :] * w[1:, :])
        dz = np.conj(z[:-1, :]) * z[1:, :]
    valid = pair_w > np.percentile(pair_w, 30)
    total_w = np.sum(pair_w[valid])
    mean = np.sum(pair_w[valid] * dz[valid]) / max(float(total_w), 1e-12)
    return float(np.angle(mean) / (2 * np.pi)), float(abs(mean))


def image_metrics(path: Path):
    with Image.open(path) as source:
        im = source.convert("RGB")
    h, s, v = hsv_arrays(im)
    weight = s * np.sqrt(np.maximum(v, 0))
    fx, coh_x = circular_increment(h, weight, 1)
    fy, coh_y = circular_increment(h, weight, 0)
    norm = math.hypot(fx, fy)
    normal_period = math.inf if norm < 1e-12 else 1.0 / norm
    line_angle = math.degrees(math.atan2(-fx, fy))
    while line_angle >= 90:
        line_angle -= 180
    while line_angle < -90:
        line_angle += 180

    vp = Image.fromarray(np.round(v * 255).astype(np.uint8), "L")
    med = np.asarray(vp.filter(ImageFilter.MedianFilter(3)), dtype=np.float32) / 255
    smooth = np.asarray(vp.filter(ImageFilter.GaussianBlur(4.0)), dtype=np.float32) / 255
    var_v = float(np.var(v))
    structure_fraction = float(np.var(smooth) / max(var_v, 1e-12))
    roughness = float(np.mean(np.abs(v - med)))
    col_profile = np.mean(smooth, axis=0)
    row_profile = np.mean(smooth, axis=1)
    column_component = float(np.std(col_profile) / max(np.std(smooth), 1e-12))
    row_component = float(np.std(row_profile) / max(np.std(smooth), 1e-12))
    return {
        "width": im.width,
        "height": im.height,
        "phase_dx_cycles_per_pixel": fx,
        "phase_dy_cycles_per_row": fy,
        "phase_dx_coherence": coh_x,
        "phase_dy_coherence": coh_y,
        "phase_normal_period_px": normal_period,
        "phase_stripe_line_angle_deg": line_angle,
        "value_low_frequency_fraction": structure_fraction,
        "value_median_residual": roughness,
        "column_profile_fraction": column_component,
        "row_profile_fraction": row_component,
    }


def repeatability_rows(device_key: str):
    path = DEVICES[device_key]["folder"] / f"{device_key}_metrics.csv"
    rows = {}
    with path.open("r", newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["method"] != "Coherent_HSV" or row["median"] != "median_off":
                continue
            p = int(row["frames"])
            rows[p] = {
                "repeatability_ssim": None if row["repeatabilitySSIM"] == "nan" else float(row["repeatabilitySSIM"]),
                "repeatability_psnr_db": None if row["repeatabilityPSNR_dB"] == "nan" else float(row["repeatabilityPSNR_dB"]),
                "repeatability_snr_db": None if row["repeatabilitySNR_dB"] == "nan" else float(row["repeatabilitySNR_dB"]),
                "mean_global_coherence": float(row["meanGlobalCoherence"]),
            }
    return rows


rows = []
for key, meta in DEVICES.items():
    repeat = repeatability_rows(key)
    for p in P_VALUES:
        path = meta["folder"] / f"{key}_P{p:03d}_Coherent_HSV_median_off.png"
        row = {
            "device": key,
            "device_title": meta["title"],
            "frames": p,
            "path": path.relative_to(ROOT).as_posix(),
        }
        row.update(image_metrics(path))
        row.update(repeat[p])
        rows.append(row)

(ROOT / "image_metrics.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
with (ROOT / "image_metrics.csv").open("w", newline="", encoding="utf-8-sig") as f:
    writer = csv.DictWriter(f, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)


def fit_panel(path: Path, size=(190, 360)):
    with Image.open(path) as im:
        rgb = im.convert("RGB")
    return ImageOps.contain(rgb, size, method=Image.Resampling.LANCZOS)


panel_w, panel_h = 210, 410
label_w = 190
sheet = Image.new("RGB", (label_w + panel_w * 5, 38 + panel_h * 3), (245, 246, 248))
draw = ImageDraw.Draw(sheet)
headers = ["Original", "P=1", "P=32", "P=100", "P=200"]
for j, header in enumerate(headers):
    x = label_w + j * panel_w + panel_w // 2
    draw.text((x, 8), header, fill=(25, 28, 33), font=font(18, True), anchor="ma")
for i, (key, meta) in enumerate(DEVICES.items()):
    y0 = 38 + i * panel_h
    label = meta["title"].replace(" (111.9 MHz)", "\n(111.9 MHz)")
    draw.multiline_text((12, y0 + 170), label, fill=(25, 28, 33), font=font(17, True), anchor="lm", spacing=4)
    paths = [meta["original"]] + [meta["folder"] / f"{key}_P{p:03d}_Coherent_HSV_median_off.png" for p in P_VALUES]
    for j, path in enumerate(paths):
        tile = fit_panel(path)
        x = label_w + j * panel_w + (panel_w - tile.width) // 2
        y = y0 + (370 - tile.height) // 2
        sheet.paste(tile, (x, y))
        draw.rectangle((label_w + j * panel_w + 8, y0 + 380, label_w + (j + 1) * panel_w - 8, y0 + 382), fill=(204, 208, 216))
sheet.save(ROOT / "frame_progression.jpg", quality=88, optimize=True)


# Decompose the P=200 rendering into what hue and value actually contain.
dec_w, dec_h = 230, 405
dec = Image.new("RGB", (170 + dec_w * 3, 42 + dec_h * 3), (245, 246, 248))
dd = ImageDraw.Draw(dec)
for j, title in enumerate(["Coherent HSV", "Hue only (phase)", "Value only (magnitude)"]):
    dd.text((170 + j * dec_w + dec_w // 2, 10), title, fill=(25, 28, 33), font=font(17, True), anchor="ma")
for i, (key, meta) in enumerate(DEVICES.items()):
    path = meta["folder"] / f"{key}_P200_Coherent_HSV_median_off.png"
    rgb = Image.open(path).convert("RGB")
    hsv_arr = np.asarray(rgb.convert("HSV"), dtype=np.uint8)
    hue_only = hsv_arr.copy()
    hue_only[:, :, 1] = 255
    hue_only[:, :, 2] = 230
    hue_im = Image.fromarray(hue_only, "HSV").convert("RGB")
    value_im = Image.fromarray(hsv_arr[:, :, 2], "L").convert("RGB")
    y0 = 42 + i * dec_h
    label = meta["title"].replace(" (111.9 MHz)", "\n(111.9 MHz)")
    dd.multiline_text((10, y0 + 180), label, fill=(25, 28, 33), font=font(16, True), anchor="lm", spacing=4)
    for j, panel in enumerate([rgb, hue_im, value_im]):
        tile = ImageOps.contain(panel, (200, 370), method=Image.Resampling.LANCZOS)
        x = 170 + j * dec_w + (dec_w - tile.width) // 2
        y = y0 + (380 - tile.height) // 2
        dec.paste(tile, (x, y))
dec.save(ROOT / "hsv_channel_decomposition.jpg", quality=90, optimize=True)


# Compact visual explanation: content amplitude gates a residual phase ramp;
# fractional horizontal shifts create a graded circular boundary after averaging.
W, H = 260, 360
yy, xx = np.mgrid[0:H, 0:W]
centers = [(70, 85), (190, 85), (70, 200), (190, 200)]
amp = np.full((H, W), 0.18, dtype=np.float32)
for cx, cy in centers:
    amp[(xx - cx) ** 2 + (yy - cy) ** 2 <= 42**2] = 0.95
phase = np.mod(0.075 * xx + 0.018 * yy, 1.0)
hsv = np.stack([np.round(255 * phase), np.full_like(amp, 255), np.round(255 * amp)], axis=2).astype(np.uint8)
hsv_rgb = Image.fromarray(hsv, "HSV").convert("RGB")
phase_hsv = np.stack([np.round(255 * phase), np.full_like(amp, 255), np.full_like(amp, 230)], axis=2).astype(np.uint8)
phase_rgb = Image.fromarray(phase_hsv, "HSV").convert("RGB")
amp_im = Image.fromarray(np.round(255 * amp).astype(np.uint8), "L").convert("RGB")

shifted = np.zeros_like(amp)
for delta in np.linspace(-12, 12, 31):
    shifted += np.asarray(Image.fromarray(np.round(255 * amp).astype(np.uint8), "L").transform((W, H), Image.Transform.AFFINE, (1, 0, delta, 0, 1, 0), resample=Image.Resampling.BILINEAR), dtype=np.float32) / 255
shifted /= 31
shifted_im = Image.fromarray(np.round(255 * shifted).astype(np.uint8), "L").convert("RGB")

expl = Image.new("RGB", (W * 4 + 60, H + 62), (245, 246, 248))
ed = ImageDraw.Draw(expl)
titles = ["Amplitude / content", "Residual phase ramp", "HSV: hue=phase, value=amplitude", "Shifted-frame average"]
for i, (title, panel) in enumerate(zip(titles, [amp_im, phase_rgb, hsv_rgb, shifted_im])):
    x = 12 + i * (W + 12)
    ed.text((x + W // 2, 12), title, fill=(25, 28, 33), font=font(16, True), anchor="ma")
    expl.paste(panel, (x, 46))
expl.save(ROOT / "circle_gradient_explainer.jpg", quality=90, optimize=True)


# Two publication-friendly metric panels. These are odd/even repeatability,
# so the labels explicitly avoid implying ground-truth fidelity.
chart = Image.new("RGB", (1240, 610), (250, 250, 251))
cd = ImageDraw.Draw(chart)
series_colors = {
    "iphone6s": (37, 99, 235),
    "lgx2": (0, 145, 120),
    "galaxy_s4_lte_111p9M": (220, 86, 70),
}


def plot_panel(box, key_name, title, y_min, y_max, y_ticks, unit=""):
    x0, y0, x1, y1 = box
    left, right, top, bottom = x0 + 78, x1 - 28, y0 + 52, y1 - 62
    cd.rectangle((left, top, right, bottom), outline=(160, 164, 171), width=2)
    for value in y_ticks:
        yp = bottom - (value - y_min) / (y_max - y_min) * (bottom - top)
        cd.line((left, yp, right, yp), fill=(220, 222, 227), width=1)
        cd.text((left - 10, yp), f"{value:g}", fill=(55, 58, 64), font=font(15), anchor="rm")
    for p in (32, 100, 200):
        xp = left + (p - 32) / (200 - 32) * (right - left)
        cd.line((xp, top, xp, bottom), fill=(232, 233, 236), width=1)
        cd.text((xp, bottom + 13), str(p), fill=(55, 58, 64), font=font(15), anchor="ma")
    cd.text(((left + right) // 2, y0 + 10), title, fill=(25, 28, 33), font=font(20, True), anchor="ma")
    cd.text(((left + right) // 2, y1 - 24), "Averaged frames P", fill=(55, 58, 64), font=font(16), anchor="ma")
    cd.text((x0 + 20, (top + bottom) // 2), unit, fill=(55, 58, 64), font=font(16), anchor="mm")
    for device_key, meta in DEVICES.items():
        pts = []
        for row in rows:
            if row["device"] != device_key or row["frames"] == 1:
                continue
            value = row[key_name]
            xp = left + (row["frames"] - 32) / (200 - 32) * (right - left)
            yp = bottom - (value - y_min) / (y_max - y_min) * (bottom - top)
            pts.append((xp, yp, value))
        cd.line([(x, y) for x, y, _ in pts], fill=series_colors[device_key], width=4)
        for x, y, value in pts:
            cd.ellipse((x - 6, y - 6, x + 6, y + 6), fill=series_colors[device_key])
            if value == pts[-1][2]:
                cd.text((x - 5, y - 11), f"{value:.2f}", fill=series_colors[device_key], font=font(14, True), anchor="rs")


plot_panel((20, 55, 615, 590), "repeatability_ssim", "Odd/even repeatability SSIM", 0, 1.0, [0, .25, .5, .75, 1.0], "SSIM")
plot_panel((625, 55, 1220, 590), "repeatability_snr_db", "Odd/even repeatability SNR", -12, 18, [-10, -5, 0, 5, 10, 15], "dB")
legend_x = 352
for device_key, meta in DEVICES.items():
    cd.line((legend_x, 30, legend_x + 30, 30), fill=series_colors[device_key], width=4)
    cd.text((legend_x + 38, 30), meta["title"].replace(" (111.9 MHz)", ""), fill=(25, 28, 33), font=font(15), anchor="lm")
    legend_x += 230
chart.save(ROOT / "frame_metrics.jpg", quality=94, optimize=True)

print(json.dumps(rows, ensure_ascii=False, indent=2))
