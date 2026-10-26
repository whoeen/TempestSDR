"""Render measured iPhone 6 FAM results; does not execute MATLAB or touch IQ."""
from __future__ import annotations
import argparse
import html
import json
import math
from pathlib import Path
from datetime import datetime, timezone

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def array(value):
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def number(value, digits=6):
    try:
        return f"{float(value):.{digits}f}" if math.isfinite(float(value)) else "unavailable"
    except (TypeError, ValueError):
        return "unavailable"


def latest_validation(root):
    candidates = []
    for p in root.glob("validation*/validation.json"):
        data = read(p)
        if data.get("status") == "complete" and data.get("all_discovery_replays_passed"):
            candidates.append((p.stat().st_mtime_ns, p, data))
    if not candidates:
        raise RuntimeError("No completed validation with passed discovery replay is available.")
    _, path, data = max(candidates, key=lambda x: x[0])
    return path, data


def md_table(headers, rows):
    cells = lambda row: "| " + " | ".join(str(x).replace("|", "\\|") for x in row) + " |"
    return "\n".join([cells(headers), cells(["---"] * len(headers))] + [cells(row) for row in rows])


def html_table(headers, rows):
    tr = lambda row, tag: "<tr>" + "".join(f"<{tag}>{html.escape(str(x))}</{tag}>" for x in row) + "</tr>"
    return '<div class="table-scroll"><table><thead>' + tr(headers, "th") + "</thead><tbody>" + "".join(tr(row, "td") for row in rows) + "</tbody></table></div>"


def nearest(peaks, alpha):
    return min(array(peaks), key=lambda x: abs(x["alpha_hz"] - alpha))


def frozen_rows(band):
    rows = []
    candidates = array(band["frozen_candidates"])
    blocks = array(band["blocks"])
    controls = array(band["gaussian_controls"])
    for i, candidate in enumerate(candidates):
        values = {kind: [array(block[kind])[i]["coherence_magnitude"] for block in blocks]
                  for kind in ["original", "line_residual"]}
        values["fsm"] = [array(block["independent_frequency_smoothing"]["estimates"])[i]["coherence_magnitude"] for block in blocks]
        values["gaussian"] = [array(control["estimates"])[i]["coherence_magnitude"] for control in controls]
        rows.append({"index": i + 1, "alpha_hz": candidate["alpha_hz"],
                     "nominal_rf_hz": band["nominal_center_hz"] + candidate["f_hz"],
                     "k_bin": candidate["k_bin"], "l_bin": candidate["l_bin"], "q_bin": candidate["q_bin"],
                     **values,
                     "power_floor_pass": [array(block["original"])[i]["frozen_power_floor_pass"] for block in blocks],
                     "phase_local_rad": [array(block["original"])[i]["phase_local_radians"] for block in blocks],
                     "phase_epoch_rad": [array(block["original"])[i]["phase_original_epoch_radians"] for block in blocks]})
    return rows


def row_cells(row):
    triple = lambda key: " / ".join(number(v, 6) for v in row[key])
    return [row["index"], number(row["alpha_hz"], 6), number(row["nominal_rf_hz"] / 1e6, 6),
            f'{row["k_bin"]},{row["l_bin"]},{row["q_bin"]}', triple("original"), triple("line_residual"),
            triple("fsm"), number(max(row["gaussian"]), 6), "/".join("yes" if v else "no" for v in row["power_floor_pass"])]


def render_plots(root, refined, bands, centers):
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10,
                         "axes.spines.top": False, "axes.spines.right": False,
                         "axes.grid": True, "grid.alpha": 0.18, "figure.facecolor": "white"})
    fig, axes = plt.subplots(2, 2, figsize=(14, 9), constrained_layout=True)
    family = array(centers[78]["integer_harmonic_families"])[0]
    fundamental = family["fundamental_hz"]
    palette = {78: "#146aab", 106: "#d65c32"}
    for center in [78, 106]:
        peaks = array(refined[(center, 1)]["nc"]["separated_profile_peaks"])
        points = sorted(peaks[:64], key=lambda p: p["alpha_hz"])
        axes[0, 0].scatter([p["alpha_hz"] / 1e3 for p in points], [p["max_pair_coherence"] for p in points],
                           s=19, alpha=.8, label=f"RF {center} MHz, discovery maxima", color=palette[center])
    for h in [1, 2, 3, 4]:
        axes[0, 0].axvline(h * fundamental / 1e3, ls="--", lw=.7, color="gray")
    axes[0, 0].set(xlabel="Cycle frequency alpha (kHz)", ylabel="Maximized NC pair correlation", xlim=(0, 500), ylim=(0, 1), title="A. Raw-IQ cyclic structure (exploratory maxima)")
    axes[0, 0].legend(fontsize=8)
    peaks = array(refined[(78, 1)]["nc"]["separated_profile_peaks"])
    half = fundamental / 2
    selected = sorted([p for p in peaks if abs(p["alpha_hz"] - half) < 150], key=lambda p: p["alpha_hz"])
    for p in selected:
        x, y = p["alpha_hz"] - half, p["max_pair_coherence"]
        axes[0, 1].vlines(x, 0, y, color="#146aab", alpha=.7)
        axes[0, 1].plot(x, y, "o", color="#146aab", ms=5)
        if abs(abs(x) - 29.5836448669) < 1:
            axes[0, 1].annotate(f"{p['alpha_hz']:.3f} Hz", (x, y), xytext=(x + (-20 if x < 0 else 8), y + .04), ha="right" if x < 0 else "left", fontsize=8)
    axes[0, 1].axvline(0, ls="--", color="gray")
    axes[0, 1].set(xlabel=f"Offset from F/2 = {half:.3f} Hz", ylabel="Maximized NC pair correlation", ylim=(0, .55), title="B. Half-order split: F/2 itself is not established")
    strongest = bands[78]["rows"][0]
    blocks = array(bands[78]["source"]["blocks"])
    times = [b["epoch_seconds"] for b in blocks]
    for kind, label, marker in [("original", "Frozen FAM pair: original", "o"), ("line_residual", "Same pair: line residual", "s"), ("fsm", "Independent frequency smoothing", "^")]:
        axes[1, 0].plot(times, strongest[kind], marker=marker, label=label)
    noise = max(strongest["gaussian"])
    axes[1, 0].axhline(noise, ls=":", color="gray", label=f"Two Gaussian controls: max {noise:.4f}")
    axes[1, 0].axvspan(min(times) - .08, min(times) + .08, color="gray", alpha=.08)
    axes[1, 0].set(xlabel="Block first-sample time in original recording (s)", ylabel="Normalized cyclic correlation", ylim=(0, 1), title=f"C. Fixed (k,l,q), alpha = {strongest['alpha_hz']:.3f} Hz")
    axes[1, 0].legend(fontsize=8)
    for center in [78, 106]:
        for mode, style in [("nc", "-o"), ("conjugate", "--s")]:
            magnitudes = [refined[(center, b)][mode]["stats"]["maximum_pair_coherence"] for b in [1, 2, 3]]
            axes[1, 1].plot(times, magnitudes, style, color=palette[center], label=f"{center} MHz {'NC' if mode == 'nc' else 'C'}")
    axes[1, 1].set(xlabel="Block first-sample time (s)", ylabel="Search maximum, reselected each block", ylim=(0, 1), title="D. NC and conjugate searches (not frozen validation)")
    axes[1, 1].legend(fontsize=8)
    fig.suptitle("iPhone 6 / fc = 100 MHz recording: FAM evidence and fixed-pair checks", fontsize=16)
    fig.savefig(root / "summary.png", dpi=170)
    plt.close(fig)
    fig, axes = plt.subplots(1, 2, figsize=(13, 4.8), constrained_layout=True)
    for center in [78, 106]:
        rows = bands[center]["rows"]
        row = min(rows, key=lambda r: abs(r["alpha_hz"] - 2 * fundamental))
        axes[0].plot(times, np.rad2deg(row["phase_local_rad"]), "o-", label=f"RF {center} MHz")
        axes[1].plot(times, np.rad2deg(row["phase_epoch_rad"]), "o-", label=f"RF {center} MHz")
    for ax in axes:
        ax.set(xlabel="Block first-sample time (s)", ylabel="NC cyclic coefficient phase (degrees)", ylim=(-185, 185))
        ax.legend()
    axes[0].set_title("Local first retained sample as phase origin")
    axes[1].set_title("Original recording epoch as phase origin")
    fig.suptitle("Frozen alpha near 2F: cyclic phase is not instantaneous IQ carrier phase", fontsize=13)
    fig.savefig(root / "cyclic_phases.png", dpi=160)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", type=Path, default=Path(__file__).resolve().parents[1] / "results" / "iphone6_fc100_fam_20261026")
    args = parser.parse_args()
    root = args.results.resolve()
    preflight = read(root / "preflight.json")
    coarse = read(root / "coarse/summary.json")
    refined = {(center, block): read(root / f"refined/rf{center}_block{block}/summary.json") for center in [78, 106] for block in [1, 2, 3]}
    validation_path, validation = latest_validation(root)
    periodicity = read(root / "periodicity/summary.json")
    if periodicity.get("status") != "completed":
        raise RuntimeError("Periodicity analysis is not completed.")
    centers = {round(c["rf_center_hz"] / 1e6): c for c in array(periodicity["centers"])}
    bands = {round(b["nominal_center_hz"] / 1e6): {"source": b, "rows": frozen_rows(b)} for b in array(validation["bands"])}
    family = array(centers[78]["integer_harmonic_families"])[0]
    f = family["fundamental_hz"]
    refinement = centers[78]["refinement"]
    fold_f = refinement["used_frequency_hz"]
    delta = refined[(78, 1)]["metadata"]["alpha_bin_spacing_hz"]
    main_row = min(bands[78]["rows"], key=lambda r: abs(r["alpha_hz"] - 2 * f))
    family_rows = []
    for harmonic in [1, 2, 3, 4]:
        peak = nearest(refined[(78, 1)]["nc"]["separated_profile_peaks"], harmonic * f)
        family_rows.append([harmonic, number(peak["alpha_hz"], 6), number(1e6 / peak["alpha_hz"], 6), number(peak["max_pair_coherence"], 6), number((78e6 + peak["argmax_f_hz"]) / 1e6, 6)])
    validation_headers = ["#", "alpha (Hz)", "RF midpoint (MHz)", "k,l,q", "원본 B1/B2/B3", "line 잔차 B1/B2/B3", "FSM B1/B2/B3", "Gaussian 최대", "power gate B1/B2/B3"]
    block_rows = []
    for center in [78, 106]:
        for block in array(bands[center]["source"]["blocks"]):
            block_rows.append([center, block["block"], number(block["epoch_seconds"], 1), number(100 * block["line_projection_metrics"]["power_fraction"], 4), number(bands[center]["source"]["discovery_replay_max_absolute_error"], 12)])
    fold_rows = []
    for center in [78, 106]:
        for block in array(centers[center]["blocks"]):
            for metric in array(block["fold_metrics"]):
                fold_rows.append([center, block["block"], metric["period_multiplier"], number(metric["fold_period_seconds"] * 1e6, 6), number(metric["unaligned_power_correlation_to_training"], 6), number(metric["relative_fold_modulation_rms"], 6), number(metric["display_only_shift_bins"], 0)])
    phase_rows = []
    for center in [78, 106]:
        row = min(bands[center]["rows"], key=lambda r: abs(r["alpha_hz"] - 2 * f))
        for b, local, epoch in zip([1, 2, 3], row["phase_local_rad"], row["phase_epoch_rad"]):
            phase_rows.append([center, b, number(row["alpha_hz"], 6), number(local, 6), number(epoch, 6)])
    facts = {
        "status": "complete", "created_utc": datetime.now(timezone.utc).isoformat(),
        "input": preflight["read"]["filename"], "native_fs_hz": preflight["sampling_rate_hz"],
        "nominal_capture_bandwidth_hz": 120e6, "capture_bandwidth_source": "user measurement setup",
        "analysis_fs_hz": refined[(78, 1)]["metadata"]["fs_hz"], "decimation": 16,
        "M": 32, "L": 8, "P": 131072, "alpha_spacing_hz": delta,
        "alpha_fft_time_seconds": refined[(78, 1)]["metadata"]["alpha_fft_time_seconds"],
        "block_start_seconds": [0.2, 1.1, 1.8], "time_axis_warp_applied": False,
        "integer_family_frequency_hz": f, "integer_family_period_us": 1e6 / f,
        "training_cyclic_power_refinement": refinement,
        "half_order_split_hz": [-4 * delta, 4 * delta], "observed_slow_grid_peak_hz": 8 * delta,
        "packet_identified": False, "validation_file": validation_path.relative_to(root).as_posix(),
        "validation_all_discovery_replays_passed": validation["all_discovery_replays_passed"],
        "bands": {str(k): {"frozen_candidates": v["rows"], "line_projection_power_fraction": [b["line_projection_metrics"]["power_fraction"] for b in array(v["source"]["blocks"])]} for k, v in bands.items()},
        "scope": "Measured cyclic radiation structure; no decoded SoT, packet header, ECC, lane count or bit rate."
    }
    render_plots(root, refined, bands, centers)
    lead = f"100 MHz 중심주파수 녹음본의 연속 IQ에서 FAM으로 약 {f / 1e3:.6f} kHz의 정수 고조파군을 찾았다. 대응 방사 주기는 {1e6 / f:.6f} µs이다. 이 주기는 HS/row 후보로 사용할 수 있지만 packet 자체를 식별한 결과는 아니다."
    check_text = f"RF 78 MHz 주변에서 alpha={main_row['alpha_hz']:.6f} Hz의 (k,l,q)를 block 1에서 선택한 뒤 고정했다. 원본 정규화 순환상관은 B1/B2/B3에서 {' / '.join(number(v, 6) for v in main_row['original'])}이다. 뒤의 block에서 최대값을 다시 찾은 수치와 구분된다."
    split_text = f"F/2={f / 2:.6f} Hz 근방의 주요 피크는 {f / 2 - 4 * delta:.6f}, {f / 2 + 4 * delta:.6f} Hz로 분리되어 있다. 즉 F/2 ±{4 * delta:.6f} Hz이고 간격은 {8 * delta:.6f} Hz다. 56.4 kHz를 단독 기본 packet 주파수라고 확정할 수 없다. 약 60 Hz 변조 가능성은 있지만 FFT 간격 {delta:.6f} Hz에서 관측한 {8 * delta:.6f} Hz를 정확한 frame rate로 해석하면 안 된다."
    processing = "원본 Fs=124.0828 MS/s, 기록의 nominal fc=100 MHz, 사용자가 보고한 수신 BW=120 MHz. 저장 형식은 big-endian int16 I,Q이며 I−jQ RF 부호 가설을 사용했다. discovery block 평균 DC를 모든 block에 동일하게 빼고, 절대 원본 sample index를 기준으로 DDC했다. 원본 신호에는 CFO 보정·fractional timing warp·frame 정렬을 적용하지 않았다. MATLAB resample(x,1,16,32,8)로 anti-alias 필터링 후 16분주하여 Fs=7.755175 MS/s로 분석했다. 이 단계는 분석 대역을 줄이는 일정 비율 변환이며, 샘플 클록 오차 추정에 의한 fractional timing 보정이 아니다."
    fam_text = "native coarse FAM으로 탐색한 뒤 RF 78 MHz 주변을 정밀 분석하고 RF 106 MHz 구간을 비교했다. 각 정밀 분석은 M=32, L=8, P=131072, symmetric Hamming channel window, rectangular slow-time window, zero padding 없음이다. slow-time 관측 길이는 135.209844 ms이고 alpha FFT 간격은 7.395911 Hz다. retained 실제 IQ는 1,048,600 samples, 135.212938 ms이다. block 시작점은 0.2 / 1.1 / 1.8 s이며 filter guard는 소비 구간 밖에서 확보했다. NC와 C는 동일한 결합 규칙이 아니므로 분리해 계산했다."
    distinction = "NC는 D(k)·conj(D(l)), conjugate C는 D(k)·D(l)이다. 표시한 coherence는 유한 window로 평균한 channel-pair cyclic correlation의 정규화 크기이며 점별 population SCF coherence나 SNR이 아니다. discovery 그림은 주파수 쌍을 최대화한 탐색 통계다. 아래 검증표는 block 1에서 고정한 alpha,k,l,q를 block 2·3에서 다시 최적화하지 않고 직접 DTFT로 평가한 결과다."
    controls = "독립 구현의 frequency-smoothed cyclic periodogram(FSM)은 고정된 physical f,alpha에서 별도 smoothing kernel을 사용한다. FAM과 크기가 같아야 하는 검증은 아니다. line projection은 block 1 DFT의 상위 8개 peak group(±2 bins)을 고정하고 각 block에서 계수만 투영한 진단이다. 유용한 화면의 결정론적 성분도 제거될 수 있으므로 이를 곧바로 clutter 제거 성능으로 부르지 않는다. 두 proper colored Gaussian 대조군은 배경색과 전력을 근사한 sanity reference이며 다중 탐색의 유의수준이나 오경보 확률을 보정한 검정이 아니다."
    line78 = [100 * b["line_projection_metrics"]["power_fraction"] for b in array(bands[78]["source"]["blocks"])]
    line106 = [100 * b["line_projection_metrics"]["power_fraction"] for b in array(bands[106]["source"]["blocks"])]
    slow106 = min(bands[106]["rows"], key=lambda r: r["alpha_hz"])
    diagnostic_text = f"이번 선 성분 투영으로 제거한 power 비율은 78 MHz에서 {min(line78):.4f}–{max(line78):.4f}%, 106 MHz에서 {min(line106):.4f}–{max(line106):.4f}%다. 78 MHz의 2F 고정 후보는 line 잔차에서 {' / '.join(number(v, 6) for v in main_row['line_residual'])}로 유지됐다. 반면 106 MHz의 저주파 후보 {slow106['alpha_hz']:.6f} Hz는 원본 {' / '.join(number(v, 6) for v in slow106['original'])}에서 잔차 {' / '.join(number(v, 6) for v in slow106['line_residual'])}로 변했다. 이는 선택한 40개 DFT bin에 대한 조건부 진단이며 모든 tone 또는 driver clutter를 제거했다는 뜻은 아니다."
    phase_text = "아래 위상은 고정된 순환계수의 각도다. 순간 IQ carrier phase나 복원 RGB hue가 아니다. local 위상은 각 retained block 첫 sample을 0초로 두며, epoch 위상은 exp(−j2παt_start)를 곱해 원본 녹음 시작을 기준으로 표시했다. alpha의 FFT 양자화 오차만으로도 떨어진 block 사이 위상이 회전할 수 있으므로 위상 변화만으로 CFO 또는 clock drift를 단정하지 않는다."
    fold_text = f"folding 주파수는 block 1에서만 선택했다. 78 MHz 구간은 FAM family seed {f:.6f} Hz 주변 ±0.5 alpha bin에서 mean-subtracted |IQ|²의 Hann-weighted DTFT 크기를 최적화하여 {fold_f:.6f} Hz를 사용했다. 이는 cyclic-power가 같은 기본 주기를 공유한다는 가정 아래의 sub-bin 추정이며 통계적 신뢰구간이 아니다. 이후 block은 이 값을 고정하고 원본 absolute sample-time phase로 접었다. F/2의 두 배 길이 folding은 비교 가설이다. display-only circular alignment 그림은 시각 비교용이며 검증에는 사용하지 않았다."
    corr78 = [array(b["fold_metrics"])[0]["unaligned_power_correlation_to_training"] for b in array(centers[78]["blocks"])[1:]]
    corr106 = [array(b["fold_metrics"])[0]["unaligned_power_correlation_to_training"] for b in array(centers[106]["blocks"])[1:]]
    fold_evidence = f"78 MHz의 {1e6 / fold_f:.6f} µs power fold는 시간축 재정렬 없이 block 2·3에서 training 파형과 {corr78[0]:.9f}, {corr78[1]:.9f}의 상관을 보였다. 두 구간 모두 display-only 최적 shift도 0 bin이었다. 따라서 이 대역은 현재 고정 주기 기반 반복 구간 추출에 유망하다. 106 MHz를 별도로 최적화한 주파수에서는 unaligned 상관이 {corr106[0]:.6f}, {corr106[1]:.6f}이므로 같은 phase 안정성을 주장하지 않는다. 이후 shift를 맞춰 그림이 유사해지는 것과 원본 시간축에서 일치하는 것은 다른 결과다."
    facts["frozen_power_fold_confirmation"] = {"rf78_block2_block3_unaligned_correlation": corr78, "rf106_block2_block3_unaligned_correlation": corr106, "rf78_frozen_period_us": 1e6 / fold_f, "posthoc_shift_used": False}
    conclusion = "현재 얻은 것은 실제 녹음에서 재현되는 방사 주기와 고조파·분할 sideband 구조다. 다음 단계에서는 이 주기로 원본 IQ의 반복 구간을 추출해 burst 시작/끝, 반복 header 후보, 패턴 전환 시 변화를 확인해야 한다. 알려진 SoT/packet header/ECC와 맞는 증거가 생기기 전에는 MIPI HS packet clock, lane 수, byte rate, DDR clock 또는 pixel clock으로 이름 붙이지 않는다."
    limitations = ["packet/SoT/header/ECC를 decode하지 않았다. 패널 driver 방사와 DSI packet 방사를 아직 구별하지 않았다.", "분리된 세 block은 같은 파일 안의 확인 구간이다. 전체 녹음을 전혀 본 적 없는 독립 수집 데이터라는 뜻은 아니다.", "반복 tone 사이 차주파수도 NC cyclic peak를 만들 수 있다. 강한 peak만으로 AM/PM payload 변조를 증명하지 못한다.", "conjugate peak는 RF 106 MHz 구간에서 강하지만 tone, 비원형성 또는 IQ 불균형도 설명 후보다. NC 후보의 검증을 C에 그대로 적용했다고 주장하지 않는다.", "AA decimation은 정보나 해상도를 생성하지 않는다. 이번 출력은 영상 복원·stitching 성공 판정이 아니다."]
    markdown = ["# iPhone 6 · 100 MHz 녹음본 FAM 주기성 분석", "", lead, "", check_text, "", "![FAM 요약](summary.png)", "", "## 1. 실제 사용한 데이터와 처리", "", processing, "", fam_text, "", distinction, "", "## 2. 정수 고조파군과 반차수 분할", "", md_table(["order", "alpha (Hz)", "1/alpha (µs)", "탐색 최대 NC", "RF midpoint (MHz)"], family_rows), "", split_text, "", "![원본 PSD](native_psd.png)", "", "![native coarse FAM](coarse/fam_maps.png)", "", "![78 MHz 정밀 FAM](refined/rf78_block1/fam_maps.png)", "", "## 3. 고정된 후보의 확인", "", check_text, "", controls, "", diagnostic_text]
    for center in [78, 106]:
        markdown += ["", f"### RF {center} MHz", "", md_table(validation_headers, [row_cells(r) for r in bands[center]["rows"]])]
    markdown += ["", "### 선 성분 투영 진단", "", md_table(["RF MHz", "block", "start s", "투영 power %", "discovery replay 최대 절대 오차"], block_rows), "", "## 4. 주기적 파형과 위상", "", fold_text, "", fold_evidence, "", "![주기 folding](periodicity/rf78/periodicity_folds.png)", "", md_table(["RF MHz", "block", "period multiplier", "period µs", "unaligned fold correlation", "fold modulation RMS / mean", "display-only shift bins"], fold_rows), "", phase_text, "", "![순환계수 위상](cyclic_phases.png)", "", md_table(["RF MHz", "block", "alpha Hz", "local phase rad", "epoch phase rad"], phase_rows), "", "## 5. 해석 범위와 다음 단계", "", conclusion, ""]
    markdown += [f"- {text}" for text in limitations]
    markdown += ["", "## 재현 파일", "", f"- 검증 수치: [{validation_path.parent.name}/validation.json]({validation_path.relative_to(root).as_posix()})", "- 주기 모델: [periodicity/summary.json](periodicity/summary.json)", "- 수치 요약: [RESULTS_SUMMARY.json](RESULTS_SUMMARY.json)", "- 실제 계산: MATLAB R2026b, Signal Processing Toolbox resample/pwelch + 공개된 FAM MATLAB 구현. Wavelet 변환은 이번 FAM 추정에 사용하지 않았다.", "- 방법 출처: [CSP Estimators: The FFT Accumulation Method](https://cyclostationary.blog/2018/06/01/csp-estimators-the-fft-accumulation-method/) (알고리즘 참고; 위 숫자는 이 녹음본의 실행 결과).", ""]
    (root / "REPORT_KO.md").write_text("\n".join(markdown), encoding="utf-8")
    (root / "RESULTS_SUMMARY.json").write_text(json.dumps(facts, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    gallery = root / "gallery"
    gallery.mkdir(exist_ok=True)
    p = lambda text: "<p>" + html.escape(text) + "</p>"
    image = lambda path, caption: f'<figure><a href="../{path}" target="_blank"><img loading="lazy" src="../{path}" alt="{html.escape(caption)}"></a><figcaption>{html.escape(caption)}</figcaption></figure>'
    body = '<header><div class="eyebrow">MEASURED IQ · MATLAB R2026b · 2026-10-26</div><h1>100 MHz 녹음본에서 찾은<br>112.8 kHz 방사 주기</h1>' + p(lead) + '<div class="metrics"><div><b>' + number(1e6 / f, 6) + '</b><span>µs · FAM family period</span></div><div><b>' + number(f / 1e3, 6) + '</b><span>kHz · integer family</span></div><div><b>' + number(delta, 6) + '</b><span>Hz · alpha FFT spacing</span></div></div></header>'
    body += '<nav><a href="#summary">요약</a><a href="#method">처리 조건</a><a href="#family">주기 구조</a><a href="#validation">고정 후보 확인</a><a href="#phase">파형·위상</a><a href="#scope">해석 범위</a></nav>'
    body += '<section id="summary"><h2>실제 계산 결과</h2>' + p(check_text) + image("summary.png", "A/B/D는 탐색 통계, C는 discovery에서 고정한 쌍의 확인 결과") + '</section>'
    body += '<section id="method"><h2>원본 IQ에서 FAM까지</h2>' + p(processing) + p(fam_text) + p(distinction) + image("native_psd.png", "원본 Welch PSD. 최대 spectral peak가 가장 유용한 cyclic feature와 일치할 필요는 없다.") + '</section>'
    body += '<section id="family"><h2>정수 고조파군과 F/2 주변의 분리 피크</h2>' + html_table(["order", "alpha (Hz)", "period (µs)", "탐색 최대 NC", "RF midpoint (MHz)"], family_rows) + p(split_text) + image("coarse/fam_maps.png", "Native-rate coarse NC/C FAM")
    body += '<div class="tabs"><button onclick="showBand(78)" class="band78 selected">78 MHz</button><button onclick="showBand(106)" class="band106">106 MHz</button></div>'
    for center in [78, 106]:
        body += f'<div data-band="{center}"' + (' hidden' if center == 106 else '') + '>' + image(f"refined/rf{center}_block1/fam_maps.png", f"RF {center} MHz: block 1 정밀 NC/C FAM (탐색 최대값)") + '</div>'
    body += '</section><section id="validation"><h2>고정된 (alpha,k,l,q)의 확인</h2>' + p(check_text) + p(controls) + p(diagnostic_text)
    for center in [78, 106]:
        body += f'<details {"open" if center == 78 else ""}><summary>RF {center} MHz · 전체 고정 후보 수치</summary>' + html_table(validation_headers, [row_cells(r) for r in bands[center]["rows"]]) + '</details>'
    body += '<h3>선 성분 투영과 replay</h3>' + html_table(["RF MHz", "block", "start s", "투영 power %", "replay 최대 절대 오차"], block_rows) + '</section>'
    body += '<section id="phase"><h2>주기 파형과 순환계수 위상</h2>' + p(fold_text) + p(fold_evidence)
    for center in [78, 106]:
        body += f'<details {"open" if center == 78 else ""}><summary>RF {center} MHz · 원본 sample-time 기준 folding</summary>' + image(f"periodicity/rf{center}/periodicity_folds.png", "학습 주파수를 고정한 power folding; phase shift로 맞추지 않은 결과") + image(f"periodicity/rf{center}/temporal_pulse_structure.png", "각 block 내부 시간별 fold와 원본 power 파형") + '</details>'
    body += html_table(["RF MHz", "block", "period multiplier", "period µs", "unaligned correlation", "modulation RMS/mean", "display-only shift bins"], fold_rows) + p(phase_text) + image("cyclic_phases.png", "순간 IQ carrier phase가 아니라 고정 NC 순환계수 위상") + html_table(["RF MHz", "block", "alpha Hz", "local rad", "original epoch rad"], phase_rows) + '</section>'
    body += '<section id="scope"><h2>현재 결론과 다음 확인</h2>' + p(conclusion) + '<ul>' + ''.join('<li>' + html.escape(t) + '</li>' for t in limitations) + '</ul><div class="downloads"><a href="../REPORT_KO.md">한국어 보고서</a><a href="../RESULTS_SUMMARY.json">수치 JSON</a><a href="../' + validation_path.relative_to(root).as_posix() + '">전체 검증 JSON</a><a href="../periodicity/summary.json">주기 모델 JSON</a></div></section>'
    css = 'body{margin:0;background:#f3f6fa;color:#16283b;font-family:"Malgun Gothic",system-ui,sans-serif;line-height:1.75}main{max-width:1250px;margin:auto;padding:30px}header{padding:36px 42px;background:#fff;border-top:6px solid #176ea8;border-radius:12px}.eyebrow{color:#46718d;font-size:12px;letter-spacing:1.5px}h1{font-size:40px;line-height:1.3;margin:14px 0}h2{font-size:25px}p{max-width:1100px}nav{display:flex;gap:18px;flex-wrap:wrap;padding:18px 4px;position:sticky;top:0;background:#f3f6faf2;z-index:2}a{color:#135f96}section{padding:25px 30px;margin:16px 0;background:white;border:1px solid #dce4ec;border-radius:10px;scroll-margin-top:70px}.metrics{display:flex;gap:40px;flex-wrap:wrap;padding-top:18px}.metrics div{display:flex;flex-direction:column}.metrics b{font-size:27px;color:#126b9d}.metrics span{font-size:12px;color:#617186}figure{margin:22px 0}img{width:100%;height:auto;border:1px solid #e1e6ea}figcaption{font-size:12px;color:#526575}table{border-collapse:collapse;width:100%;font-size:12px;white-space:nowrap}th,td{text-align:left;border-bottom:1px solid #e2e8ed;padding:9px 11px}th{background:#edf3f8;position:sticky;top:0}.table-scroll{overflow:auto;max-height:620px;margin:16px 0}details{border:1px solid #dce4ec;border-radius:7px;margin:14px 0;padding:10px}summary{cursor:pointer;font-weight:600}.tabs{display:flex;gap:8px}button{border:1px solid #b9cad7;padding:10px 20px;border-radius:6px;background:white;cursor:pointer}.selected{background:#146aab;color:white}.downloads{display:flex;gap:20px;flex-wrap:wrap;margin-top:20px}li{margin:8px 0}@media(max-width:700px){main{padding:10px}header,section{padding:20px}h1{font-size:29px}.metrics{gap:20px}}'
    js = 'function showBand(n){document.querySelectorAll("[data-band]").forEach(e=>e.hidden=Number(e.dataset.band)!==n);[78,106].forEach(i=>document.querySelectorAll(".band"+i).forEach(e=>e.classList.toggle("selected",i===n)));}'
    (gallery / "index.html").write_text('<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>iPhone 6 100 MHz FAM</title><style>' + css + '</style><main>' + body + '</main><script>' + js + '</script></html>', encoding="utf-8")
    print(json.dumps({"status": "complete", "validation": str(validation_path), "report": str(root / "REPORT_KO.md"), "gallery": str(gallery / "index.html"), "summary_figure": str(root / "summary.png")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
