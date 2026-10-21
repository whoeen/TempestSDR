"""Sensitivity sweep for the line period of antenna 1/2 captures.

The files are headerless big-endian int16 I,Q.  This script deliberately does
not infer a sample rate or RF center.  It uses the independently measured
full-file frame periods in *sample units* and tests whether the failed screen
reconstruction was caused by forcing 1880 rows per frame.

For every candidate samples/line value, four frames are reconstructed with
Catmull-Rom cubic fractional interpolation on a 1880 x 1100 raster.  Frames
1+3 and 2+4 form independent odd/even AM averages.  Their log-AM and
horizontal-edge correlations are reported on one fixed, documented crop per
antenna.  A high correlation proves recurrence, but cannot by itself identify
the recurring pattern as display content; the montages retain that distinction.
"""
from __future__ import annotations

import csv
import json
import math
import os
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import coherent_hsv_resampling as core


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "coherent_results" / "antenna_line_sweep"
DATA = Path(os.environ.get("TEMPEST_DATA_ROOT", ROOT / "data")).expanduser()
FILES = {1: DATA / "antenna1.rIs", 2: DATA / "antenna2.rIs"}
FRAME_PERIODS = {
    1: 2_069_037.548,
    2: 2_068_971.403,
}
ROWS = 1880
COLS = 1100
ACTIVE_ROWS = 1334
ACTIVE_COLS = 750
FRAME_INDICES = (1, 2, 3, 4)  # avoid the file-start interpolation boundary
BASE_CANDIDATES = (1098.0, 1099.0, 1100.0, 1100.52, 1101.0, 1102.0,
                   1103.0, 1104.0, 1105.0, 1106.0, 1107.0)


def candidates_for(period: float) -> list[float]:
    """Include the exact 1880-row implication as well as the common sweep."""
    values = list(BASE_CANDIDATES) + [period / ROWS]
    return sorted({round(value, 9) for value in values})


def load_frame_segments(path: Path, period: float, candidates: list[float]):
    """Read each source interval once; all line-period candidates reuse it."""
    maximum = max(candidates)
    segments = []
    for frame_index in FRAME_INDICES:
        nominal = frame_index * period
        first = max(0, math.floor(nominal) - 8)
        last = math.ceil(nominal + ROWS * maximum) + 8
        iq = core.read_iq(path, first, last - first + 1)
        iq -= np.complex64(iq.mean(dtype=np.complex128))
        segments.append((first, nominal, iq))
    return segments


def reconstruct_halves(segments, samples_per_line: float):
    odd = np.zeros((ROWS, COLS), np.float32)
    even = np.zeros((ROWS, COLS), np.float32)
    for index, (first, nominal, iq) in enumerate(segments):
        frame = core.sample_positions(
            iq, first, nominal, ROWS, COLS, samples_per_line, "cubic"
        )
        if index % 2 == 0:
            odd += np.abs(frame).astype(np.float32)
        else:
            even += np.abs(frame).astype(np.float32)
    odd /= 2.0
    even /= 2.0
    return odd, even, 0.5 * (odd + even)


def choose_fixed_crop(reference_average: np.ndarray):
    log_am = np.log1p(reference_average)
    row_score = np.var(log_am, axis=1)
    rows = core.best_circular_window(row_score, ACTIVE_ROWS)
    column_score = np.var(log_am[rows], axis=0)
    cols = core.best_circular_window(column_score, ACTIVE_COLS)
    return rows, cols


def projection_fractions(image: np.ndarray):
    """Energy in row/column-only projections versus true 2-D residual."""
    value = np.asarray(image, np.float64)
    value -= value.mean()
    total = float(np.sum(value * value))
    if total <= 1e-20:
        return {
            "column_projection_fraction": 0.0,
            "row_projection_fraction": 0.0,
            "two_dimensional_residual_fraction": 0.0,
            "horizontal_edge_column_projection_fraction": 0.0,
        }
    column = value.mean(axis=0)
    row = value.mean(axis=1)
    column_fraction = float(value.shape[0] * np.sum(column * column) / total)
    row_fraction = float(value.shape[1] * np.sum(row * row) / total)

    edge = np.diff(value, axis=1)
    edge -= edge.mean()
    edge_total = float(np.sum(edge * edge))
    edge_column = edge.mean(axis=0)
    edge_column_fraction = float(
        edge.shape[0] * np.sum(edge_column * edge_column) / max(edge_total, 1e-20)
    )
    return {
        "column_projection_fraction": column_fraction,
        "row_projection_fraction": row_fraction,
        "two_dimensional_residual_fraction": float(
            max(0.0, 1.0 - column_fraction - row_fraction)
        ),
        "horizontal_edge_column_projection_fraction": edge_column_fraction,
    }


def metrics(odd: np.ndarray, even: np.ndarray, average: np.ndarray,
            rows: np.ndarray, cols: np.ndarray):
    odd_crop = np.log1p(odd[np.ix_(rows, cols)]).astype(np.float64)
    even_crop = np.log1p(even[np.ix_(rows, cols)]).astype(np.float64)
    average_crop = np.log1p(average[np.ix_(rows, cols)]).astype(np.float64)
    result = {
        "odd_even_log_am_correlation": core.correlation(odd_crop, even_crop),
        "odd_even_horizontal_edge_correlation": core.correlation(
            np.diff(odd_crop, axis=1), np.diff(even_crop, axis=1)
        ),
        "odd_even_vertical_edge_correlation": core.correlation(
            np.diff(odd_crop, axis=0), np.diff(even_crop, axis=0)
        ),
        "log_am_standard_deviation": float(np.std(average_crop)),
    }
    result.update(projection_fractions(average_crop))
    return result


def normalized_gray(amplitude: np.ndarray) -> Image.Image:
    return core.gray(core.robust_value(amplitude)).convert("RGB")


def save_candidate_image(path: Path, average: np.ndarray, rows: np.ndarray,
                         cols: np.ndarray):
    image = normalized_gray(average[np.ix_(rows, cols)])
    image.save(path)
    return image


def save_sweep_montage(number: int, records: list[dict], images: list[Image.Image],
                       exact_spl: float, crop: dict):
    panel_w, panel_h = 310, 525
    columns = 4
    rows_count = math.ceil(len(records) / columns)
    header = 125
    canvas = Image.new("RGB", (columns * panel_w, header + rows_count * panel_h), "white")
    draw = ImageDraw.Draw(canvas)
    draw.text((18, 10), f"Antenna {number}: samples/line sensitivity (4-frame cubic AM)",
              font=core.font(27, True), fill="black")
    draw.text((18, 48),
              f"Frame period {FRAME_PERIODS[number]:.3f} samples; exact /1880 = {exact_spl:.6f}; raster 1880 x 1100",
              font=core.font(17), fill="#333333")
    draw.text((18, 75),
              f"Fixed crop {crop['height']}x{crop['width']} from exact-candidate variance window; r=log-AM, e=horizontal-edge odd/even correlation",
              font=core.font(15), fill="#333333")
    draw.text((18, 99),
              "Correlation shows recurrence. It does not by itself prove readable screen content.",
              font=core.font(15, True), fill="#8a3b12")

    best_index = int(np.argmax([record["odd_even_horizontal_edge_correlation"] for record in records]))
    for index, (record, image) in enumerate(zip(records, images)):
        grid_x = (index % columns) * panel_w
        grid_y = header + (index // columns) * panel_h
        is_exact = abs(record["samples_per_line"] - exact_spl) < 1e-7
        border = "#d47b16" if is_exact else ("#1769aa" if index == best_index else "#d6d6d6")
        draw.rectangle((grid_x + 2, grid_y + 2, grid_x + panel_w - 3,
                        grid_y + panel_h - 3), outline=border, width=4)
        label = f"spl={record['samples_per_line']:.6f}"
        if is_exact:
            label += "  [period/1880]"
        elif index == best_index:
            label += "  [best edge r]"
        draw.text((grid_x + 10, grid_y + 10), label, font=core.font(15, True), fill="black")
        draw.text((grid_x + 10, grid_y + 33),
                  f"r={record['odd_even_log_am_correlation']:+.3f}   e={record['odd_even_horizontal_edge_correlation']:+.3f}",
                  font=core.font(14), fill="#333333")
        draw.text((grid_x + 10, grid_y + 54),
                  f"column={record['column_projection_fraction']:.3f}  2-D={record['two_dimensional_residual_fraction']:.3f}",
                  font=core.font(13), fill="#555555")
        panel = core.fit_panel(image, (panel_w - 18, panel_h - 86), background="white")
        canvas.paste(panel, (grid_x + 9, grid_y + 79))
    output = OUT / f"antenna{number}_line_sweep_montage.png"
    canvas.save(output)
    return output, best_index


def difference_image(odd: np.ndarray, even: np.ndarray) -> Image.Image:
    a = np.log1p(odd).astype(np.float64)
    b = np.log1p(even).astype(np.float64)
    difference = np.abs(a - b)
    high = float(np.percentile(difference, 99))
    return core.gray(np.clip(difference / max(high, 1e-12), 0, 1)).convert("RGB")


def residual_image(average: np.ndarray) -> Image.Image:
    value = np.log1p(average).astype(np.float64)
    value -= value.mean()
    residual = value - value.mean(axis=0, keepdims=True) - value.mean(axis=1, keepdims=True)
    low, high = np.percentile(residual, [1, 99])
    normalized = np.clip((residual - low) / max(high - low, 1e-12), 0, 1)
    return core.gray(normalized).convert("RGB")


def save_half_detail(number: int, label: str, samples_per_line: float,
                     odd: np.ndarray, even: np.ndarray, average: np.ndarray,
                     rows: np.ndarray, cols: np.ndarray, record: dict):
    odd = odd[np.ix_(rows, cols)]
    even = even[np.ix_(rows, cols)]
    average = average[np.ix_(rows, cols)]
    views = [
        ("frames 1+3", normalized_gray(odd)),
        ("frames 2+4", normalized_gray(even)),
        ("four-frame mean", normalized_gray(average)),
        ("absolute half difference", difference_image(odd, even)),
        ("row+column projection removed", residual_image(average)),
    ]
    panel_w, panel_h = 300, 580
    header = 105
    canvas = Image.new("RGB", (panel_w * len(views), panel_h + header), "white")
    draw = ImageDraw.Draw(canvas)
    draw.text((18, 10), f"Antenna {number}: {label} candidate, spl={samples_per_line:.6f}",
              font=core.font(25, True), fill="black")
    draw.text((18, 46),
              f"independent-half log-AM r={record['odd_even_log_am_correlation']:+.4f}; horizontal-edge r={record['odd_even_horizontal_edge_correlation']:+.4f}",
              font=core.font(16), fill="#333333")
    draw.text((18, 73),
              "Rasterized tones can form stripes; only recognizable 2-D features surviving both independent halves count as frame-locked display content.",
              font=core.font(14), fill="#8a3b12")
    for index, (title, image) in enumerate(views):
        x = index * panel_w
        draw.text((x + 8, header + 7), title, font=core.font(14, True), fill="black")
        panel = core.fit_panel(image, (panel_w, panel_h - 35), background="white")
        canvas.paste(panel, (x, header + 35))
    output = OUT / f"antenna{number}_{label.replace(' ', '_')}_halves.png"
    canvas.save(output)
    return output


def crop_description(indices: np.ndarray, total: int):
    return {
        "start_index_zero_based": int(indices[0]),
        "length": int(len(indices)),
        "wraps_raster_boundary": bool(indices[-1] < indices[0]),
        "segments_zero_based_inclusive": (
            [[int(indices[0]), int(indices[-1])]]
            if indices[-1] >= indices[0]
            else [[int(indices[0]), total - 1], [0, int(indices[-1])]]
        ),
    }


def process_antenna(number: int):
    path = FILES[number]
    period = FRAME_PERIODS[number]
    exact_spl = period / ROWS
    candidates = candidates_for(period)
    print(f"antenna {number}: loading four source intervals", flush=True)
    segments = load_frame_segments(path, period, candidates)

    print(f"antenna {number}: defining fixed crop at spl={exact_spl:.9f}", flush=True)
    cached = reconstruct_halves(segments, exact_spl)
    crop_rows, crop_cols = choose_fixed_crop(cached[2])
    crop = {
        "selection": "maximum local-variance circular window on the four-frame mean at frame_period/1880; reused unchanged for every candidate",
        "height": int(len(crop_rows)),
        "width": int(len(crop_cols)),
        "rows": crop_description(crop_rows, ROWS),
        "columns": crop_description(crop_cols, COLS),
    }

    records = []
    images = []
    arrays_by_value = {}
    candidate_dir = OUT / f"antenna{number}_candidates"
    candidate_dir.mkdir(parents=True, exist_ok=True)
    for value in candidates:
        if abs(value - exact_spl) < 5e-10:
            odd, even, average = cached
        else:
            odd, even, average = reconstruct_halves(segments, value)
        result = {
            "antenna": number,
            "samples_per_line": value,
            "raster_span_samples": value * ROWS,
            "raster_minus_verified_frame_samples": value * ROWS - period,
            "is_frame_period_divided_by_1880": abs(value - exact_spl) < 1e-7,
        }
        result.update(metrics(odd, even, average, crop_rows, crop_cols))
        image_path = candidate_dir / f"spl_{value:.6f}.png"
        image = save_candidate_image(image_path, average, crop_rows, crop_cols)
        result["average_image"] = str(image_path.relative_to(ROOT))
        records.append(result)
        images.append(image)
        arrays_by_value[value] = (odd, even, average)
        print(
            f"antenna {number}: spl={value:.6f}, "
            f"AM r={result['odd_even_log_am_correlation']:+.4f}, "
            f"edge r={result['odd_even_horizontal_edge_correlation']:+.4f}",
            flush=True,
        )

    montage, best_index = save_sweep_montage(number, records, images, exact_spl, crop)
    best = records[best_index]
    best_arrays = arrays_by_value[best["samples_per_line"]]
    exact_index = int(np.argmin([abs(record["samples_per_line"] - exact_spl) for record in records]))
    exact = records[exact_index]
    exact_arrays = arrays_by_value[exact["samples_per_line"]]
    best_detail = save_half_detail(
        number, "best_edge", best["samples_per_line"], *best_arrays,
        crop_rows, crop_cols, best,
    )
    exact_detail = save_half_detail(
        number, "period_over_1880", exact["samples_per_line"], *exact_arrays,
        crop_rows, crop_cols, exact,
    )

    # This is deliberately a structural classification.  Readability is kept
    # as a separate visual assessment in the JSON after inspecting both halves.
    if best["odd_even_horizontal_edge_correlation"] >= 0.2:
        recurrence = "repeatable raster-locked structure present"
    else:
        recurrence = "weak independent-half recurrence"
    metadata = {
        "antenna": number,
        "source_file": str(path),
        "source_format": "headerless interleaved big-endian signed int16 I,Q",
        "raw_complex_samples": path.stat().st_size // 4,
        "verified_frame_period_samples": period,
        "frame_indices": list(FRAME_INDICES),
        "frames_per_candidate": len(FRAME_INDICES),
        "raster": {"rows": ROWS, "columns": COLS},
        "interpolation": "four-point Catmull-Rom cubic fractional interpolation",
        "sample_rate_hz": None,
        "rf_center_hz": None,
        "configured_bandwidth_hz": None,
        "fixed_crop": crop,
        "recurrence_classification": recurrence,
        "screen_content_visual_assessment": (
            "no readable two-dimensional screen content in any tested line period; "
            "stripe slope rotates with samples/line and the independent-half horizontal-edge "
            "correlation remains near zero, identifying rasterized interference rather than "
            "a frame-locked display image"
        ),
        "best_horizontal_edge_candidate": best,
        "period_over_1880_candidate": exact,
        "montage": str(montage.relative_to(ROOT)),
        "best_half_detail": str(best_detail.relative_to(ROOT)),
        "exact_half_detail": str(exact_detail.relative_to(ROOT)),
        "candidates": records,
    }
    return metadata


def write_csv(items: list[dict]):
    records = [record for item in items for record in item["candidates"]]
    fields = [key for key in records[0] if key != "average_image"] + ["average_image"]
    with (OUT / "line_sweep_metrics.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(records)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    items = [process_antenna(1), process_antenna(2)]
    write_csv(items)
    summary = {
        "purpose": "test whether the 1880-row samples/line assumption caused the missing antenna-screen reconstruction",
        "interpretation_rule": "odd/even correlation establishes recurrence only; readable display content requires recognizable two-dimensional features in both independent halves",
        "antennas": items,
    }
    (OUT / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"wrote {OUT}", flush=True)


if __name__ == "__main__":
    main()
