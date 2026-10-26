"""Author a source-based Korean review and gallery; never runs historical MATLAB."""
from __future__ import annotations
import argparse
import csv
import hashlib
import html
import json
from pathlib import Path


def read_json(p):
    return json.loads(p.read_text(encoding="utf-8-sig"))


def rows_csv(p):
    with p.open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def mdtable(head, rows):
    row = lambda values: "| " + " | ".join(str(v).replace("|", "\\|") for v in values) + " |"
    return "\n".join([row(head), row(["---"] * len(head))] + [row(r) for r in rows])


def table(head, rows):
    row = lambda values, tag: "<tr>" + "".join(f"<{tag}>{html.escape(str(v))}</{tag}>" for v in values) + "</tr>"
    return '<div class="scroll"><table><thead>' + row(head,"th") + '</thead><tbody>' + ''.join(row(r,"td") for r in rows) + '</tbody></table></div>'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", type=Path, default=Path(__file__).resolve().parents[1] / "results" / "claude_mobile_review_20261026")
    opts = parser.parse_args()
    root = opts.results.resolve()
    snapshot = root / "source_snapshot"
    inventory = read_json(snapshot / "SOURCE_INVENTORY.json")
    audit = read_json(root / "endian_audit.json")
    assert audit["status"] == "completed" and audit["saved_csv_rms_reproduced"]
    entries = {e["relative_path"]: e for e in inventory["entries"]}
    source_count = len(rows_csv(snapshot / "ORIGINAL_FILE_LIST_METADATA_ONLY.csv"))
    for relative, entry in entries.items():
        actual = snapshot / relative
        assert actual.stat().st_size == entry["bytes"]
        assert hashlib.sha256(actual.read_bytes()).hexdigest() == entry["sha256"], relative
    figures = {
        "galaxy": "analysis_outputs/final_screens_v1/galaxy_111p9M_K120_equalised_1080x1920.png",
        "lg": "analysis_outputs/final_screens_v1/lgx2_subaligned_K85_equalised_720x1440.png",
        "iphone100": "analysis_outputs/res_generic_black_fc100M_P139/black_fc100M_P139_active.png",
        "iphone100_full": "analysis_outputs/res_generic_black_fc100M_P139/black_fc100M_P139_fullraster.png",
        "galaxy_sampling": "analysis_outputs/ppt_galaxy_111p9M/galaxy_111p9M_ppt.png",
        "harmonic": "analysis_outputs/harmonic_structure_v1/harmonic_structure_v1.png",
        "iphone238": "analysis_outputs/fusion_weights_iphone6_238M_8band/iphone6_238M_8band_fusion_weights.png"
    }
    assert all(p in entries for p in figures.values())
    theory = "docs/theory/2026-07-27_PAPER_RES_EQUATIONS_AND_CODE_COMPARISON.md"
    galaxy_note = "docs/experiments/2026-07-29_galaxy_111p9M_band_and_linerate_v1.md"
    iphone_note = "docs/experiments/2026-07-27_iphone6_238M_frame_count_200_to_488_v1.md"
    metrics_path = "analysis_outputs/iphone6s_RES_paper_fourier_full_v1/iphone6s_RES_paper_fourier_full_metrics_v1.csv"
    fourier = rows_csv(snapshot / metrics_path)
    t = audit["timing"]
    blocks = audit["blocks"]
    r = lambda field: (min(b[field] for b in blocks), max(b[field] for b in blocks))
    outside = r("outside_small_word_fraction")
    power = r("outside_small_word_be_power_fraction")
    correlation = r("be_vs_le_div256_correlation")
    nmse = r("le_div256_minus_be_normalized_mse")
    slip_cells = t["whole_capture_relative_cycle_slip"] * 750
    source_link = lambda rel: f"[스냅샷](source_snapshot/{rel}) · [원본]({entries[rel]['original_path']})"
    def html_source(rel):
        e = entries[rel]
        return '<p class="source"><a href="../source_snapshot/' + html.escape(rel, quote=True) + '">보관한 소스</a> · <a href="' + Path(e["original_path"]).as_uri() + '">원본 파일</a> · SHA-256 <code>' + e["sha256"][:16] + '…</code></p>'
    audit_rows = [[i+1, b["first_complex_sample"], f'{b["be_rms_i"]:.6f}', f'{b["le_rms_i"]:.6f}', f'{b["be_vs_le_div256_correlation"]:.6f}', f'{100*b["outside_small_word_fraction"]:.4f}', f'{100*b["outside_small_word_be_power_fraction"]:.4f}', f'{b["le_div256_minus_be_normalized_mse"]:.6f}'] for i,b in enumerate(blocks)]
    audit_head = ["block", "첫 complex sample", "BE I RMS", "LE I RMS", "corr(BE,LE/256)", "범위 밖 scalar %", "해당 scalar power %", "NMSE(LE/256−BE)"]
    timing_rows = [
        ["Fs label (MS/s)", f'{t["claude_fs_hz"]/1e6:.7f}', f'{t["fam_fs_hz"]/1e6:.7f}'],
        ["주기 추정치 (Hz)", f'{t["claude_fit_hz"]:.9f}', f'{t["fam_fit_hz"]:.9f}'],
        ["samples/cycle", f'{t["claude_samples_per_cycle"]:.9f}', f'{t["fam_samples_per_cycle"]:.9f}'],
        ["현재 Fs 축에 환산한 주파수 (Hz)", f'{t["claude_frequency_on_fam_fs_axis_hz"]:.9f}', f'{t["fam_fit_hz"]:.9f}']
    ]
    quality_rows = [
        ["LG X2", "동일 P=411, edge half correlation", "−0.000723 → 0.811617 → 0.842219", "미정렬 → 정수 shift → fractional shift; 정렬 개선의 비교"],
        ["Galaxy 111.9 MHz", "half log correlation", "0.023376 → 0.570816", "자체 fH + frame 정렬 + P=200→377을 함께 변경; timing 단독 효과로 분해 불가"],
        ["iPhone6s Fourier", "cell baseline 대비 full log correlation", f'{float(fourier[0]["FullLogCorrelation"]):.6f} → {float(fourier[1]["FullLogCorrelation"]):.6f}', "nearest-one → grouped noise-aware; ground truth 정확도가 아님"],
        ["Galaxy row 700 sampling", "N, Fourier Gram condition", "N=359,911; κ≈1.003–1.07", "377 frames의 Galaxy 표본 구조; iPhone6 100MHz 수치가 아님"]
    ]
    overview = f"원본 연구 폴더 {inventory['source_root']}를 찾아 기존 성공 화면과 해당 MATLAB 코드·기록을 함께 검토했다. 전체 {source_count:,}개 파일의 메타데이터를 목록화했고, {inventory['copied_files']}개({inventory['copied_bytes']:,} bytes)를 원래 상대 경로대로 보관했다. 각 복사본의 SHA-256이 원본 수집 기록과 일치한다. 원본 RIS·MAT 또는 원본 코드는 변경하지 않았다."
    success = "Galaxy와 LG의 기존 복원 PNG에는 실제 keypad 구조와 숫자가 보인다. 이 성공 결과는 다시 분석해야 할 근거다. 다만 화면 인지 성공과 저장 IQ를 물리적 진폭·위상으로 정확히 해석했는지는 별개의 검증 항목이다. 이번에는 보관된 성공 화면을 재표시했고, 새로운 화면 복원을 실행했다고 표시하지 않았다."
    endian = f"새 MATLAB 대조 실험은 동일한 iPhone6 fc100MHz 파일의 4개 구간을 BE와 LE로 각각 읽었다. 기존 CSV에 남은 평균 I RMS {audit['saved_claude_csv_rms_i']:.9f}가 LE 해석에서 {audit['le_mean_rms_i']:.9f}로 재현됐으며, BE 해석에서는 {audit['be_mean_rms_i']:.9f}였다. 이는 검토한 이전 실행이 LE 경로를 사용했다는 직접적인 재현 근거다. 현재 프로젝트의 BE 기록 규약과 충돌하므로 reader 기준을 먼저 일치시켜야 한다. 수집 VI 자체는 이번 audit에서 열어 확인하지 않았다."
    nonlinear = f"LE/256과 BE의 상관은 {correlation[0]:.6f}–{correlation[1]:.6f}였고, 정규화 제곱오차는 {nmse[0]:.6f}–{nmse[1]:.6f}였다. BE scalar 값의 {100*outside[0]:.4f}–{100*outside[1]:.4f}%만 [−128,127] 밖에 있지만 이들이 BE power의 {100*power[0]:.2f}–{100*power[1]:.2f}%를 차지한다. 따라서 단순 gain 256 차이로 볼 수 없다. 작은 정수 구간에서는 byte swap 결과가 원값에 가깝게 비례하므로 구조와 주기가 남을 수 있고, 범위를 넘는 pulse에서 비선형 wrapping이 발생해 스펙트럼·진폭·위상이 달라진다. 기존 화면이 읽힌다는 사실과 물리적 해석을 재검증해야 한다는 판단은 함께 성립한다."
    timing = f"Fs label 차이는 {t['fs_label_difference_ppm']:.6f} ppm이지만 Fs와 주파수 추정치를 같은 비율로 스케일했다면 fH/Fs는 변하지 않는다. 따라서 11.9 ppm을 그대로 복원 오류라고 할 수 없다. 실제 비교해야 하는 것은 sample당 cycle이다. 환산 후에도 {t['remaining_normalized_difference_ppm']:.6f} ppm의 차이가 남고, 전체 {audit['bytes']//4:,} complex samples에서 누적 차이는 {t['whole_capture_relative_cycle_slip']:.9f} cycle이다. 750-column folding을 가정하면 {slip_cells:.3f} cell, 약 반 line의 누적 위치 차이에 해당한다. 이것은 두 추정치를 고정 사용했을 때의 계산값이며, 실제 P139 화면 열화의 원인을 이 항목 하나로 확정한 결과는 아니다."
    pipeline = "성공 그림의 주요 처리 경로는 IQ 읽기 → AM |IQ| → frame별 위치 보정을 반영한 fractional sample phase의 raster cell 누적 → cell mean → 수평 harmonic 제한 K 및 표시용 crop/equalization으로 구분된다. 이 중 image FFT에서 K개 harmonic만 유지하는 연산은 재배치된 cell 이미지의 수평 저역 투영이다. 원본 비균일 sample 위치에서 Fourier least-squares를 푸는 연산과 같지 않다. 후속 iPhone6s 구현에는 실제 비균일 phase matrix를 만든 nearest-one 방식과 grouped noise-aware Fourier 해법이 추가되어 있으며, 저장 CSV도 존재한다. 따라서 전체 연구를 '비균일 Fourier 복원 미구현'으로 요약하면 부정확하다."
    interpretation = "N=359,911과 κ≈1.003–1.07은 Galaxy 377-frame 특정 row의 sample geometry에 대한 수치다. 다른 기기·대역의 신호 강도나 복원 품질을 보장하지 않는다. iPhone6s의 0.908486 대 0.318193은 기존 cell 결과와의 유사도이며 원본 화면과의 정확도가 아니다. LG 정수/fractional 정렬 비교는 동일 P=411 조건이라는 점에서 효과 해석이 비교적 분명하다. Galaxy 개선은 자체 fH 선택, 정렬, frame 수가 함께 바뀐 결과이므로 어느 한 단계만의 이득으로 귀속할 수 없다."
    older_iphone = "기존 iPhone6 238MHz 분석과 현재 100MHz black text 측정은 서로 다른 capture다. 238MHz 기록은 1880-row raster를 사용했지만 ACF의 1881-row 후보 및 G(k) 탐색 경계에 걸린 결과가 남아 있으므로 frame 수를 늘려 반복성이 좋아졌다는 사실만으로 timing 문제를 배제할 수 없다. blanking이나 세로선도 두 half에서 반복될 수 있다. 과거 노트의 'SNR만이 실패 원인' 또는 10,000-frame 외삽은 확정 결론으로 유지하지 않는다."
    bandwidth = "기존 100MHz survey launcher에는 nominalBW_Hz=60 MHz가 있고, 사용자가 제공한 측정 셋업은 120 MHz다. 수신 하드웨어/드라이버 설정 기록으로 해결해야 하는 메타데이터 불일치다. 이를 디지털 subband 폭이나 저역 필터 cutoff와 혼합하면 안 된다. ADC Fs, 실제 analog/DDC passband, 선택한 디지털 처리 대역, 출력 cell 수는 각각 기록해야 한다."
    next_steps = "현재 정리된 재사용 자산은 읽을 수 있는 Galaxy/LG 성공 결과, capture별 timing·정렬 코드, iPhone6s 비균일 Fourier 비교다. iPhone6 100MHz를 다시 비교할 때는 BE/LE 해석과 fH/Fs를 먼저 고정한 동일 구간 대조군을 만들고, frame 정렬·평균 횟수·대역 선택을 각각 분리해 평가해야 한다. 이번 결과는 그 비교에 필요한 원본 위치와 실패 후보를 확정한 검토 기록이다. 새로운 reconstruction 또는 stitching 결과를 제시한 것은 아니다."
    evidence_rows = [
        ["이번 재실행", "동일 바이트의 BE/LE RMS·비선형 차이·PSD·1100-sample fold", "endian_audit.json / endian_comparison.png"],
        ["소스/출력 확인", "기존 reader의 ieee-le, Fs=124.08428e6, nominalBW=60e6", "보관한 run_*black_fc100M*.m 및 공통 reader"],
        ["기존 결과", "Galaxy/LG 성공 PNG, P139 가로띠 PNG, 과거 반복성 지표", "source_snapshot 이미지·CSV·노트; 이번 새 복원 아님"],
        ["계산으로 도출", f"정규화 timing 차이 {t['remaining_normalized_difference_ppm']:.6f} ppm, 전체 {slip_cells:.3f} cells", "두 저장 추정치와 동일 파일 길이로 계산"],
        ["미확정 가설", "가로띠 원인 중 byte swap·누적 timing 오차·정렬·대역 선택의 상대 기여", "동일 조건 복원 A/B가 필요"],
        ["미해결 metadata", "60 MHz 대 120 MHz 수신 BW, 원 acquisition VI endian", "현재 source와 사용자 측정 설명을 따로 보존"]
    ]
    md = ["# 기존 Claude 모바일 복원 자료와 현재 iPhone6 분석의 대조", "", overview, "", "## 1. 기존 성공 화면을 찾았다", "", success, "", "### Galaxy 111.9 MHz", "", f"![Galaxy 기존 성공 화면](source_snapshot/{figures['galaxy']})", "", source_link(figures['galaxy']), "", "### LG X2", "", f"![LG 기존 성공 화면](source_snapshot/{figures['lg']})", "", source_link(figures['lg']), "", "### 기존 iPhone6 100MHz P139", "", f"![기존 P139 가로띠 결과](source_snapshot/{figures['iphone100']})", "", "가로 위치 정보가 크게 흐려지고 글줄 위치에 대응하는 띠가 보인다. 이 PNG만으로 원인을 확정할 수 없다.", "", source_link(figures['iphone100']), "", "## 2. 같은 원본 바이트에서 LE 사용을 재현했다", "", endian, "", nonlinear, "", "![동일 바이트 BE LE 비교](endian_comparison.png)", "", mdtable(audit_head,audit_rows), "", source_link("survey_captures_level_band_linerate_v1.m"), "", source_link("reconstruct_explicit_res_generic_v1.m"), "", "## 3. Fs 이름표보다 samples/cycle을 비교해야 한다", "", mdtable(["항목", "기존 Claude 100MHz", "현재 FAM 기반"],timing_rows), "", timing, "", source_link("run_timing_black_fc100M_v1.m"), "", "## 4. 성공 파이프라인과 실제 비균일 Fourier 구현", "", pipeline, "", mdtable(["대상", "지표/조건", "기록된 수치", "해석 범위"],quality_rows), "", interpretation, "", source_link(theory), "", source_link(metrics_path), "", source_link(galaxy_note), "", f"![Galaxy 반복 표본 파형](source_snapshot/{figures['galaxy_sampling']})", "", source_link(figures['galaxy_sampling']), "", "## 5. 이전 iPhone6 실패 해석과 BW 기록", "", older_iphone, "", bandwidth, "", source_link(iphone_note), "", source_link("run_survey_black_fc100M_v1.m"), "", "## 6. 증거의 종류와 재사용 방향", "", mdtable(["종류", "확인 내용", "근거/범위"],evidence_rows), "", next_steps, "", "## 파일과 실행 범위", "", "- [스냅샷 설명](source_snapshot/README_KO.md)", "- [43개 파일 원본 경로·SHA-256](source_snapshot/SOURCE_INVENTORY.json)", "- [전체 파일 메타데이터 목록](source_snapshot/ORIGINAL_FILE_LIST_METADATA_ONLY.csv)", "- [이번 MATLAB 수치 audit](endian_audit.json)", "- [실행 로그](matlab_audit.log)", "", "스냅샷은 검토용 선별 자료다. RIS와 MAT 의존성을 포함하는 재실행 패키지가 아니므로 보관 코드를 그대로 실행하면 원래 경로와 입력 의존성이 필요하다. 과거 노트의 해석은 당시 주장으로 읽었고, 이번 audit와 충돌하거나 검증되지 않은 부분은 별도로 표시했다.", ""]
    (root/"REPORT_KO.md").write_text("\n".join(md),encoding="utf-8")
    gallery=root/"gallery"
    gallery.mkdir(exist_ok=True)
    p=lambda text: '<p>'+html.escape(text)+'</p>'
    def fig(relative,caption,portrait=False):
        return '<figure'+(' class="portrait"' if portrait else '')+'><a href="../'+html.escape(relative,quote=True)+'" target="_blank"><img loading="lazy" src="../'+html.escape(relative,quote=True)+'" alt="'+html.escape(caption,quote=True)+'"></a><figcaption>'+html.escape(caption)+'</figcaption></figure>'
    body='<header><span class="eyebrow">SOURCE REVIEW + MEASURED BYTE-ORDER AUDIT</span><h1>기존 성공 화면과<br>현재 iPhone6 분석을 연결하다</h1>'+p(overview)+'<div class="metrics"><div><b>'+str(inventory['copied_files'])+'</b><span>SHA-256 확인한 보관 파일</span></div><div><b>'+f"{source_count:,}"+'</b><span>원본 파일 메타데이터</span></div><div><b>'+f"{t['remaining_normalized_difference_ppm']:.6f}"+'</b><span>ppm · 남은 normalized timing 차이</span></div></div></header>'
    body+='<nav><a href="#success">기존 성공 화면</a><a href="#endian">바이트 순서</a><a href="#timing">시간축 비교</a><a href="#method">복원 경로</a><a href="#scope">판정과 근거</a></nav>'
    body+='<section id="success"><h2>01 · Galaxy와 LG 성공 결과</h2>'+p(success)+'<div class="phone-grid">'
    for key,name in [('galaxy','Galaxy 111.9 MHz · K120 equalised'),('lg','LG X2 · fractional alignment · K85')]:
        body+='<article><h3>'+name+'</h3>'+fig('source_snapshot/'+figures[key], '기존 저장 PNG 그대로; 이번에 새 복원한 그림이 아님',True)+html_source(figures[key])+'</article>'
    body+='</div><details open><summary>iPhone6 100MHz · 기존 P139 결과</summary>'+p('글줄에 대응하는 가로띠는 보이지만 개별 글자 가로 구조가 흐려진 기존 결과다. 아래 바이트 순서와 normalized timing 비교는 이 결과를 다시 평가하기 위한 진단이다.')+fig('source_snapshot/'+figures['iphone100'],'기존 black_fc100M_P139_active.png',True)+html_source(figures['iphone100'])+'</details></section>'
    body+='<section id="endian"><h2>02 · 같은 바이트를 다르게 읽으면</h2>'+p(endian)+p(nonlinear)+fig('endian_comparison.png','이번 실제 MATLAB 대조 실험: 동일 바이트, 동일 구간, timing 조정 없음')+table(audit_head,audit_rows)+html_source('survey_captures_level_band_linerate_v1.m')+html_source('reconstruct_explicit_res_generic_v1.m')+'</section>'
    body+='<section id="timing"><h2>03 · label 차이와 sample 좌표의 차이</h2>'+table(['항목','기존 Claude 100MHz','현재 FAM 기반'],timing_rows)+p(timing)+'<div class="formula">δ = (fH,old / Fs,old) − (fH,FAM / Fs,FAM)<br>전체 cycle 차이 = Nsamples × δ<br>750-column 누적 위치 차이 = 750 × Nsamples × δ</div>'+html_source('run_timing_black_fc100M_v1.m')+'</section>'
    body+='<section id="method"><h2>04 · 복원 알고리즘을 단계별로 읽기</h2>'+p(pipeline)+table(['대상','지표/조건','기록된 수치','해석 범위'],quality_rows)+p(interpretation)+html_source(theory)+html_source(metrics_path)+html_source(galaxy_note)+'<details><summary>Galaxy의 반복 표본과 파형 그림</summary>'+fig('source_snapshot/'+figures['galaxy_sampling'],'Galaxy 377-frame 파형과 표본 구조; iPhone6 100MHz 수치로 사용하지 않는다')+html_source(figures['galaxy_sampling'])+'</details></section>'
    body+='<section id="scope"><h2>05 · 확정한 사실과 남은 가설</h2>'+p(older_iphone)+p(bandwidth)+table(['증거 종류','확인 내용','근거/범위'],evidence_rows)+p(next_steps)+html_source(iphone_note)+html_source('run_survey_black_fc100M_v1.m')+'</section>'
    body+='<section><h2>보관 파일 탐색</h2><p>파일명을 입력하면 43개 선별 파일과 원본 경로를 찾을 수 있다.</p><input id="filter" placeholder="예: galaxy, reader, fourier, fc100M" oninput="filterFiles(this.value)"><div class="scroll"><table id="files"><thead><tr><th>스냅샷 파일</th><th>원본</th><th>bytes</th><th>SHA-256</th></tr></thead><tbody>'
    for rel,e in entries.items():
        body+='<tr><td><a href="../source_snapshot/'+html.escape(rel,quote=True)+'">'+html.escape(rel)+'</a></td><td><a href="'+Path(e['original_path']).as_uri()+'">원본 열기</a></td><td>'+f"{e['bytes']:,}"+'</td><td><code>'+e['sha256']+'</code></td></tr>'
    body+='</tbody></table></div><div class="downloads"><a href="../REPORT_KO.md">한국어 보고서</a><a href="../endian_audit.json">실제 audit JSON</a><a href="../source_snapshot/SOURCE_INVENTORY.json">원본·해시 inventory</a><a href="../source_snapshot/ORIGINAL_FILE_LIST_METADATA_ONLY.csv">전체 파일 목록</a></div></section>'
    css='body{margin:0;background:#f3f6fa;color:#17283b;font-family:"Malgun Gothic",system-ui,sans-serif;line-height:1.75}main{max-width:1240px;margin:auto;padding:28px}header{background:#fff;border-top:6px solid #176ba2;padding:35px 40px;border-radius:10px}.eyebrow{font-size:12px;letter-spacing:1.2px;color:#4f6e82}h1{font-size:40px;line-height:1.3}h2{font-size:25px}.metrics{display:flex;gap:38px;flex-wrap:wrap}.metrics div{display:flex;flex-direction:column}.metrics b{font-size:28px;color:#176ba2}.metrics span{font-size:12px;color:#607285}nav{position:sticky;top:0;z-index:2;padding:18px 4px;background:#f3f6faf0;display:flex;gap:22px;flex-wrap:wrap}a{color:#165e94}section{background:white;border:1px solid #dce4ec;border-radius:9px;margin:18px 0;padding:26px 30px;scroll-margin-top:75px}figure{margin:18px 0}img{width:100%;height:auto}figcaption,.source{font-size:12px;color:#5a6e7e}.phone-grid{display:grid;grid-template-columns:1fr 1fr;gap:24px}.portrait{max-width:480px;margin:20px auto}.portrait img{border:1px solid #dce4ec}.source code{overflow-wrap:anywhere}details{border:1px solid #dae3eb;border-radius:7px;padding:12px;margin:18px 0}summary{cursor:pointer;font-weight:600}.scroll{overflow:auto;max-height:620px}table{border-collapse:collapse;font-size:12px;width:100%}th,td{padding:10px 12px;border-bottom:1px solid #e1e8ed;text-align:left;vertical-align:top}th{background:#edf3f8;white-space:nowrap}.formula{background:#edf5fb;padding:20px;font-family:monospace;border-left:3px solid #176ba2}.downloads{display:flex;gap:20px;flex-wrap:wrap;margin:24px 0}input{padding:12px;border:1px solid #adbfcd;border-radius:5px;width:min(90%,500px);margin:14px 0}#files{white-space:nowrap}#files code{font-size:10px}@media(max-width:760px){main{padding:10px}header,section{padding:20px}.phone-grid{grid-template-columns:1fr}h1{font-size:29px}}'
    js='function filterFiles(q){q=q.toLowerCase();document.querySelectorAll("#files tbody tr").forEach(r=>r.hidden=!r.textContent.toLowerCase().includes(q));}'
    (gallery/'index.html').write_text('<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>기존 모바일 복원 자료 대조</title><style>'+css+'</style><main>'+body+'</main><script>'+js+'</script></html>',encoding='utf-8')
    manifest={'status':'completed','source_count':source_count,'snapshot_count':len(entries),'snapshot_hashes_verified':True,'audit_status':audit['status'],'saved_csv_rms_reproduced':audit['saved_csv_rms_reproduced'],'new_reconstruction_performed':False,'nominal_bandwidth_disagreement_unresolved':True,'timing':t,'derived_750cell_full_capture_slip':slip_cells,'artifacts':['REPORT_KO.md','gallery/index.html','endian_audit.json','endian_comparison.png']}
    (root/'REVIEW_SUMMARY.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':'complete','report':str(root/'REPORT_KO.md'),'gallery':str(gallery/'index.html'),'snapshot_hashes_checked':len(entries)},ensure_ascii=False))


if __name__=='__main__':
    main()
