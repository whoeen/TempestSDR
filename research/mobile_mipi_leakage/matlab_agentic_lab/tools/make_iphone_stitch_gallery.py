#!/usr/bin/env python3
"""Build an offline iPhone stitching gallery from existing PNG/JSON outputs.

This script performs presentation layout only: Pillow opens/resizes existing
images for four small contact sheets. It never reads IQ/MAT files and performs
no signal processing, image enhancement, alignment, or fidelity measurement.
Run only after the MATLAB result stages have finished. Missing outputs remain
explicitly pending rather than being inferred or replaced.

    python tools/make_iphone_stitch_gallery.py
    python tools/make_iphone_stitch_gallery.py --result-root <results-directory>

The HTML refers to the original PNGs by relative paths; preserve the result
folder tree in the full-resolution views release bundle. Only four summary
PNGs and one copied reference PNG are created in gallery/.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import math
import os
from pathlib import Path
import shutil
import textwrap
from datetime import datetime, timezone
from urllib.parse import quote

from PIL import Image, ImageDraw, ImageFont, ImageOps

CENTERS = list(range(100, 701, 60))
POLARITIES = [1, -1]
METHODS = ["raised_cosine", "paper_lr_w8"]
REFERENCE_DEFAULT = Path("C:/Users/leechanghoon/Downloads/5D0ED11B-F431-49D4-84C4-E25AD8746E2C.png")
SUMMARY_NAMES = ["summary_01_am_refinement.png", "summary_02_eleven_bands.png",
                 "summary_03_stitch_unvalidated.png", "summary_04_phase_tf.png"]
PHASE_FILES = [
    ("phase_comparison.png", "AM / relative RF phase comparison"),
    ("relative_phase_hsv.png", "Relative RF phase HSV (not display RGB)"),
    ("line1050_phase_comparison.png", "Row 1050: phase before/after anti-alias reduction"),
    ("stft_three_rows.png", "STFT: three analysis rows"),
    ("stft_whole_frame.png", "STFT: whole stored frame"),
    ("phase_amplitude_mask.png", "Amplitude mask (not a confidence map)"),
]


def read_json(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as error:
        return {"_read_error": str(error)}
    return value if isinstance(value, dict) else {"_value": value}


def number(value, digits=4) -> str:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        return "pending"
    return f"{value:.{digits}f}"


def relative_url(path: Path, base: Path) -> str:
    return quote(os.path.relpath(path, base).replace(os.sep, "/"), safe="/._-+")


def json_safe(value):
    if isinstance(value, dict):
        return {key: json_safe(item) for key, item in value.items()}
    if isinstance(value, (tuple, list)):
        return [json_safe(item) for item in value]
    if isinstance(value, float) and not math.isfinite(value):
        return None
    return value


class Assets:
    def __init__(self, result_root: Path, gallery: Path):
        self.root, self.gallery = result_root, gallery
        self.referenced: set[str] = set()
        self.pending: set[str] = set()

    def get(self, relative: str | Path):
        path = self.root / relative
        key = Path(relative).as_posix()
        if path.is_file():
            self.referenced.add(key)
            return relative_url(path, self.gallery)
        self.pending.add(key)
        return None

    def json(self, relative: str | Path) -> dict:
        self.get(relative)
        return read_json(self.root / relative)


def compact_alignment(source: dict) -> dict:
    core = source.get("alignment", source)
    return {
        "status": core.get("status", "pending"),
        "train": core.get("train_unit_gain", {}),
        "test": core.get("test_unit_gain", {}),
        "effective_bins": core.get("effective_bin_count"),
        "span90_hz": core.get("energy_90_percent_span_hz"),
        "second_peak_ratio": core.get("second_peak_ratio"),
        "branch_offset_bins": source.get("selected_branch_offset_bins"),
        "boundary": source.get("selected_at_search_boundary", False),
        "branch_ambiguous": source.get("branch_ambiguous", False),
        "low_spectral_diversity": core.get("low_spectral_diversity", False),
        "competing_periodic_peak": core.get("competing_periodic_peak", False),
        "delay_samples": core.get("delay_samples"),
    }


def compact_synthesis(source: dict) -> dict:
    synthesis = source.get("synthesis", {})
    return {
        "am_train_test_correlation": source.get("am_train_test_correlation"),
        "output_rate_hz": synthesis.get("output_rate_hz"),
        "nominal_union_hz": synthesis.get("nominal_union_hz"),
        "edge_guard_hz": synthesis.get("edge_guard_hz"),
        "covered_frequency_measure_hz": synthesis.get("covered_frequency_measure_hz"),
        "internal_gap_bin_count": synthesis.get("internal_gap_bin_count"),
        "image_scaling": source.get("image_scaling"),
        "image_registration": source.get("image_registration"),
    }


def collect_data(assets: Assets, reference_url: str | None) -> dict:
    data = {"reference": reference_url, "single": [], "growth": [], "stitch": {}, "phase": [], "edges": [], "single_controls": []}
    for center in CENTERS:
        folder = Path("integer_controls") / f"fc{center}MHz"
        data["single"].append({"center": center, "image": assets.get(folder / "am_N16.png")})
    for center in [100, 340, 520]:
        folder = Path("am_refinement") / f"fc{center}MHz"
        meta = assets.json(folder / "metadata.json")
        data["growth"].append({
            "center": center, "metadata": assets.get(folder / "metadata.json"),
            "frame_log": assets.get(folder / "frame_log.csv"), "meta": meta,
            "frames": {str(n): {"am": assets.get(folder / f"am_N{n:02d}.png"),
                "coherent": assets.get(folder / f"coherent_adaptive_N{n:02d}.png")} for n in [1, 4, 8, 16, 32, 64]},
            "integer8": assets.get(folder / "am_integer_N08.png"),
            "text_crop": assets.get(folder / "text_region_AM64.png") if center == 100 or (assets.root / folder / "text_region_AM64.png").is_file() else None,
            "display_highpass": assets.get(folder / "am_N64_display_highpass.png"),
        })
    for polarity in POLARITIES:
        polarity_root = Path(f"stitch_polarity_{polarity:+d}")
        entries = []
        for first, second in zip(CENTERS, CENTERS[1:]):
            entries.append((f"pair_{first:03d}_{second:03d}", f"{first} + {second} MHz", "pair"))
        entries.extend([("group_100_700", "All 11 bands / nominal 720 MHz", "full"),
                        ("group_100_220", "100–220 MHz centers / 3 bands", "extra"),
                        ("group_100_400", "100–400 MHz centers / 6 bands", "extra"),
                        ("group_400_700", "400–700 MHz centers / 6 bands", "extra")])
        for name, label, kind in entries:
            folder = polarity_root / name
            alignment_source = assets.json(folder / "alignment.json") if kind == "pair" else {}
            alignment = compact_alignment(alignment_source) if kind == "pair" else None
            record = {"label": label, "kind": kind, "alignment": alignment,
                      "alignment_url": assets.get(folder / "alignment.json") if kind == "pair" else None,
                      "methods": {}}
            for method in METHODS:
                metrics = assets.json(folder / f"{method}_metrics.json")
                record["methods"][method] = {
                    "train": assets.get(folder / f"{method}_train.png"),
                    "heldout": assets.get(folder / f"{method}_heldout.png"),
                    "residual": assets.get(folder / f"{method}_row_column_residual.png"),
                    "metrics": compact_synthesis(metrics),
                    "metrics_url": assets.get(folder / f"{method}_metrics.json"),
                }
            data["stitch"][f"{polarity}:{name}"] = record
            if kind == "pair":
                audit_path = Path("clutter_audit") / f"polarity_{polarity:+d}" / f"{name}.json"
                audit = assets.json(audit_path)
                data["edges"].append({"polarity": polarity, "label": label, "alignment": alignment,
                    "alignment_url": record["alignment_url"], "audit_url": assets.get(audit_path),
                    "audit": {key: audit.get(key) for key in ["status", "original_fixed", "spectral_diversity_before",
                        "spectral_diversity_after", "retained_power_fraction", "masked_refit"] if key in audit}})
    for first, second in [(100, 160), (280, 340), (520, 580)]:
        for polarity in POLARITIES:
            folder = Path("single_frame_controls") / f"pair_{first:03d}_{second:03d}_polarity_{polarity:+d}"
            control = assets.json(folder / "single_frame_control.json")
            alignment = compact_alignment(assets.json(folder / "alignment.json"))
            data["single_controls"].append({"label": f"{first} + {second} MHz", "polarity": polarity,
                "alignment": alignment, "boundary": control.get("boundary", {}),
                "comparison": assets.get(folder / "comparison.png"),
                "train": assets.get(folder / "raised_cosine_train.png"),
                "heldout": assets.get(folder / "raised_cosine_heldout.png"),
                "metadata": assets.get(folder / "single_frame_control.json"),
                "training_frame": control.get("training_frame_zero_based"),
                "heldout_frame": control.get("heldout_frame_zero_based"),
                "metrics": compact_synthesis(assets.json(folder / "raised_cosine_metrics.json"))})
    data["single_controls_csv"] = assets.get("single_frame_controls/overview.csv")
    for center in [100, 520, 640]:
        folder = Path("phase_tf") / f"fc{center}MHz"
        data["phase"].append({"center": center, "meta": assets.json(folder / "metadata.json"),
            "metadata_url": assets.get(folder / "metadata.json"),
            "trace_csv": assets.get(folder / "line1050_phase_trace.csv"),
            "images": [{"label": label, "url": assets.get(folder / name)} for name, label in PHASE_FILES]})
    data["report_url"] = assets.get("REPORT.md")
    data["clutter_csv_url"] = assets.get("clutter_audit/overview.csv")
    data["timing_csv_url"] = assets.get("timing_model/overview.csv")
    return data


def font(size: int, bold=False):
    candidates = [Path("C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf"),
                  Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")]
    for path in candidates:
        if path.is_file():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def contact_sheet(root: Path, destination: Path, title: str, subtitle: str,
                  panels: list[tuple[str, str | Path]], columns: int, cell_width: int, image_height: int):
    """Compose already generated PNGs with labels; no pixel-value enhancement."""
    margin, gap, header, caption = 14, 10, 75, 57
    rows = math.ceil(len(panels) / columns)
    width = 2 * margin + columns * cell_width + (columns - 1) * gap
    cell_height = image_height + caption
    height = header + rows * cell_height + (rows - 1) * gap + margin
    canvas = Image.new("RGB", (width, height), "#e8edf2")
    draw = ImageDraw.Draw(canvas)
    title_size = 22
    while title_size > 13 and draw.textbbox((0, 0), title, font=font(title_size, True))[2] > width - 2 * margin:
        title_size -= 1
    draw.text((margin, 10), title, font=font(title_size, True), fill="#12253a")
    for line_index, line in enumerate(textwrap.wrap(subtitle, max(50, width // 8))[:2]):
        draw.text((margin, 38 + 16 * line_index), line, font=font(13), fill="#8d2024")
    for index, (label, relative) in enumerate(panels):
        x = margin + (index % columns) * (cell_width + gap)
        y = header + (index // columns) * (cell_height + gap)
        draw.rectangle((x, y, x + cell_width, y + cell_height), fill="white")
        path = root / relative
        if path.is_file():
            with Image.open(path) as source:
                displayed = ImageOps.contain(source.convert("RGB"), (cell_width - 8, image_height - 8), Image.Resampling.LANCZOS)
            canvas.paste(displayed, (x + (cell_width - displayed.width) // 2,
                                     y + (image_height - displayed.height) // 2))
        else:
            draw.text((x + 12, y + image_height // 2), "PENDING OUTPUT", font=font(16, True), fill="#7a8794")
        for line_index, line in enumerate(textwrap.wrap(label, max(20, cell_width // 8))[:3]):
            draw.text((x + 7, y + image_height + 4 + line_index * 15), line, font=font(13), fill="#12253a")
    canvas.save(destination, format="PNG", optimize=True)


def make_contacts(root: Path, gallery: Path):
    folder = Path("am_refinement/fc100MHz")
    contact_sheet(root, gallery / SUMMARY_NAMES[0], "iPhone 6 | 100 MHz AM reconstruction controls",
        "Display scaling differs per image. Adaptive controls are not held-out validation; source pixels only, no enhancement added here.",
        [("AM N64 text crop (existing output)", folder / "text_region_AM64.png"),
         ("AM N64 / fractional timing", folder / "am_N64.png"),
         ("Complex adaptive mean N64", folder / "coherent_adaptive_N64.png"),
         ("AM N8 / integer timing (same frames)", folder / "am_integer_N08.png"),
         ("AM N8 / fractional timing (same frames)", folder / "am_N08.png"),
         ("Complex adaptive mean N8 (same frames)", folder / "coherent_adaptive_N08.png")], 3, 345, 370)
    panels = [("Reference screenshot / user supplied", Path("gallery/reference.png"))]
    # A custom --output still uses the copied reference through a relative path.
    panels[0] = (panels[0][0], Path(os.path.relpath(gallery / "reference.png", root)))
    panels += [(f"fc {center} MHz | AM N16", Path(f"integer_controls/fc{center}MHz/am_N16.png")) for center in CENTERS]
    contact_sheet(root, gallery / SUMMARY_NAMES[1], "iPhone 6 | eleven single-band AM controls",
        "Independent display scaling; apparent brightness is not a physical SNR comparison. 120 MHz nominal bandwidth per capture.",
        panels, 6, 168, 300)
    panels = []
    for polarity in POLARITIES:
        base = Path(f"stitch_polarity_{polarity:+d}")
        for folder_name, method, label in [
            ("pair_100_160", "raised_cosine", "100+160 / raised cosine"),
            ("pair_520_580", "raised_cosine", "520+580 / raised cosine"),
            ("group_100_700", "raised_cosine", "All 11 / raised cosine"),
            ("group_100_700", "paper_lr_w8", "All 11 / source L-R W8")]:
            panels.append((f"IQ {polarity:+d} | {label} | TRAIN", base / folder_name / f"{method}_train.png"))
    contact_sheet(root, gallery / SUMMARY_NAMES[2], "Stitching controls | physical wideband reconstruction NOT validated",
        "720 MHz is the nominal RF union. Single-tone correlation, phase errors and branch ambiguity require independent validation.",
        panels, 4, 245, 350)
    panels = []
    for center in [100, 520, 640]:
        base = Path(f"phase_tf/fc{center}MHz")
        panels += [(f"fc {center} MHz | relative RF phase; not RGB", base / "phase_comparison.png"),
                   (f"fc {center} MHz | three-row STFT; ADC-count^2/Hz", base / "stft_three_rows.png")]
    contact_sheet(root, gallery / SUMMARY_NAMES[3], "Relative RF phase and time-frequency diagnostics",
        "A row/column is an analysis time grid, not verified pixel geometry. Phase and TF energy do not identify a physical driver source.",
        panels, 2, 520, 285)


HTML_TEMPLATE = r'''<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>iPhone 6 RF 복원 · stitching 실험</title>
<style>
:root{color-scheme:light;--ink:#182a3c;--muted:#586a7b;--line:#d4dfe8;--blue:#075ab1;--warn:#8c2020}
*{box-sizing:border-box}body{margin:0;background:#edf2f6;color:var(--ink);font:15px/1.55 system-ui,-apple-system,"Segoe UI","Malgun Gothic",sans-serif}
main{max-width:1500px;margin:auto;padding:28px 24px 70px}h1{font-size:32px;margin:0 0 8px}h2{font-size:24px;margin:0 0 14px}h3{font-size:19px;margin:20px 0 9px}
p{margin:8px 0 16px}a{color:var(--blue)}nav{display:flex;gap:15px;flex-wrap:wrap;margin:22px 0}section{background:white;border:1px solid var(--line);border-radius:12px;padding:22px;margin:22px 0;scroll-margin:20px}
.warn{background:#fff0ee;color:var(--warn);border-left:5px solid #b62c27;padding:14px 17px;margin:14px 0}.note{color:var(--muted);font-size:14px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:14px}.growth{grid-template-columns:repeat(4,minmax(0,1fr))}.compare{grid-template-columns:repeat(3,minmax(0,1fr))}.phase-grid{grid-template-columns:repeat(2,minmax(0,1fr))}
figure{margin:0;padding:10px;background:#f4f7fa;border:1px solid var(--line);border-radius:8px;min-width:0}figure img{display:block;max-width:100%;max-height:540px;margin:auto;object-fit:contain;background:#e4ebf1}figure.wide img{max-height:850px}figcaption{margin:9px 0 0;overflow-wrap:anywhere}figcaption small{display:block;color:var(--muted);font-size:12px}.placeholder{min-height:180px;display:grid;place-items:center;background:#e9eef2;color:var(--muted)}
.controls{display:flex;gap:16px;flex-wrap:wrap;margin:12px 0 18px;padding:14px;background:#edf4fc;border-radius:8px}.controls label{display:flex;flex-direction:column;gap:5px;font-weight:600}select{font:inherit;padding:7px;border:1px solid #a8bdd1;border-radius:5px;background:white}button{font:inherit;cursor:pointer;background:#e8f1fc;border:1px solid #aac2db;border-radius:6px;padding:7px 12px}
.table-wrap{overflow:auto}table{border-collapse:collapse;width:100%;font-size:13px}th,td{border-bottom:1px solid var(--line);padding:9px;text-align:right;white-space:nowrap}th{background:#eff4f9;position:sticky;top:0}th:first-child,td:first-child{text-align:left}.flags{white-space:normal;min-width:170px;text-align:left;color:var(--warn)}.metricbar{width:70px;height:5px;background:#dce7ef;margin-top:3px}.metricbar i{height:5px;display:block;background:#2472b8}.status{display:inline-block;border-radius:4px;background:#edf2f7;padding:1px 6px;font-size:12px;color:#425970}
.facts{display:flex;gap:10px;flex-wrap:wrap}.facts span{background:#e9f1f8;padding:7px 11px;border-radius:6px}.links{display:flex;gap:12px;flex-wrap:wrap}.reference-grid{display:grid;grid-template-columns:minmax(200px,360px) 1fr;gap:18px}.reference-grid img{max-height:620px}details{margin:14px 0}summary{cursor:pointer;font-weight:650}.full-layout{display:grid;grid-template-columns:minmax(240px,550px) 1fr;gap:20px}.full-layout .note{align-self:start}code{background:#eaf0f6;padding:1px 4px;border-radius:3px}
@media(max-width:800px){main{padding:16px 10px}.growth,.compare,.phase-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.reference-grid,.full-layout{grid-template-columns:1fr}section{padding:14px}h1{font-size:25px}figure img{max-height:430px}}
@media(max-width:480px){.growth,.compare,.phase-grid{grid-template-columns:1fr}}
</style></head><body><main>
<header><h1>iPhone 6 · RF 화면 복원과 stitching</h1><p class="note">저장된 MATLAB 결과를 탐색하는 오프라인 갤러리 · 생성 시각 __GENERATED__ · 외부 라이브러리/네트워크 요청 없음</p>
<div class="warn"><strong>전체 720 MHz의 물리적 coherent stitching은 검증되지 않았습니다.</strong><br>720 MHz는 11개 측정의 명목 RF 합집합입니다. 생성된 화면, 높은 coherence 또는 AM train/test 상관만으로 영상 복원 정확도·넓은 대역의 위상 일치·MIPI 디코딩 성공을 판단하지 않습니다.</div>
<div class="facts"><span>iPhone 6 / 사용자 테스트 화면</span><span>저장 IQ: 124.0828 MS/s</span><span>사용자 진술 BW: 120 MHz</span><span>fc: 100:60:700 MHz</span><span>명목 RF: 40–760 MHz</span><span>인접 10쌍: 각 180 MHz</span></div>
<nav><a href="#reference">원본과 대표 복원</a><a href="#single">11개 대역</a><a href="#growth">평균 frame 수 / N8 대조</a><a href="#stitch">Stitching 비교</a><a href="#single-control">단일 frame stitching 대조</a><a href="#quality">정렬 수치</a><a href="#phase">위상·STFT</a><a href="#files">보존·자료</a></nav></header>
<section id="reference"><h2>원본과 대표 AM 복원</h2><div id="reference-content" class="reference-grid"></div><p class="note">원본은 사용자 제공 screenshot입니다. 복원 화면에 원본 글자를 삽입하거나 생성한 내용은 없습니다. 표시 contrast와 crop을 신호 복원 자체와 구분합니다.</p></section>
<section id="single"><h2>11개 단일 대역 · AM 16 frames</h2><p class="note">모든 중심주파수를 같은 순서로 표시합니다. 개별 이미지의 표시 범위가 달라 밝기만으로 물리적 SNR을 비교할 수 없습니다. 클릭하면 원래 해상도 PNG를 엽니다.</p><div id="single-grid" class="grid"></div></section>
<section id="growth"><h2>Frame 수에 따른 변화와 같은 N=8 대조</h2><p class="note">AM refinement는 각 frame에서 timing을 적응적으로 추정합니다. Complex adaptive mean은 각 frame의 phase도 추정합니다. 이 화면은 복원 대조이며 고정 모델의 held-out 검증이 아닙니다. Frame 수가 다른 이미지만으로 fractional resampling 효과를 단정하지 않도록 같은 0–7번 frames의 N8 대조를 별도로 표시합니다.</p><div class="controls"><label>표시할 평균 종류<select id="growth-kind"><option value="am">AM mean</option><option value="coherent">Complex adaptive mean</option></select></label></div><div id="growth-content"></div></section>
<section id="stitch"><h2>인접 10쌍과 전체 11개 합성</h2><p class="warn">이 섹션의 합성은 검증용 실험 출력입니다. Full-band 물리적 복원이 검증됐다는 표시가 아닙니다. IQ polarity도 하드웨어 기준으로 확인되지 않았습니다.</p>
<div class="controls"><label>IQ 부호<select id="polarity"><option value="1">I+jQ (+1)</option><option value="-1">I−jQ (−1)</option></select></label><label>Overlap weighting<select id="method"><option value="raised_cosine">Support-limited raised cosine</option><option value="paper_lr_w8">원문 L-R W8</option></select></label><label>평가 구간<select id="split"><option value="train">Training frames 0–7</option><option value="heldout">Held-out frames 16–23</option></select></label></div>
<p id="stitch-description" class="note"></p><h3>인접 2개씩 · 명목 폭 180 MHz</h3><div id="pairs-grid" class="grid"></div><h3>전체 11개 · 명목 폭 720 MHz</h3><div id="full-content" class="full-layout"></div><details><summary>추가 연속 대역 조합</summary><div id="extra-grid" class="compare grid"></div></details>
</section>
<section id="single-control"><h2>평균·θ derotation을 제외한 단일 frame stitching 대조</h2><p class="note">0번 frame으로 branch/delay/phase를 추정하고 16번 frame에 고정 적용했습니다. Coherent frame averaging과 fitted Floquet θ derotation은 사용하지 않습니다. 기존 timing resampling과 fixed training DC 제거는 남아 있습니다. 단일 frame의 SNR과 endpoint mismatch도 달라지므로 한 조건만 바꾼 원인 규명으로 취급하지 않습니다.</p><p class="warn">Finite frame의 periodic FFT/circular-delay 근사와 nominal RF translation을 사용한 실험 대조입니다. 이 결과도 검증된 광대역 물리 복원이 아닙니다.</p><div id="single-control-grid" class="compare grid"></div><div id="single-control-table" class="table-wrap"></div></section>
<section id="quality"><h2>Overlap 정렬의 수치와 모호성</h2><p class="note">아래 coherence는 saved training delay/phase를 적용한 복소 교차합의 정규화 크기입니다. 위상 예측 오차를 포함하는 지표가 아니며 단일 tone에도 크게 나올 수 있습니다. Effective bins, 에너지 5–95% 폭, held-out phase/error, competing peak와 검색 경계 도달 여부를 함께 읽어야 합니다. 이 표는 복원 정확도 순위가 아닙니다.</p><div id="edge-table" class="table-wrap"></div>
<h3>Training 상위10 bins ±8 제거 · 동일 mask held-out 적용</h3><p class="note">선택된 integer branch는 유지합니다. 고정 delay/phase의 전후 변화와 masked training만 재정렬한 결과를 구분합니다. 해당 bin이 물리적으로 clutter임을 증명하는 검사는 아닙니다.</p><div id="audit-table" class="table-wrap"></div></section>
<section id="phase"><h2>상대 RF 위상과 시간–주파수</h2><p class="warn">HSV hue는 상대 수신 IQ 위상이며 원본 화면 RGB가 아닙니다. Low-amplitude mask는 신뢰도 확률이 아닙니다. 안정된 세로선/위상 또는 TF 에너지만으로 LCD driver·MIPI common mode의 기원을 확정할 수 없습니다.</p><p class="note">1100×1881은 분석 시간 격자입니다. 한 column의 연속 row 값은 한 row 주기씩 떨어진 samples이며 하나의 연속 column 시간 구간이 아닙니다. RF 축은 I+jQ와 nominal fc를 가정합니다. STFT zero padding의 bin spacing은 실제 분해능과 다릅니다.</p><div id="phase-content"></div></section>
<section id="files"><h2>자료와 재현</h2><div id="resource-links" class="links"></div><p>Git 미리보기는 아래 작은 PNG 4장과 원본 screenshot만 보존합니다. 전체 해상도 이미지는 views release bundle의 결과 폴더 구조를 유지해 압축 해제한 뒤 이 <code>gallery/index.html</code>을 여세요. 이 HTML은 전체 PNG를 중복 저장하지 않고 상대 경로로 참조합니다.</p><div id="summary-grid" class="grid"></div><p class="note">갤러리 생성기는 기존 PNG의 배치·축소만 수행합니다. IQ/MAT 읽기, 추가 DSP, image enhancement, registration, 새로운 SNR/복원 정확도 계산은 수행하지 않습니다. Raw RIS는 수정하지 않습니다.</p></section>
</main><script id="gallery-data" type="application/json">__DATA__</script><script>
'use strict';
const D=JSON.parse(document.getElementById('gallery-data').textContent);
const $=id=>document.getElementById(id);
const fmt=(x,n=4)=>typeof x==='number'&&Number.isFinite(x)?x.toFixed(n):'pending';
const unit=(x,multiplier)=>typeof x==='number'&&Number.isFinite(x)?x*multiplier:NaN;
function node(tag,text,cls){const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;}
function link(url,label){if(!url)return node('span',label+' (pending)','note');const a=node('a',label);a.href=url;a.target='_blank';a.rel='noopener';return a;}
function figure(url,label,detail='',wide=false){const f=node('figure',undefined,wide?'wide':'');if(url){const a=link(url,'');const img=document.createElement('img');img.src=url;img.alt=label;img.loading='lazy';img.decoding='async';a.append(img);f.append(a);}else f.append(node('div','Pending output','placeholder'));const cap=node('figcaption',label);if(detail)cap.append(node('small',detail));f.append(cap);return f;}
function warningText(a){if(!a||a.status==='pending')return 'pending';const w=[];if(a.low_spectral_diversity)w.push('low spectral diversity');if(a.competing_periodic_peak)w.push('competing delay peak');if(a.branch_ambiguous)w.push('ambiguous integer branch');if(a.boundary)w.push('search boundary reached');if(a.status==='ambiguous_periodic_estimate'&&!w.length)w.push('ambiguous estimate');return w.join('; ')||'No flag in source; not a validation pass';}
function appendLinks(parent,items){const p=node('p',undefined,'links');for(const [url,label]of items)p.append(link(url,label));parent.append(p);}
function drawReference(){const host=$('reference-content');host.append(figure(D.reference,'사용자 제공 원본 · 750×1334 screenshot'));const box=node('div');const g=D.growth.find(x=>x.center===100);box.append(figure(g?.text_crop,'100 MHz · AM N64 text crop','기존 MATLAB crop; 여기에 새로운 처리를 추가하지 않음',true));if(g)appendLinks(box,[[g.frames['64'].am,'전체 AM64'],[g.frames['64'].coherent,'Complex adaptive N64'],[g.metadata,'metadata']]);host.append(box);}
function drawGrowth(){const host=$('growth-content');host.replaceChildren();const kind=$('growth-kind').value;for(const b of D.growth){host.append(node('h3',b.center+' MHz · '+(kind==='am'?'AM':'Complex adaptive')+' N=1/4/16/64'));const grid=node('div',undefined,'growth grid');for(const n of [1,4,16,64])grid.append(figure(b.frames[String(n)][kind],'N='+n,kind==='am'?'Adaptive envelope timing':'Per-frame timing and phase fit'));host.append(grid);const meta=b.meta||{};host.append(node('p','period '+fmt(meta.period_samples,6)+' input samples; median AM correlation '+fmt(meta.median_am_correlation)+'; median complex correlation '+fmt(meta.median_complex_correlation)+'. Descriptive per-frame fit, not held-out validation.','note'));host.append(node('h3','같은 N8 / 같은 source frames 0–7'));const same=node('div',undefined,'compare grid');same.append(figure(b.integer8,'AM integer timing · N8'));same.append(figure(b.frames['8'].am,'AM fractional/adaptive timing · N8'));same.append(figure(b.frames['8'].coherent,'Complex adaptive · N8'));host.append(same);appendLinks(host,[[b.metadata,'metadata'],[b.frame_log,'frame log CSV'],[b.frames['32'].am,'AM N32'],[b.frames['64'].am,'AM N64'],[b.display_highpass,'N64 display high-pass (별도 enhancement)']]);}}
function synthesisDetail(m){return 'Nominal union '+fmt(unit(m.nominal_union_hz,1e-6),3)+' MHz; output computation rate '+fmt(unit(m.output_rate_hz,1e-6),3)+' MS/s; AM train/test r='+fmt(m.am_train_test_correlation)+' (repeatability only, not fidelity/SNR).';}
function drawStitch(){const p=$('polarity').value,m=$('method').value,s=$('split').value;const pairs=$('pairs-grid'),full=$('full-content'),extra=$('extra-grid');pairs.replaceChildren();full.replaceChildren();extra.replaceChildren();$('stitch-description').textContent=m==='raised_cosine'?'Raised cosine는 support 제한 및 3 MHz edge guard를 사용합니다. 원문 L-R과 유효 support가 같지 않습니다.':'원문 L-R W8 응답은 source Fs_filter=2B에서 평가되고 power-of-two 출력 격자에 배치됩니다. 비overlap 감쇠를 정규화로 제거하지 않은 대조입니다.';for(const [key,rec] of Object.entries(D.stitch)){if(!key.startsWith(p+':'))continue;const method=rec.methods[m],a=rec.alignment;let desc=synthesisDetail(method.metrics);if(a)desc+=' Held-out complex rho='+fmt(a.test.complex_coherence)+'; effective bins='+fmt(a.effective_bins,2)+'; '+warningText(a);const fig=figure(method[s],rec.label+' · '+s,desc,rec.kind==='full');if(rec.kind==='pair')pairs.append(fig);if(rec.kind==='extra')extra.append(fig);if(rec.kind==='full'){full.append(fig);const box=node('div');box.append(node('p','물리적 full-band coherent stitching 미검증','warn'));box.append(node('p',desc));box.append(node('p','표시되는 720 MHz는 명목 폭입니다. 출력 sample rate는 계산용 주기 격자의 값이며 입력 IQ률, 유효 물리적 복원 대역폭, MIPI bitrate와 다릅니다.','note'));appendLinks(box,[[method.metrics_url,'합성 metrics JSON'],[method.residual,'Row/column residual (별도 display control)']]);full.append(box);}}}
function makeTable(headers){const table=node('table'),head=node('thead'),tr=node('tr'),body=node('tbody');for(const text of headers)tr.append(node('th',text));head.append(tr);table.append(head,body);return [table,body];}
function metricCell(value,digits=4,bar=false){const td=node('td',fmt(value,digits));if(bar&&typeof value==='number'&&Number.isFinite(value)){const track=node('div',undefined,'metricbar'),fill=node('i');fill.style.width=Math.max(0,Math.min(1,value))*100+'%';track.append(fill);td.append(track);}return td;}
function drawQuality(){const [table,body]=makeTable(['IQ / pair (MHz)','Train |ρ|','Held-out |ρ|','Effective bins','5–95% span (MHz)','Test phase (rad)','Test error','2nd/1st peak','Branch bins','Warnings']);for(const e of D.edges){const a=e.alignment,tr=node('tr'),label=node('td');label.append(link(e.alignment_url,(e.polarity>0?'+1':'−1')+' / '+e.label));tr.append(label,metricCell(a.train.complex_coherence,4,true),metricCell(a.test.complex_coherence,4,true),metricCell(a.effective_bins,2),metricCell(unit(a.span90_hz,1e-6),5),metricCell(a.test.residual_cross_phase_rad,4),metricCell(a.test.normalized_complex_error,4),metricCell(a.second_peak_ratio,6),metricCell(a.branch_offset_bins,0),node('td',warningText(a),'flags'));body.append(tr);}$('edge-table').append(table);const [at,ab]=makeTable(['IQ / pair','Audit','Test |ρ| before','Test |ρ| fixed after','Test |ρ| refit after','Retained test A/B','Effective bins after','Refit test phase','Refit test error']);for(const e of D.edges){const a=e.audit||{},before=a.original_fixed?.before?.test||{},after=a.original_fixed?.after?.test||{},refit=a.masked_refit?.test_unit_gain||{},r=a.retained_power_fraction||{},tr=node('tr'),label=node('td');label.append(link(e.audit_url,(e.polarity>0?'+1':'−1')+' / '+e.label));tr.append(label,node('td',a.status||'pending'),metricCell(before.complex_coherence),metricCell(after.complex_coherence),metricCell(refit.complex_coherence),node('td',fmt(r.overlap_test_a,4)+' / '+fmt(r.overlap_test_b,4)),metricCell(a.spectral_diversity_after?.effective_bin_count,2),metricCell(refit.residual_cross_phase_rad),metricCell(refit.normalized_complex_error));ab.append(tr);}$('audit-table').append(at);}
function drawSingleControl(){const grid=$('single-control-grid');const [table,body]=makeTable(['IQ / pair (MHz)','Train |ρ|','Held-out |ρ|','Effective bins','Test phase (rad)','Test error','2nd/1st peak','Warnings']);for(const c of D.single_controls){const a=c.alignment;const card=figure(c.comparison,(c.polarity>0?'+1':'−1')+' / '+c.label+' / one frame','Left: training frame '+c.training_frame+'; right: held-out frame '+c.heldout_frame+'. Frozen training display scale.',true);appendLinks(card,[[c.train,'train PNG'],[c.heldout,'held-out PNG'],[c.metadata,'control JSON']]);grid.append(card);const tr=node('tr');tr.append(node('td',(c.polarity>0?'+1':'−1')+' / '+c.label),metricCell(a.train.complex_coherence,4,true),metricCell(a.test.complex_coherence,4,true),metricCell(a.effective_bins,2),metricCell(a.test.residual_cross_phase_rad),metricCell(a.test.normalized_complex_error),metricCell(a.second_peak_ratio,6),node('td',warningText(a),'flags'));body.append(tr);}$('single-control-table').append(table);appendLinks($('single-control-table'),[[D.single_controls_csv,'Single-frame control CSV']]);}
function drawPhase(){const host=$('phase-content');for(const b of D.phase){host.append(node('h3',b.center+' MHz'));const m=b.meta||{},l=m.line_stft||{},f=m.frame_stft||{};host.append(node('p','Analysis row '+fmt(unit(m.analysis_row_seconds,1e6),6)+' µs; time step '+fmt(unit(m.analysis_column_time_step_seconds,1e9),4)+' ns. Three-row STFT window '+fmt(unit(l.window_duration_seconds,1e6),4)+' µs / ENBW '+fmt(unit(l.enbw_hz,1e-3),3)+' kHz; frame STFT window '+fmt(unit(f.window_duration_seconds,1e6),4)+' µs / ENBW '+fmt(unit(f.enbw_hz,1e-3),3)+' kHz.','note'));if(m.phase_reference_rule)host.append(node('p','Phase reference: '+m.phase_reference_rule+'. Across-band absolute phase comparison: unavailable.','note'));const grid=node('div',undefined,'phase-grid grid');for(const item of b.images)grid.append(figure(item.url,item.label,'Existing MATLAB output',true));host.append(grid);appendLinks(host,[[b.metadata_url,'Phase/STFT metadata'],[b.trace_csv,'Row1050 phase trace CSV']]);}}
function drawFiles(){appendLinks($('resource-links'),[[D.report_url,'연구 보고서'],[D.clutter_csv_url,'Clutter audit CSV'],[D.timing_csv_url,'Timing model CSV'],['manifest.json','갤러리 manifest'],['README.md','오프라인 사용 안내']]);for(const [index,name]of D.summary_names.entries())$('summary-grid').append(figure(name,'Git preview '+(index+1)));}
drawReference();for(const b of D.single)$('single-grid').append(figure(b.image,b.center+' MHz · AM N16'));drawGrowth();drawStitch();drawQuality();drawSingleControl();drawPhase();drawFiles();$('growth-kind').addEventListener('change',drawGrowth);for(const id of ['polarity','method','split'])$(id).addEventListener('change',drawStitch);
</script></body></html>'''


def write_gallery(root: Path, gallery: Path, reference: Path):
    gallery.mkdir(parents=True, exist_ok=True)
    reference_target = gallery / "reference.png"
    reference_source = None
    if reference.is_file():
        if reference.resolve() != reference_target.resolve():
            shutil.copy2(reference, reference_target)
        reference_source = str(reference)
    reference_url = "reference.png" if reference_target.is_file() else None
    assets = Assets(root, gallery)
    data = collect_data(assets, reference_url)
    data["summary_names"] = SUMMARY_NAMES
    generated = datetime.now(timezone.utc).isoformat(timespec="seconds")
    embedded = json.dumps(json_safe(data), ensure_ascii=False, allow_nan=False, separators=(",", ":")).replace("</", "<\\/")
    page = HTML_TEMPLATE.replace("__DATA__", embedded).replace("__GENERATED__", html.escape(generated))
    (gallery / "index.html").write_text(page, encoding="utf-8")
    make_contacts(root, gallery)
    previews = []
    for name in SUMMARY_NAMES:
        path = gallery / name
        with Image.open(path) as image:
            dimensions = list(image.size)
        previews.append({"file": name, "bytes": path.stat().st_size, "dimensions_px": dimensions,
                         "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    manifest = {"generated_utc": generated, "script": str(Path(__file__).resolve()),
        "result_root": str(root), "gallery_root": str(gallery),
        "scope": "Existing PNG/JSON presentation only; no IQ/MAT reads, DSP, enhancement or fidelity estimation.",
        "stitch_validation": "Full 720 MHz coherent physical reconstruction is NOT validated.",
        "reference_source": reference_source, "reference_copy": reference_url,
        "reference_sha256": hashlib.sha256(reference_target.read_bytes()).hexdigest() if reference_url else None,
        "summary_png_count": len(previews), "summaries": previews,
        "referenced_existing_result_files": sorted(assets.referenced),
        "pending_result_files": sorted(assets.pending),
        "release_bundle_instruction": "Preserve the result-root directory structure. gallery/index.html uses relative local URLs; no web server is required."}
    (gallery / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    readme = ["# iPhone 6 stitching gallery", "", "[Open the offline gallery](index.html)", "",
              "**Full 720 MHz coherent physical reconstruction is not validated.** The union is nominal RF coverage, not a demonstrated recovered physical bandwidth.", "",
              "The four PNGs below are compact Git previews. Full-resolution images are referenced by relative path and belong in the views release bundle. Preserve the parent result folder tree when extracting that bundle. No network or external library is used by the HTML.", "",
              "The gallery generator performs only PNG layout/resizing and reads saved JSON metrics. It does not read IQ/MAT files, apply DSP or enhancement, or calculate image fidelity.", ""]
    for index, name in enumerate(SUMMARY_NAMES, 1):
        readme += [f"## Preview {index}", "", f"![Summary {index}]({name})", ""]
    readme += ["## Rebuild", "", "Run tools/make_iphone_stitch_gallery.py after all MATLAB output stages finish. Missing outputs are shown as pending. Generated gallery files may be replaced; raw captures and existing MATLAB outputs are never modified.", "", "See manifest.json for source assets and missing outputs.", ""]
    (gallery / "README.md").write_text("\n".join(readme), encoding="utf-8")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--result-root", type=Path,
                        default=Path(__file__).resolve().parents[1] / "results" / "iphone6_stitch_20261023")
    parser.add_argument("--output", type=Path, help="Default: <result-root>/gallery")
    parser.add_argument("--reference", type=Path, default=REFERENCE_DEFAULT)
    args = parser.parse_args()
    root = args.result_root.resolve()
    if not root.is_dir():
        parser.error(f"Result directory does not exist: {root}")
    gallery = args.output.resolve() if args.output else root / "gallery"
    manifest = write_gallery(root, gallery, args.reference)
    print(json.dumps({"index": str(gallery / "index.html"),
        "summary_png_count": manifest["summary_png_count"],
        "summary_total_bytes": sum(item["bytes"] for item in manifest["summaries"]),
        "referenced_result_files": len(manifest["referenced_existing_result_files"]),
        "pending_result_files": len(manifest["pending_result_files"])}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
