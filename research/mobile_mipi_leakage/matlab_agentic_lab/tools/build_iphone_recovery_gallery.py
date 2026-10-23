"""Display reviewed MATLAB iPhone exports; performs no signal processing.

Usage: python -X utf8 build_iphone_recovery_gallery.py [--result-dir PATH]
       Add --embed-images to produce an HTML file containing local image bytes.
"""
from __future__ import annotations

import argparse
import base64
import csv
import html
import json
import mimetypes
from pathlib import Path
from urllib.parse import quote

DEFAULT_ROOT = Path(__file__).resolve().parents[1] / "results" / "iphone_recovery_20261023"


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def number(value: object, divisor: float = 1.0, digits: int = 6) -> str:
    if value is None or isinstance(value, bool):
        return "미기록"
    try:
        result = float(value) / divisor
    except (TypeError, ValueError):
        return "미기록"
    if not -float("inf") < result < float("inf"):
        return "미기록"
    formatted = f"{result:,.{digits}f}"
    return formatted.rstrip("0").rstrip(".") if digits else formatted


def source_label(value: object) -> str:
    if isinstance(value, dict):
        for name in ("path", "filename", "raw_file", "id"):
            if value.get(name):
                return str(value[name])
        return json.dumps(value, ensure_ascii=False)
    return str(value) if value is not None else "원본 경로 미기록"


def load_items(summary: Path) -> list[dict]:
    payload = json.loads(summary.read_text(encoding="utf-8-sig"))
    if isinstance(payload, dict):
        for name in ("items", "results", "devices", "presentation"):
            if isinstance(payload.get(name), list):
                payload = payload[name]
                break
    if not isinstance(payload, list) or not all(isinstance(item, dict) for item in payload):
        raise ValueError("Summary must be an array of result records.")
    if not payload:
        raise ValueError("Summary contains no result records.")
    return payload


def build_gallery(root: Path, items: list[dict], embed: bool = False) -> tuple[str, list[str]]:
    root = root.resolve()
    warnings = []

    def figure(relative: object, label: str, optional: bool = False) -> str:
        if not relative:
            warnings.append(f"Image not recorded: {label}")
            return "" if optional else '<p class="missing">' + esc(label) + ': 파일 미기록</p>'
        asset = (root / str(relative)).resolve()
        if not asset.is_relative_to(root):
            raise ValueError(f"Image outside result directory: {relative}")
        if not asset.is_file():
            warnings.append(f"Image not found: {relative}")
            return "" if optional else '<p class="missing">' + esc(label) + ': 파일 없음 <code>' + esc(relative) + '</code></p>'
        if asset.suffix.lower() not in (".png", ".jpg", ".jpeg", ".webp", ".gif"):
            raise ValueError(f"Unsupported image type: {relative}")
        if embed:
            mime = mimetypes.guess_type(asset.name)[0] or "application/octet-stream"
            url = "data:" + mime + ";base64," + base64.b64encode(asset.read_bytes()).decode("ascii")
        else:
            url = quote(asset.relative_to(root).as_posix(), safe="/")
        return ('<figure><a href="' + esc(url) + '" target="_blank" rel="noopener">'
                '<img loading="lazy" src="' + esc(url) + '" alt="' + esc(label) + '"></a>'
                '<figcaption>' + esc(label) + '</figcaption></figure>')

    def progression(item: dict) -> str:
        recorded = item.get("full_output_folder")
        if not recorded:
            warnings.append(f"Frame progression folder not recorded: {item.get('key')}")
            return ""
        folder = Path(str(recorded)).resolve()
        if not folder.is_relative_to(root):
            warnings.append(f"Frame progression folder outside result directory: {recorded}")
            return '<p class="missing">프레임 누적 폴더가 결과 디렉터리 밖에 있어 연결하지 않았습니다.</p>'
        relative_folder = folder.relative_to(root)
        csv_path = folder / "frame_progression.csv"
        records = []
        if csv_path.is_file():
            with csv_path.open(encoding="utf-8-sig", newline="") as stream:
                records = list(csv.DictReader(stream))
        else:
            warnings.append(f"Frame progression CSV not found: {relative_folder.as_posix()}")
        fields = [
            ("frames", "P", 0),
            ("am_odd_even_correlation", "홀짝 AM 상관", 6),
            ("mean_coherent_over_incoherent", "행 위상 보정 평균/AM 비", 6),
            ("uncorrected_coherent_power_counts2", "무보정 전력 (count²)", 3),
            ("global_coherent_power_counts2", "Global 보정 전력 (count²)", 3),
            ("row_coherent_power_counts2", "Row 보정 전력 (count²)", 3),
            ("fractional_vs_nearest_relative_rms", "Cubic/nearest 상대 RMS 차이", 6),
        ]
        body = ""
        for record in records:
            cells = []
            for field, _, digits in fields:
                value = number(record.get(field), digits=digits)
                if field == "am_odd_even_correlation" and record.get("frames") == "1":
                    value = "해당 없음 (P1)"
                cells.append('<td>' + esc(value) + '</td>')
            body += '<tr>' + ''.join(cells) + '</tr>'
        table = ""
        if records:
            table = ('<div class="table-scroll"><table><thead><tr>'
                     + ''.join('<th>' + esc(label) + '</th>' for _, label, _ in fields)
                     + '</tr></thead><tbody>' + body + '</tbody></table></div>')
        checkpoints = []
        for frame_count in (1, 4, 8, 16, 32, 64):
            relative = relative_folder / f"P{frame_count:03d}_comparison.png"
            if (root / relative).is_file():
                checkpoints.append('<details class="checkpoint"><summary>P' + str(frame_count)
                                   + ' — 처리 중 저장된 비교 영상</summary>'
                                   + figure(relative.as_posix(), f"P{frame_count} 누적 checkpoint — 저장된 crop와 표시 유지")
                                   + '</details>')
        csv_link = ""
        if csv_path.is_file():
            csv_link = ('<a href="' + quote(csv_path.relative_to(root).as_posix(), safe="/")
                        + '">frame_progression.csv 원문</a>')
        return ('<div class="progression"><h3>프레임 누적 과정</h3>'
                '<p class="muted">아래 checkpoint는 처리 중 저장된 crop와 표시를 유지합니다. '
                '위 최종 presentation의 자동 crop·대비와 다를 수 있습니다. '
                '복소/진폭 비는 위치별 |복소평균|/진폭평균의 평균이며, 전력 변화는 SNR 이득이 아닙니다.</p>'
                + table + '<p>' + csv_link + '</p>' + ''.join(checkpoints) + '</div>')

    cards, nav = [], []
    for index, item in enumerate(items, 1):
        title = str(item.get("title") or item.get("key") or f"결과 {index}")
        if item.get("frames") is not None:
            title += " · P" + number(item.get("frames"), digits=0)
        anchor = f"result-{index}"
        nav.append('<li><a href="#' + anchor + '">' + str(index) + '. ' + esc(title) + '</a></li>')
        metadata = [
            ("기록 ID", item.get("key", "미기록")),
            ("원본 캡처", source_label(item.get("source"))),
            ("Stored IQ Fs", number(item.get("fs_hz"), 1e6) + " MS/s"),
            ("기록상 RF 중심", number(item.get("fc_hz"), 1e6) + " MHz"),
            ("기록상 수신 BW", number(item.get("bandwidth_hz"), 1e6) + " MHz"),
            ("누적 frame 수", number(item.get("frames"), digits=0)),
            ("홀짝 AM 상관", number(item.get("am_odd_even_correlation"))),
            ("행 위상 보정 평균/AM 비", number(item.get("coherent_over_am"))),
            ("원시 samples / 출력 raster cell", number(item.get("samples_per_output_raster_cell"))),
            ("Crop 방식", item.get("crop_method") or "미기록"),
            ("표시 크기 (row × column)", number(item.get("crop_rows"), digits=0) + " × "
             + number(item.get("crop_columns"), digits=0)),
            ("Crop 시작 row / column", number(item.get("crop_row_start"), digits=0) + " / "
             + number(item.get("crop_column_start"), digits=0)),
        ]
        table = '<dl>' + ''.join('<dt>' + esc(label) + '</dt><dd>' + esc(value) + '</dd>'
                                 for label, value in metadata) + '</dl>'
        preview = figure(item.get("preview"), title + " — 처리 단계 비교")
        single = ''.join([
            figure(item.get("am"), "AM 대조군 — 원시 IQ에서 계산한 진폭 복원"),
            figure(item.get("cleaned"), "열 평균 제거 처리본 — 화면 성분도 함께 제거될 수 있음"),
            figure(item.get("phase"), "위상 HSV — 상대 측정 위상, 원래 화면 RGB 아님"),
        ])
        extra = item.get("processing_note") or item.get("note") or item.get("display_filter_caveat")
        note = '<p class="item-note">' + esc(extra) + '</p>' if extra else ""
        if str(item.get("key", "")).startswith("password_105"):
            note += ('<p class="finding unresolved"><strong>105 MHz: 반복 간섭 우세, 비밀번호 화면 미확인.</strong> '
                     '높은 홀짝 AM 상관만으로 화면 복원에 성공했다고 판단할 수 없습니다.</p>')
        elif str(item.get("key", "")).startswith("iphone6s"):
            note += '<p class="finding">iPhone 6s: 원형 키패드와 숫자·버튼 구조가 확인됩니다. 세로선은 남아 있습니다.</p>'
        else:
            note += ('<p class="finding">기존 iPhone 6 캡처: 키패드 또는 홈 UI 구조가 관찰됩니다. '
                     'P32에서는 상관이 높아져도 번짐이 남으며, 상관 상승이 화면 복원 성능 향상을 보장하지 않습니다.</p>')
        cards.append('<section class="card" id="' + anchor + '"><h2>' + esc(title) + '</h2>'
                     + table + note + preview + '<details><summary>각 영상 확대: AM 대조군 · 열 성분 제거 · 위상</summary>'
                     + '<div class="individual">' + single + '</div></details>' + progression(item) + '</section>')

    archive = figure("archive_P008/archive_survey_am.png", "기존 6개 캡처 P8 AM 비교 — 과거 처리 기준점", True)
    timing = figure("password_timing_preview/timing_candidate_comparison.png", "화면 timing 후보 비교 — 선택 전 후보 진단", True)
    supplement = ""
    if archive or timing:
        nav.append('<li><a href="#controls">기존 결과 및 timing 대조</a></li>')
        supplement = '<section class="card" id="controls"><h2>기존 결과 및 timing 대조</h2>' + archive + timing + '</section>'
    missing = ""
    if warnings:
        missing = '<section class="notice"><h2>미포함 파일</h2><ul>' + ''.join('<li>' + esc(w) + '</li>' for w in warnings) + '</ul></section>'
    page = '''<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>iPhone 6 · 6s 신호 복원 검토</title>
<style>
:root{color-scheme:light;--ink:#16283d;--muted:#52677d;--border:#cdd9e3;--blue:#145894}
*{box-sizing:border-box}body{margin:0;background:#eef3f7;color:var(--ink);font:16px/1.75 "Malgun Gothic","Noto Sans KR",Arial,sans-serif}
header{background:#102b46;color:white;padding:35px max(22px,calc((100% - 1300px)/2));border-bottom:5px solid #4bc0ba}
h1{font-size:clamp(1.6rem,3vw,2.3rem);line-height:1.35;margin:8px 0 14px}header p{max-width:1000px;margin:8px 0;color:#dce9f3}
.eyebrow{font-size:.88rem;letter-spacing:.05em;color:#86ddd3}main{max-width:1340px;margin:auto;padding:24px 20px 65px}
h2{font-size:1.3rem;margin:0 0 18px}a{color:var(--blue)}.card,.notice,nav{background:#fff;border:1px solid var(--border);border-radius:12px;padding:24px;margin-bottom:24px;scroll-margin-top:20px}
.notice{border-left:5px solid #2d7c98;background:#fafdff}.notice ul{padding-left:25px}
nav ul{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:8px 20px;list-style:none;padding:0;margin:0}
dl{display:grid;grid-template-columns:180px 1fr;gap:7px 14px;font-size:.94rem;margin:0 0 20px}dt{color:var(--muted)}dd{margin:0;overflow-wrap:anywhere}
figure{margin:18px 0 8px}figure img{display:block;max-width:100%;height:auto;max-height:1400px;margin:auto;background:#f5f7f9;object-fit:contain;border:1px solid #e2e8ef}
figcaption{color:var(--muted);font-size:.9rem;text-align:center;padding:9px}figure a{display:block}details{border-top:1px solid var(--border);margin-top:22px;padding-top:15px}
.progression{margin-top:28px;border-top:2px solid var(--border);padding-top:18px}.progression h3{margin:0 0 10px}.muted{font-size:.9rem;color:var(--muted)}.table-scroll{overflow:auto}table{border-collapse:collapse;font-size:.85rem;width:100%}th,td{padding:9px 10px;border-bottom:1px solid var(--border);text-align:right;white-space:nowrap}th{background:#edf4f9}td:first-child,th:first-child{text-align:left}.checkpoint{padding:12px;border:1px solid var(--border);border-radius:7px;margin-top:10px}
summary{cursor:pointer;color:var(--blue);font-weight:700}.individual{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px;align-items:start}.individual img{max-height:1000px}
.finding{padding:12px 15px;background:#edf8f5;border-left:4px solid #38977f}.unresolved{background:#fff5e4;border-color:#c38a2b}
.missing{padding:16px;background:#fff1d6;border:1px solid #e4c280;border-radius:6px;margin:12px 0;overflow-wrap:anywhere}.item-note{padding:12px;background:#f3f6f9}code{font-family:Consolas,monospace;font-size:.9em}footer{color:var(--muted);font-size:.9rem;margin:25px 0}
@media(max-width:700px){main{padding:15px 10px}.card,.notice,nav{padding:17px}dl{grid-template-columns:1fr;gap:2px}dd{margin-bottom:9px}.individual{grid-template-columns:1fr}}
@media print{body{background:white}header{color:#111;background:white;padding:15px}header p{color:#333}nav,details{display:none}.card{break-inside:avoid;border:0;padding:10px;margin:0}figure img{max-height:750px}a{color:inherit;text-decoration:none}}
</style></head><body>
<header><div class="eyebrow">2026-10-23 · MATLAB 수신 IQ 분석 기록</div><h1>iPhone 6 · iPhone 6s 화면 복원 검토</h1>
<p>캡처별 AM 대조군, 처리 결과와 상대 위상을 함께 비교합니다. 각 그림을 누르면 원본 크기로 열립니다.</p></header><main>
<section class="notice"><h2>표시와 수치의 의미</h2><ul>
<li><strong>iPhone 6와 iPhone 6s는 별도 기기입니다.</strong> 캡처 이름·주파수·샘플률을 각 결과에 함께 표시했습니다.</li>
<li>AM 대조군도 수신 IQ에서 계산한 복원 영상입니다. 실제 휴대폰 화면을 촬영한 원본 사진과 구별합니다. 열 성분 제거는 후처리이며, 세로선과 겹치는 화면 정보도 제거할 수 있습니다.</li>
<li>HSV의 색은 상대 측정 위상입니다. 화면의 원래 RGB 색상을 복원했다는 뜻이 아니며 낮은 진폭에서 위상은 불안정할 수 있습니다.</li>
<li>홀짝 AM 상관은 누적 결과의 반복성을 나타냅니다. 정확한 화면 복원율이나 물리 SNR이 아니며 고정 간섭도 기여할 수 있습니다.</li>
<li>Fs·RF 중심·BW는 제공된 기록의 값입니다. Headerless RIS가 직접 제공하는 metadata가 아니며, Fs와 수신 대역폭은 다릅니다. Crop 좌표는 summary 기록값이며 인덱스 기준은 해당 생성 코드에 따릅니다.</li>
</ul></section><nav aria-label="결과 목차"><h2>캡처별 결과</h2><ul>'''
    page += ''.join(nav) + '</ul></nav>' + ''.join(cards) + supplement + missing
    page += '<footer>출처: <a href="presentation_summary.json">presentation_summary.json</a>. 이 HTML 생성기는 저장된 수치와 PNG를 표시하며 신호 처리·보간·영상 보강을 수행하지 않습니다. <a href="REPORT_KO.md">한국어 분석 보고서</a> · <a href="raw_provenance.json">입력 근거</a> · <a href="password_105_P064_refined/refinement.json">105MHz 시간 보정 검증</a></footer></main></body></html>\n'
    return page, warnings


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--result-dir", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--embed-images", action="store_true")
    args = parser.parse_args()
    root = args.result_dir.resolve()
    items = load_items(root / "presentation_summary.json")
    page, warnings = build_gallery(root, items, args.embed_images)
    output = root / "index.html"
    output.write_text(page, encoding="utf-8")
    print(json.dumps({"output": str(output), "records": len(items), "warnings": warnings,
                      "signal_processing_performed": False}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
