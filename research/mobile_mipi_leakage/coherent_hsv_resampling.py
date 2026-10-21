"""Big-endian coherent HSV and fractional-raster resampling experiment.

The old Python readers in this workspace used little-endian samples.  The
laboratory RIS2IQ.m reader and the byte distributions show that these captures
are interleaved big-endian int16 I,Q.  This script therefore starts from the
raw bytes again and compares a nearest-sample raster with a cubic fractional
delay raster on the same pixel grid.

This is a data-driven MIPI/display leakage experiment.  It does not claim that
the selected RF band is an integer pixel-clock harmonic or that its phase is a
decoded MIPI DSI symbol phase.
"""
from __future__ import annotations

import csv
import json
import math
import os
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "coherent_results" / "three_devices_big_endian"
DATA = Path(os.environ.get("TEMPEST_DATA_ROOT", ROOT / "data")).expanduser()
EPS = np.finfo(np.float32).eps
CHECKPOINTS = (1, 4, 16, 24)
MAX_FRAMES = max(CHECKPOINTS)
CHUNK = 1 << 20


@dataclass(frozen=True)
class Device:
    key: str
    title: str
    file: Path
    fc: float
    bandwidth: float
    fs: float
    fh: float
    rows: int
    cols: int
    origin_columns: float = 0.0
    active_rows: np.ndarray | None = None
    active_cols: np.ndarray | None = None
    expected_active_shape: tuple[int, int] | None = None


def circ_segments(parts: list[tuple[int, int]]) -> np.ndarray:
    return np.concatenate([np.arange(a - 1, b, dtype=np.int64) for a, b in parts])


DEVICES = (
    Device(
        "iphone6",
        "iPhone 6",
        DATA / "238M_60M_124.08571M_topleft_iphone6.rIs",
        238e6,
        60e6,
        124.085710e6,
        112805.083,
        1880,
        1100,
        expected_active_shape=(1334, 750),
    ),
    Device(
        "lgx2",
        "LG X2 (2019)",
        DATA / "LGX22019_344.8M_60M_136.56551M.rIs",
        344.8e6,
        60e6,
        136.565510e6,
        88679.652541,
        1478,
        1022,
        origin_columns=15.5,
        active_rows=circ_segments([(753, 1478), (1, 714)]),
        active_cols=circ_segments([(916, 1022), (1, 613)]),
    ),
    Device(
        "galaxy_s4_lte",
        "Galaxy S4 LTE",
        Path(
            os.environ.get(
                "TEMPEST_GALAXY_171_FILE",
                DATA / "171.5mhz_20m_55.81679m_galaxS4lte.rIs",
            )
        ).expanduser(),
        171.5e6,
        20e6,
        55.816790e6,
        116153.4254,
        1936,
        1080,
        active_rows=circ_segments([(61, 1936), (1, 36)]),
        active_cols=circ_segments([(877, 1080), (1, 719)]),
    ),
)


def font(size: int, bold: bool = False):
    candidates = [
        Path(r"C:\Windows\Fonts") / ("arialbd.ttf" if bold else "arial.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
    ]
    for path in candidates:
        if path.is_file():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def read_iq(path: Path, first: int, count: int) -> np.ndarray:
    with path.open("rb") as handle:
        handle.seek(first * 4)
        raw = np.fromfile(handle, dtype=">i2", count=2 * count)
    if raw.size != 2 * count:
        raise RuntimeError(f"short read {path.name}: {raw.size // 2}/{count}")
    pair = raw.reshape(-1, 2)
    return pair[:, 0].astype(np.float32) + 1j * pair[:, 1].astype(np.float32)


def sample_positions(
    iq: np.ndarray,
    first_read: int,
    frame_start: float,
    rows: int,
    output_columns: int,
    samples_per_line: float,
    method: str,
) -> np.ndarray:
    total = rows * output_columns
    output = np.empty(total, dtype=np.complex64)
    step = samples_per_line / output_columns
    for first in range(0, total, CHUNK):
        last = min(total, first + CHUNK)
        linear = np.arange(first, last, dtype=np.int64)
        row = linear // output_columns
        column = linear - row * output_columns
        position = (
            frame_start
            + row.astype(np.float64) * samples_per_line
            + column.astype(np.float64) * step
            - first_read
        )
        if method == "nearest":
            output[first:last] = iq[np.rint(position).astype(np.int64)]
            continue
        if method != "cubic":
            raise ValueError(method)
        base = np.floor(position).astype(np.int64)
        t = (position - base).astype(np.float32)
        p0, p1, p2, p3 = iq[base - 1], iq[base], iq[base + 1], iq[base + 2]
        output[first:last] = 0.5 * (
            2.0 * p1
            + (-p0 + p2) * t
            + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
            + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t
        )
    return output.reshape(rows, output_columns)


def profile(image: np.ndarray, k: int) -> np.ndarray:
    cells = np.abs(image).reshape(image.shape[0], -1, k).mean(axis=2)
    p = cells.mean(axis=0, dtype=np.float64)
    p -= p.mean()
    pad = np.pad(p, 2, mode="wrap")
    p = np.convolve(pad, np.ones(5) / 5, mode="valid")
    return p / max(float(np.linalg.norm(p)), 1e-12)


def estimate_shift(value: np.ndarray, reference: np.ndarray, maximum: int = 24):
    shifts = np.arange(-maximum, maximum + 1)
    scores = np.array([np.dot(np.roll(value, s), reference) for s in shifts])
    peak = int(np.argmax(scores))
    delta = 0.0
    if 0 < peak < len(scores) - 1:
        a, b, c = scores[peak - 1 : peak + 2]
        denominator = a - 2 * b + c
        if abs(denominator) > 1e-12:
            delta = float(np.clip(0.5 * (a - c) / denominator, -0.5, 0.5))
    return float(shifts[peak] + delta), float(scores[peak])


def fit_phase_line(frame: np.ndarray, reference: np.ndarray):
    cross = np.sum(frame * np.conj(reference), axis=1, dtype=np.complex128)
    smooth = np.convolve(cross, np.ones(15) / 15, mode="same")
    phase = np.unwrap(np.angle(smooth))
    weight = np.abs(smooth)
    threshold = np.percentile(weight, 30)
    keep = weight >= threshold
    x = np.arange(frame.shape[0], dtype=np.float64)
    design = np.stack([np.ones_like(x[keep]), x[keep]], axis=1)
    root_weight = np.sqrt(weight[keep] / max(float(weight[keep].max()), 1e-12))
    coefficient = np.linalg.lstsq(
        design * root_weight[:, None], phase[keep] * root_weight, rcond=None
    )[0]
    model = coefficient[0] + coefficient[1] * x
    corrected = frame * np.exp(-1j * model[:, None]).astype(np.complex64)
    normalized = float(
        abs(np.vdot(reference.ravel(), corrected.ravel()))
        / max(
            math.sqrt(
                float(np.vdot(reference.ravel(), reference.ravel()).real)
                * float(np.vdot(corrected.ravel(), corrected.ravel()).real)
            ),
            1e-12,
        )
    )
    residual = np.angle(smooth * np.exp(-1j * model))
    return corrected, float(coefficient[0]), float(coefficient[1]), normalized, float(np.std(residual[keep]))


def robust_value(complex_or_amplitude: np.ndarray) -> np.ndarray:
    magnitude = np.abs(complex_or_amplitude).astype(np.float64)
    positive = magnitude[magnitude > 0]
    floor = np.percentile(positive, 0.1) if positive.size else 1.0
    value = np.log(np.maximum(magnitude, floor))
    low, high = np.percentile(value, [1, 99])
    return np.clip((value - low) / max(high - low, 1e-12), 0, 1)


def gray(values: np.ndarray) -> Image.Image:
    return Image.fromarray(np.uint8(np.round(255 * np.clip(values, 0, 1))), "L")


def hsv_image(z: np.ndarray, phase_offset: float | None = None) -> Image.Image:
    if phase_offset is None:
        phase_offset = float(np.angle(np.sum(z, dtype=np.complex128)))
    hue = np.mod((np.angle(z) - phase_offset + np.pi) / (2 * np.pi), 1.0)
    value = robust_value(z)
    hsv = np.stack(
        [np.uint8(np.round(255 * hue)), np.full(hue.shape, 235, np.uint8), np.uint8(np.round(255 * value))],
        axis=2,
    )
    return Image.fromarray(hsv, "HSV").convert("RGB")


def best_circular_window(score: np.ndarray, length: int) -> np.ndarray:
    if length >= len(score):
        return np.arange(len(score), dtype=np.int64)
    doubled = np.concatenate([score, score])
    sums = np.convolve(doubled, np.ones(length), mode="valid")[: len(score)]
    start = int(np.argmax(sums))
    return (start + np.arange(length, dtype=np.int64)) % len(score)


def choose_active(device: Device, amplitude: np.ndarray, k: int):
    if device.active_rows is not None and device.active_cols is not None:
        return device.active_rows, device.active_cols, "established prior crop"
    cell = amplitude.reshape(device.rows, device.cols, k).mean(axis=2)
    active_h, active_w = device.expected_active_shape or (device.rows, device.cols)
    row_score = np.var(np.log1p(cell), axis=1)
    rows = best_circular_window(row_score, active_h)
    column_score = np.var(np.log1p(cell[rows]), axis=0)
    cols = best_circular_window(column_score, active_w)
    return rows, cols, "automatic maximum local-variance circular crop"


def crop_samples(image: np.ndarray, rows: np.ndarray, cols: np.ndarray, k: int):
    sample_cols = (cols[:, None] * k + np.arange(k)[None, :]).ravel()
    return image[np.ix_(rows, sample_cols)]


def cell_average(image: np.ndarray, k: int) -> np.ndarray:
    return image.reshape(image.shape[0], -1, k).mean(axis=2)


def correlation(a: np.ndarray, b: np.ndarray) -> float:
    x = np.asarray(a, np.float64).ravel(); y = np.asarray(b, np.float64).ravel()
    x -= x.mean(); y -= y.mean()
    return float(x @ y / max(float(np.linalg.norm(x) * np.linalg.norm(y)), 1e-12))


def pair_metrics(a: np.ndarray, b: np.ndarray):
    cross = np.vdot(b.ravel(), a.ravel())
    a = a * np.exp(-1j * np.angle(cross)).astype(np.complex64)
    mag_a, mag_b = robust_value(a), robust_value(b)
    mask = (mag_a + mag_b) > np.percentile(mag_a + mag_b, 35)
    phase_delta = np.angle(a[mask] * np.conj(b[mask]))
    weights = np.sqrt(np.abs(a[mask]) * np.abs(b[mask]))
    phase_agreement = float(abs(np.sum(weights * np.exp(1j * phase_delta))) / max(float(weights.sum()), 1e-12))
    circular_rmse = float(np.sqrt(np.sum(weights * phase_delta**2) / max(float(weights.sum()), 1e-12)))
    return {
        "log_magnitude_correlation": correlation(mag_a, mag_b),
        "horizontal_edge_correlation": correlation(np.diff(mag_a, axis=1), np.diff(mag_b, axis=1)),
        "weighted_phase_agreement": phase_agreement,
        "weighted_phase_rmse_rad": circular_rmse,
    }


def fit_panel(image: Image.Image, box: tuple[int, int], background="white") -> Image.Image:
    copy = image.copy().convert("RGB")
    copy.thumbnail(box, Image.Resampling.LANCZOS)
    panel = Image.new("RGB", box, background)
    panel.paste(copy, ((box[0] - copy.width) // 2, (box[1] - copy.height) // 2))
    return panel


def make_progress(
    device: Device,
    folder: Path,
    frames: int,
    k: int,
    rows: np.ndarray,
    cols: np.ndarray,
    first_nearest: np.ndarray,
    first_cubic: np.ndarray,
    nearest_average: np.ndarray,
    naive_average: np.ndarray,
    coherent_average: np.ndarray,
    amplitude_average: np.ndarray,
    phase_coherence: np.ndarray,
):
    images = [
        ("P=1 nearest HSV", hsv_image(crop_samples(first_nearest, rows, cols, k))),
        ("P=1 cubic HSV", hsv_image(crop_samples(first_cubic, rows, cols, k))),
        (f"P={frames} naive complex HSV", hsv_image(crop_samples(naive_average, rows, cols, k))),
        (f"P={frames} phase-tracked HSV", hsv_image(crop_samples(coherent_average, rows, cols, k))),
        (f"P={frames} AM average", gray(robust_value(crop_samples(amplitude_average, rows, cols, k)))),
        ("phase concentration", gray(crop_samples(phase_coherence, rows, cols, k))),
    ]
    box = (310, 560)
    title_h = 78
    canvas = Image.new("RGB", (box[0] * 6, box[1] + title_h), "white")
    draw = ImageDraw.Draw(canvas)
    draw.text((16, 10), f"{device.title}: big-endian IQ, nearest vs fractional cubic resampling", font=font(24, True), fill="black")
    draw.text((16, 43), f"raw {device.fs/(device.fh*device.cols):.6f} samples/raster-cell -> k={k}; {frames} frames", font=font(17), fill="#333333")
    for index, (title, image) in enumerate(images):
        x = index * box[0]
        canvas.paste(fit_panel(image, (box[0], box[1] - 36)), (x, title_h + 36))
        draw.text((x + 8, title_h + 8), title, font=font(15, True), fill="black")
    path = folder / f"progress_P{frames:03d}.png"
    canvas.save(path)
    return path


def moving_circular(x: np.ndarray, width: int = 61):
    pad = width // 2
    return np.convolve(np.pad(x, pad, mode="wrap"), np.ones(width) / width, mode="valid")


def column_phase_analysis(
    device: Device,
    folder: Path,
    coherent: np.ndarray,
    amplitude: np.ndarray,
    k: int,
):
    z = cell_average(coherent, k)
    a = amplitude.reshape(device.rows, device.cols, k).mean(axis=2)
    column_amplitude = a.mean(axis=0, dtype=np.float64)
    stripe = column_amplitude - moving_circular(column_amplitude)

    # Remove the common phase of each raster row before comparing a feature
    # that recurs at the same x position over many rows.  Three alternating
    # phase-synchronization steps estimate one common column template without
    # assuming that any particular row is a noiseless reference.
    template = np.mean(np.abs(z), axis=0).astype(np.complex128)
    row_aligned = z.astype(np.complex128)
    for _ in range(3):
        row_phase = np.angle(np.sum(z * np.conj(template)[None, :], axis=1))
        row_aligned = z * np.exp(-1j * row_phase[:, None])
        template = row_aligned.mean(axis=0, dtype=np.complex128)

    # A vertical-line component is defined relative to its local complex
    # background.  This keeps a broad common carrier/bias from determining the
    # phase assigned to a narrow stripe.
    pad = 30
    extended = np.concatenate([row_aligned[:, -pad:], row_aligned, row_aligned[:, :pad]], axis=1)
    local = np.zeros_like(row_aligned, dtype=np.complex128)
    for offset in range(61):
        local += extended[:, offset : offset + device.cols]
    local /= 61.0
    residual = row_aligned - local
    column_complex = residual.mean(axis=0, dtype=np.complex128)
    concentration = np.abs(column_complex) / np.maximum(np.mean(np.abs(residual), axis=0), 1e-12)
    order = np.argsort(np.abs(stripe))[::-1]
    peaks: list[int] = []
    for value in order:
        if all(min(abs(int(value) - p), device.cols - abs(int(value) - p)) >= 8 for p in peaks):
            peaks.append(int(value))
        if len(peaks) == 12:
            break
    scale = 1.4826 * np.median(np.abs(stripe - np.median(stripe)))
    strongest = int(peaks[0])
    global_phase = np.angle(column_complex[strongest])
    phase = np.angle(column_complex * np.exp(-1j * global_phase))
    rows = [
        {
            "raster_column_0based": p,
            "stripe_z": float(stripe[p] / max(scale, 1e-12)),
            "relative_phase_deg": float(np.degrees(phase[p])),
            "row_phase_concentration": float(concentration[p]),
            "mean_amplitude": float(column_amplitude[p]),
        }
        for p in sorted(peaks)
    ]
    with (folder / "vertical_line_phase.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader(); writer.writerows(rows)

    width, height = 1300, 760
    left, right, top, plot_h = 95, 35, 90, 490
    plot_w = width - left - right
    canvas = Image.new("RGB", (width, height), "white"); draw = ImageDraw.Draw(canvas)
    draw.text((24, 16), f"{device.title}: vertical-line amplitude and relative complex phase", font=font(25, True), fill="black")
    draw.text((24, 50), f"Narrow-stripe residual phase, relative to strongest stripe x={strongest}, after common row phase removal; not DDIC pin phase.", font=font(16), fill="#444444")
    xpix = left + np.arange(device.cols) / max(device.cols - 1, 1) * plot_w
    smax = max(float(np.percentile(np.abs(stripe), 99)), 1e-12)
    ystripe = top + 0.24 * plot_h - np.clip(stripe / smax, -1, 1) * 0.20 * plot_h
    draw.line(list(zip(xpix, ystripe)), fill="#222222", width=2)
    yphase = top + 0.64 * plot_h - phase / np.pi * 0.20 * plot_h
    points = list(zip(xpix, yphase))
    for i in range(len(points) - 1):
        hue = int(255 * ((phase[i] + np.pi) / (2 * np.pi)))
        color = Image.new("HSV", (1, 1), (hue, 220, 210)).convert("RGB").getpixel((0, 0))
        draw.line((points[i][0], points[i][1], points[i + 1][0], points[i + 1][1]), fill=color, width=2)
    yconc = top + 0.98 * plot_h - concentration * 0.18 * plot_h
    draw.line(list(zip(xpix, yconc)), fill="#1473b8", width=2)
    draw.text((15, top + 0.20 * plot_h), "stripe", font=font(15), fill="black")
    draw.text((15, top + 0.60 * plot_h), "phase", font=font(15), fill="black")
    draw.text((15, top + 0.92 * plot_h), "conc.", font=font(15), fill="#1473b8")
    for x in (0, device.cols // 4, device.cols // 2, 3 * device.cols // 4, device.cols - 1):
        xp = left + x / max(device.cols - 1, 1) * plot_w
        draw.line((xp, top, xp, top + plot_h), fill="#e5e5e5", width=1)
        draw.text((xp - 15, top + plot_h + 8), str(x), font=font(14), fill="black")
    for index, row in enumerate(rows):
        draw.text((35 + (index % 6) * 208, 635 + (index // 6) * 48),
                  f"x={row['raster_column_0based']:4d}  z={row['stripe_z']:+5.1f}  phi={row['relative_phase_deg']:+6.1f}°  R={row['row_phase_concentration']:.2f}",
                  font=font(13), fill="black")
    canvas.save(folder / "vertical_line_phase.png")
    return rows


def process(device: Device):
    folder = OUT / device.key; folder.mkdir(parents=True, exist_ok=True)
    spp = device.fs / (device.fh * device.cols)
    k = max(1, int(math.ceil(spp - 1e-3)))
    output_columns = device.cols * k
    spl = device.fs / device.fh
    cell_samples = spl / device.cols
    frame_period = device.rows * spl
    margin = (28 + 4) * cell_samples + 6

    shapes = (device.rows, output_columns)
    amplitude_sum = np.zeros(shapes, np.float32)
    coherent_sum = np.zeros(shapes, np.complex64)
    naive_sum = np.zeros(shapes, np.complex64)
    nearest_sum = np.zeros(shapes, np.complex64)
    unit_sum = np.zeros(shapes, np.complex64)
    odd_sum = np.zeros(shapes, np.complex64); even_sum = np.zeros(shapes, np.complex64)
    odd_n = 0; even_n = 0
    reference = None; nearest_reference = None; reference_profile = None
    first_nearest = None; first_cubic = None
    diagnostics = []
    checkpoint_metrics = []
    rows = device.active_rows; cols = device.active_cols; crop_note = ""

    print(f"\n{device.title}: {spp:.6f} raw samples/cell -> k={k}", flush=True)
    for frame_index in range(MAX_FRAMES):
        nominal = frame_index * frame_period + device.origin_columns * cell_samples
        first_read = max(0, math.floor(nominal - margin) - 4)
        last_read = math.ceil(nominal + device.rows * spl + margin) + 5
        iq = read_iq(device.file, first_read, last_read - first_read + 1)
        iq -= np.complex64(iq.mean(dtype=np.complex128))
        cubic = sample_positions(iq, first_read, nominal, device.rows, output_columns, spl, "cubic")
        p = profile(cubic, k)
        if reference_profile is None:
            shift, score = 0.0, 1.0
            reference_profile = p
        else:
            shift, score = estimate_shift(p, reference_profile)
        aligned_start = nominal - shift * cell_samples
        if abs(shift) > 1e-7:
            cubic = sample_positions(iq, first_read, aligned_start, device.rows, output_columns, spl, "cubic")
        nearest = sample_positions(iq, first_read, aligned_start, device.rows, output_columns, spl, "nearest")

        if reference is None:
            corrected = cubic.copy(); nearest_corrected = nearest.copy()
            intercept = slope = phase_residual = 0.0; coherence = 1.0
            reference = cubic.copy(); nearest_reference = nearest.copy()
            first_nearest = nearest.copy(); first_cubic = cubic.copy()
        else:
            corrected, intercept, slope, coherence, phase_residual = fit_phase_line(cubic, reference)
            phase_model = intercept + slope * np.arange(device.rows, dtype=np.float64)
            nearest_corrected = nearest * np.exp(-1j * phase_model[:, None]).astype(np.complex64)
        magnitude = np.abs(cubic).astype(np.float32)
        amplitude_sum += magnitude
        naive_sum += cubic
        coherent_sum += corrected
        nearest_sum += nearest_corrected
        unit_sum += corrected / (np.abs(corrected) + EPS)
        if frame_index % 2 == 0:
            odd_sum += corrected; odd_n += 1
        else:
            even_sum += corrected; even_n += 1
        diagnostics.append({
            "frame": frame_index + 1,
            "fractional_column_shift": shift,
            "alignment_score": score,
            "phase_intercept_rad": intercept,
            "phase_slope_rad_per_row": slope,
            "equivalent_residual_hz": slope * device.fh / (2 * np.pi),
            "coherence_after_linear_phase": coherence,
            "phase_model_residual_std_rad": phase_residual,
        })

        frames = frame_index + 1
        if frames in CHECKPOINTS:
            amplitude_average = amplitude_sum / frames
            coherent_average = coherent_sum / frames
            naive_average = naive_sum / frames
            nearest_average = nearest_sum / frames
            phase_coherence = np.abs(unit_sum / frames)
            if rows is None or cols is None:
                rows, cols, crop_note = choose_active(device, amplitude_average, k)
            amp_crop = crop_samples(amplitude_average, rows, cols, k)
            naive_crop = crop_samples(naive_average, rows, cols, k)
            coherent_crop = crop_samples(coherent_average, rows, cols, k)
            unit_crop = crop_samples(phase_coherence, rows, cols, k)
            naive_c = float(np.mean(np.abs(naive_crop) / np.maximum(amp_crop, EPS)))
            tracked_c = float(np.mean(np.abs(coherent_crop) / np.maximum(amp_crop, EPS)))
            checkpoint_metrics.append({
                "frames": frames,
                "mean_naive_phase_concentration": naive_c,
                "mean_phase_tracked_concentration": tracked_c,
                "tracked_to_naive_gain": tracked_c / max(naive_c, 1e-12),
                "mean_unit_phasor_concentration": float(np.mean(unit_crop)),
                "log_amplitude_spatial_std": float(np.std(np.log1p(amp_crop))),
            })
            make_progress(device, folder, frames, k, rows, cols, first_nearest, first_cubic,
                          nearest_average, naive_average, coherent_average, amplitude_average, phase_coherence)
            print(f"  saved P={frames}", flush=True)

    amplitude_average = amplitude_sum / MAX_FRAMES
    coherent_average = coherent_sum / MAX_FRAMES
    naive_average = naive_sum / MAX_FRAMES
    nearest_average = nearest_sum / MAX_FRAMES
    phase_coherence = np.abs(unit_sum / MAX_FRAMES)
    odd_average = odd_sum / odd_n; even_average = even_sum / even_n
    assert rows is not None and cols is not None
    cropped_odd = crop_samples(odd_average, rows, cols, k)
    cropped_even = crop_samples(even_average, rows, cols, k)
    repeatability = pair_metrics(cropped_odd, cropped_even)
    nearest_cropped = crop_samples(nearest_average, rows, cols, k)
    cubic_cropped = crop_samples(coherent_average, rows, cols, k)
    resampling_change = pair_metrics(nearest_cropped, cubic_cropped)
    naive_coherence = float(np.mean(np.abs(naive_average) / np.maximum(amplitude_average, EPS)))
    aligned_coherence = float(np.mean(np.abs(coherent_average) / np.maximum(amplitude_average, EPS)))
    active_final = checkpoint_metrics[-1]
    phase_rows = column_phase_analysis(device, folder, coherent_average, amplitude_average, k)

    with (folder / "frame_diagnostics.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(diagnostics[0]))
        writer.writeheader(); writer.writerows(diagnostics)
    with (folder / "checkpoint_metrics.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(checkpoint_metrics[0]))
        writer.writeheader(); writer.writerows(checkpoint_metrics)
    metadata = {
        "device": device.title,
        "source": str(device.file),
        "iq_format": "interleaved big-endian signed int16 [I,Q], no header",
        "center_frequency_hz": device.fc,
        "configured_complex_bandwidth_hz": device.bandwidth,
        "stored_complex_sample_rate_sps": device.fs,
        "line_rate_hz": device.fh,
        "raster": [device.rows, device.cols],
        "raw_samples_per_line": spl,
        "raw_samples_per_raster_cell": spp,
        "fractional_output_samples_per_raster_cell_k": k,
        "fractional_output_rate_sps": k * device.fh * device.cols,
        "interpolator": "four-point Catmull-Rom cubic fractional delay",
        "frames": MAX_FRAMES,
        "checkpoint_metrics": checkpoint_metrics,
        "crop": {"rows": len(rows), "columns": len(cols), "method": crop_note or "established prior crop"},
        "mean_naive_phase_concentration": naive_coherence,
        "mean_phase_tracked_concentration": aligned_coherence,
        "concentration_gain": aligned_coherence / max(naive_coherence, 1e-12),
        "active_mean_naive_phase_concentration": active_final["mean_naive_phase_concentration"],
        "active_mean_phase_tracked_concentration": active_final["mean_phase_tracked_concentration"],
        "active_concentration_gain": active_final["tracked_to_naive_gain"],
        "odd_even_repeatability_after_fractional_resampling": repeatability,
        "nearest_vs_fractional_change_after_common_phase_alignment": resampling_change,
        "mean_abs_fractional_column_shift": float(np.mean(np.abs([d["fractional_column_shift"] for d in diagnostics]))),
        "std_equivalent_residual_hz": float(np.std([d["equivalent_residual_hz"] for d in diagnostics[1:]])),
        "vertical_line_phase_peaks": phase_rows,
        "interpretation_limit": "Relative received complex phase after empirical timing/linear-row phase tracking; not decoded MIPI lane or DDIC pin phase.",
    }
    (folder / "metrics.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    np.savez_compressed(folder / "final_arrays.npz",
                        amplitude=amplitude_average.astype(np.float32),
                        naive=naive_average.astype(np.complex64),
                        coherent=coherent_average.astype(np.complex64),
                        nearest=nearest_average.astype(np.complex64),
                        phase_coherence=phase_coherence.astype(np.float32),
                        active_rows=rows, active_cols=cols)
    return metadata


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    summaries = [process(device) for device in DEVICES]
    (OUT / "summary.json").write_text(json.dumps(summaries, ensure_ascii=False, indent=2), encoding="utf-8")
    with (OUT / "summary.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        fields = ["device", "center_frequency_hz", "configured_complex_bandwidth_hz", "stored_complex_sample_rate_sps",
                  "raw_samples_per_line", "raw_samples_per_raster_cell", "fractional_output_samples_per_raster_cell_k",
                  "fractional_output_rate_sps", "mean_naive_phase_concentration", "mean_phase_tracked_concentration",
                  "concentration_gain", "active_mean_naive_phase_concentration",
                  "active_mean_phase_tracked_concentration", "active_concentration_gain",
                  "mean_abs_fractional_column_shift", "std_equivalent_residual_hz"]
        writer = csv.DictWriter(handle, fieldnames=fields); writer.writeheader()
        for item in summaries:
            writer.writerow({field: item[field] for field in fields})


if __name__ == "__main__":
    main()
