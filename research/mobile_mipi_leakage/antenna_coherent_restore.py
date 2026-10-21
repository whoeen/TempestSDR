"""Attempt iPhone-geometry restoration of three new antenna captures.

Facts used:
* raw format is big-endian int16 I,Q (RIS2IQ.m);
* antenna 1/2 show a ~60 Hz frame family and ~1880 line/frame geometry that
  closely matches the existing iPhone 6 capture;
* no header or sidecar supplies RF center, bandwidth, or sample rate.

The 124.085710 MS/s timebase is therefore an explicit, testable hypothesis,
not capture metadata.  Every output records that distinction.
"""
from __future__ import annotations

import json
import math
import csv
import os
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import coherent_hsv_resampling as core


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "coherent_results" / "antenna_big_endian"
DATA = Path(os.environ.get("TEMPEST_DATA_ROOT", ROOT / "data")).expanduser()
FILES = [DATA / f"antenna{i}.rIs" for i in range(1, 4)]
ASSUMED_FS = 124.085710e6
ROWS = 1880
COLS = 1100
ACTIVE_H = 1334
ACTIVE_W = 750
FRAMES = 24

# Full-file block-power Hann-FFT estimates (3-bin parabolic interpolation).
# They are measured in raw sample units and do not require an RF-frequency
# assumption. Antenna 3 did not reproduce this frame family, so its restoration
# uses the antenna 1/2 median strictly as a hypothesis test.
VERIFIED_FRAME_PERIODS = {
    1: 2_069_037.548,
    2: 2_068_971.403,
}


def power_blocks(path: Path, block: int = 64, maximum_samples: int = 120_000_000):
    total = min(path.stat().st_size // 4, maximum_samples)
    total -= total % block
    output = np.empty(total // block, dtype=np.float32)
    written = 0
    chunk_blocks = 32768
    with path.open("rb") as handle:
        while written < len(output):
            number_blocks = min(chunk_blocks, len(output) - written)
            raw = np.fromfile(handle, dtype=">i2", count=2 * number_blocks * block)
            pair = raw.reshape(number_blocks, block, 2).astype(np.float32)
            power = np.mean(pair[:, :, 0] ** 2 + pair[:, :, 1] ** 2, axis=1)
            output[written : written + number_blocks] = np.log1p(power)
            written += number_blocks
    return output, block


def parabolic(values: np.ndarray, index: int) -> float:
    if index <= 0 or index >= len(values) - 1:
        return float(index)
    a, b, c = values[index - 1 : index + 2]
    denominator = a - 2 * b + c
    if abs(denominator) < 1e-15:
        return float(index)
    return float(index + np.clip(0.5 * (a - c) / denominator, -0.5, 0.5))


def estimate_frame_period(path: Path):
    envelope, block = power_blocks(path)
    envelope -= envelope.mean(dtype=np.float64)
    nfft = 1 << (2 * len(envelope) - 1).bit_length()
    spectrum = np.fft.rfft(envelope, nfft)
    correlation = np.fft.irfft(spectrum * np.conj(spectrum), nfft)[: len(envelope)]
    overlap = np.arange(len(envelope), 0, -1, dtype=np.float64)
    correlation = correlation / overlap
    low = int(math.floor(ASSUMED_FS / 65.0 / block))
    high = int(math.ceil(ASSUMED_FS / 55.0 / block))
    region = correlation[low : high + 1]
    integer = int(np.argmax(region)) + low
    refined = parabolic(correlation, integer)
    period_samples = refined * block
    center = np.median(region)
    mad = 1.4826 * np.median(np.abs(region - center))
    prominence = float((correlation[integer] - center) / max(mad, 1e-12))
    return {
        "period_samples": period_samples,
        "frame_rate_hz_if_assumed_fs": ASSUMED_FS / period_samples,
        "line_rate_hz_if_1880_rows": ASSUMED_FS / period_samples * ROWS,
        "samples_per_line_if_1880_rows": period_samples / ROWS,
        "autocorrelation_peak_prominence_mad": prominence,
        "power_block_samples": block,
        "samples_used_for_timing": len(envelope) * block,
    }


def active_crop(amplitude: np.ndarray):
    row_score = np.var(np.log1p(amplitude), axis=1)
    rows = core.best_circular_window(row_score, ACTIVE_H)
    column_score = np.var(np.log1p(amplitude[rows]), axis=0)
    cols = core.best_circular_window(column_score, ACTIVE_W)
    return rows, cols


def save_progress(folder: Path, index: int, timing: dict, first: np.ndarray,
                  naive: np.ndarray, coherent: np.ndarray, amplitude: np.ndarray,
                  concentration: np.ndarray, rows: np.ndarray, cols: np.ndarray):
    def crop(x): return x[np.ix_(rows, cols)]
    images = [
        ("P=1 fractional HSV", core.hsv_image(crop(first))),
        (f"P={index} naive HSV", core.hsv_image(crop(naive))),
        (f"P={index} phase-tracked HSV", core.hsv_image(crop(coherent))),
        (f"P={index} AM average", core.gray(core.robust_value(crop(amplitude)))),
        ("phase concentration", core.gray(crop(concentration))),
    ]
    box = (350, 560); title_h = 92
    canvas = Image.new("RGB", (box[0] * len(images), box[1] + title_h), "white")
    draw = ImageDraw.Draw(canvas)
    draw.text((18, 10), f"{folder.name}: antenna IQ restoration attempt", font=core.font(25, True), fill="black")
    draw.text((18, 44),
              f"BE int16 IQ | assumed fs 124.085710 MS/s | estimated fv {timing['frame_rate_hz_if_assumed_fs']:.5f} Hz | {timing['samples_per_line_if_1880_rows']:.4f} samples/line",
              font=core.font(16), fill="#333333")
    draw.text((18, 67), "RF center/BW absent; iPhone-6 geometry is a hypothesis tested by image repeatability.", font=core.font(15), fill="#8a3b12")
    for column, (title, image) in enumerate(images):
        x = column * box[0]
        canvas.paste(core.fit_panel(image, (box[0], box[1] - 35)), (x, title_h + 35))
        draw.text((x + 8, title_h + 7), title, font=core.font(15, True), fill="black")
    canvas.save(folder / f"progress_P{index:03d}.png")


def process(path: Path, number: int, fallback_period: float | None = None):
    folder = OUT / f"antenna{number}"; folder.mkdir(parents=True, exist_ok=True)
    print(f"antenna {number}: estimating timing", flush=True)
    timing = estimate_frame_period(path)
    timing["short_probe_period_samples"] = timing.pop("period_samples")
    timing["full_file_verified_period_samples"] = VERIFIED_FRAME_PERIODS.get(number)
    if number in VERIFIED_FRAME_PERIODS:
        used_period = VERIFIED_FRAME_PERIODS[number]
        timing_source = "full-file power-block Hann FFT with 3-bin parabolic interpolation"
    elif fallback_period is not None:
        used_period = fallback_period
        timing_source = "fallback median of antenna1/2; antenna3 own 50-70 Hz peak is weak/nonmatching"
    else:
        used_period = timing["short_probe_period_samples"]
        timing_source = "short-probe 55-65 Hz autocorrelation peak"
    timing["period_used_samples"] = used_period
    timing["timing_source"] = timing_source
    timing["frame_rate_hz_if_assumed_fs"] = ASSUMED_FS / used_period
    timing["line_rate_hz_if_1880_rows"] = ASSUMED_FS / used_period * ROWS
    timing["samples_per_line_if_1880_rows"] = used_period / ROWS
    print(
        f"antenna {number}: using {used_period:.3f} samples/frame, "
        f"{timing['frame_rate_hz_if_assumed_fs']:.6f} Hz under fs hypothesis",
        flush=True,
    )
    spl = used_period / ROWS
    margin = 30 * spl / COLS + 8
    shape = (ROWS, COLS)
    amp_sum = np.zeros(shape, np.float32); naive_sum = np.zeros(shape, np.complex64)
    coherent_sum = np.zeros(shape, np.complex64); unit_sum = np.zeros(shape, np.complex64)
    odd_sum = np.zeros(shape, np.complex64); even_sum = np.zeros(shape, np.complex64)
    reference = None; reference_profile = None; first_frame = None
    rows = cols = None; diagnostics = []

    for frame_index in range(FRAMES):
        nominal = frame_index * used_period
        first_read = max(0, math.floor(nominal - margin) - 4)
        last_read = math.ceil(nominal + ROWS * spl + margin) + 5
        iq = core.read_iq(path, first_read, last_read - first_read + 1)
        iq -= np.complex64(iq.mean(dtype=np.complex128))
        frame = core.sample_positions(iq, first_read, nominal, ROWS, COLS, spl, "cubic")
        p = core.profile(frame, 1)
        if reference_profile is None:
            shift, score = 0.0, 1.0; reference_profile = p
        else:
            shift, score = core.estimate_shift(p, reference_profile, 24)
        aligned_start = nominal - shift * spl / COLS
        if abs(shift) > 1e-7:
            frame = core.sample_positions(iq, first_read, aligned_start, ROWS, COLS, spl, "cubic")
        if reference is None:
            corrected = frame.copy(); intercept = slope = residual = 0.0; coherence = 1.0
            reference = frame.copy(); first_frame = frame.copy()
        else:
            corrected, intercept, slope, coherence, residual = core.fit_phase_line(frame, reference)
        amplitude = np.abs(frame).astype(np.float32)
        amp_sum += amplitude; naive_sum += frame; coherent_sum += corrected
        unit_sum += corrected / (np.abs(corrected) + core.EPS)
        if frame_index % 2 == 0: odd_sum += corrected
        else: even_sum += corrected
        diagnostics.append({"frame": frame_index + 1, "column_shift": shift, "alignment_score": score,
                            "phase_intercept_rad": intercept, "phase_slope_rad_per_row": slope,
                            "coherence": coherence, "phase_residual_std_rad": residual})
        count = frame_index + 1
        if count in core.CHECKPOINTS:
            amplitude_avg = amp_sum / count; naive_avg = naive_sum / count
            coherent_avg = coherent_sum / count; concentration = np.abs(unit_sum / count)
            if rows is None: rows, cols = active_crop(amplitude_avg)
            save_progress(folder, count, timing, first_frame, naive_avg, coherent_avg, amplitude_avg, concentration, rows, cols)
            print(f"antenna {number}: saved P={count}", flush=True)

    amplitude_avg = amp_sum / FRAMES; naive_avg = naive_sum / FRAMES
    coherent_avg = coherent_sum / FRAMES; concentration = np.abs(unit_sum / FRAMES)
    assert rows is not None and cols is not None
    repeatability = core.pair_metrics(odd_sum / 12, even_sum / 12)
    metadata = {
        "file": str(path), "bytes": path.stat().st_size,
        "complex_samples": path.stat().st_size // 4,
        "iq_format": "interleaved big-endian signed int16 I,Q; headerless",
        "center_frequency_hz": None, "configured_bandwidth_hz": None,
        "sample_rate_status": "assumed from matching prior iPhone 6 receiver timebase; not file metadata",
        "assumed_sample_rate_sps": ASSUMED_FS,
        "timing": timing, "geometry_hypothesis": [ROWS, COLS], "active_crop": [len(rows), len(cols)],
        "frames_averaged": FRAMES,
        "mean_naive_phase_concentration": float(np.mean(np.abs(naive_avg) / np.maximum(amplitude_avg, core.EPS))),
        "mean_phase_tracked_concentration": float(np.mean(np.abs(coherent_avg) / np.maximum(amplitude_avg, core.EPS))),
        "odd_even_repeatability": repeatability,
        "mean_alignment_score": float(np.mean([r["alignment_score"] for r in diagnostics[1:]])),
        "mean_coherence_after_phase_tracking": float(np.mean([r["coherence"] for r in diagnostics[1:]])),
        "result_classification": "hypothesis test; visual and independent-half repeatability required",
    }
    with (folder / "frame_diagnostics.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(diagnostics[0]))
        writer.writeheader(); writer.writerows(diagnostics)
    (folder / "metrics.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    np.savez_compressed(folder / "final_arrays.npz", amplitude=amplitude_avg, naive=naive_avg,
                        coherent=coherent_avg, phase_concentration=concentration,
                        active_rows=rows, active_cols=cols)
    return metadata


def overview(items):
    paths = [OUT / f"antenna{i}" / "progress_P024.png" for i in range(1, 4)]
    images = [Image.open(path).convert("RGB") for path in paths]
    width = 1750; panels = []
    for image in images:
        image.thumbnail((width, 650), Image.Resampling.LANCZOS); panels.append(image.copy())
    canvas = Image.new("RGB", (width, sum(x.height for x in panels) + 115), "white")
    draw = ImageDraw.Draw(canvas); draw.text((20, 12), "Antenna captures: common big-endian/iPhone-timing hypothesis", font=core.font(28, True), fill="black")
    draw.text((20, 52), "Only antenna 1/2 timing is expected to be reliable; RF center, bandwidth and true fs were not embedded in the files.", font=core.font(17), fill="#6a3417")
    y = 100
    for image in panels: canvas.paste(image, ((width - image.width) // 2, y)); y += image.height
    canvas.save(OUT / "antenna_overview.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    first = process(FILES[0], 1)
    second = process(FILES[1], 2)
    robust_periods = list(VERIFIED_FRAME_PERIODS.values())
    fallback = float(np.median(robust_periods))
    third = process(FILES[2], 3, fallback)
    items = [first, second, third]
    (OUT / "summary.json").write_text(json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8")
    overview(items)


if __name__ == "__main__":
    main()
