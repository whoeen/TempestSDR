# Stitching 준비: 기존 LG X2 / iPhone 6 데이터 인벤토리

검토일: 2026-10-22. 원본 IQ를 새로 스캔하거나 MATLAB을 실행하지 않았다. 아래 값은 저장된 manifest, 설정, 결과 JSON/CSV와 코드의 provenance 점검 결과다. **iPhone 6와 iPhone 6s를 구별했다.**

## 1. 데이터 출처와 계산 범위

기준은 `research/mobile_mipi_leakage` 아래의 다음 파일이다.

- `raw_iq/RAW_IQ_RELEASE_MANIFEST.json`: 2026-10-21T05:19:17Z 생성, dataset 19개. 각 원본 bytes와 SHA-256, split asset identity 기록.
- `DATASETS.md`: 기종, 파일명 유래 RF center/BW/stored Fs 및 측정 조건의 짧은 라벨.
- `README.md`의 Result provenance, `TF_DRIVER_STUDY_KR.md` 첫 정정 문단: 역사적 little-endian 결과와 big-endian 재분석을 구별.
- `coherent_hsv_resampling.py`: `DEVICES`, `read_iq`, `fit_phase_line`, `process`; big-endian reader와 24-frame timing/phase 처리.
- `coherent_results/three_devices_big_endian/{lgx2,iphone6}/{metrics.json,frame_diagnostics.csv,checkpoint_metrics.csv,vertical_line_phase.csv}`.
- `coherent_results/tf_big_endian/iphone6/tf_metadata.json`와 `analyze_iq_tf.py`.
- `matlab_agentic_lab/results/licensed_baseline_20261022/config.json`, `lgx2/frame_parameters.csv`, `lgx2/frame_progression.csv`.

공통 raw format은 headerless signed int16 I,Q interleaved, **big-endian**, 4 bytes/complex sample이다. center/BW/Fs는 raw header에서 읽힌 값이 아니라 외부 기록이다. 이 점검에서 원본 전체 hash를 다시 계산하지 않았다. 아래 sample count는 manifest bytes/4, duration은 sample count/외부 stored Fs로 계산했다. 실제 uninterrupted hardware capture duration이나 lost-sample 부재를 뜻하지 않는다.

원본은 [기존 raw IQ release](https://github.com/whoeen/TempestSDR/releases/tag/mobile-mipi-raw-iq-2026-10-21)에 있다.

## 2. 두 기기에 해당하는 8개 캡처

MHz와 MS/s는 십진 단위다. 예상 RF 구간은 `fc ± BW/2`라는 **명목 계산**이며 실제 calibrated usable passband가 아니다.

| Manifest ID | 기기/파일명 조건 | fc MHz | BW MHz | Stored Fs MS/s | Bytes | Complex samples | 계산 길이 s | 명목 RF 구간 MHz |
|---|---|---:|---:|---:|---:|---:|---:|---|
| `lgx2_230m` | LG X2, left-middle/top | 230 | 20 | 119.678470 | 2,673,000,000 | 668,250,000 | 5.583711 | 220–240 |
| `lgx2_344p8m` | LG X2, 현 baseline | 344.8 | 60 | 136.565510 | 3,742,200,000 | 935,550,000 | 6.850558 | 314.8–374.8 |
| `iphone6_book34_238m` | iPhone 6, book34/top-left | 238 | 60 | 124.085710 | 2,613,600,000 | 653,400,000 | 5.265715 | 208–268 |
| `iphone6_bottom_middle_238m` | iPhone 6, bottom-middle | 238 | 60 | 124.085710 | 2,435,400,000 | 608,850,000 | 4.906689 | 208–268 |
| `iphone6_topleft_238m` | iPhone 6, top-left/big-endian 재분석 | 238 | 60 | 124.085710 | 4,039,200,000 | 1,009,800,000 | 8.137923 | 208–268 |
| `iphone6_book93_238m` | iPhone 6, book93/top-middle | 238 | 60 | 124.085710 | 3,504,600,000 | 876,150,000 | 7.060845 | 208–268 |
| `iphone6_response_308m` | iPhone 6, response screen 라벨 | 308 | 60 | 124.085710 | 3,623,400,000 | 905,850,000 | 7.300196 | 278–338 |
| `iphone6_response_312m` | iPhone 6, response/background 라벨 | 312 | 49 | 124.085710 | 5,346,000,000 | 1,336,500,000 | 10.770781 | 287.5–336.5 |

파일명 원문:

```text
230mhz_20m_119.67847m_left_middle top_LGX22019.rIs
LGX22019_344.8M_60M_136.56551M.rIs
238M_60M_124.08571_topleft_iphone6_book34page_.rIs
238M_60M_124.08571M_bottom middle_iphone6.rIs
238M_60M_124.08571M_topleft_iphone6.rIs
238M_60M_124.08571M_topmiddle_book93page_iphone6.rIs
308M_60M_124.08571M_bageung hwameon_iphone6.rIs
312M_49M_124.08571M_baeung.rIs
```

Manifest SHA-256:

| ID | SHA-256 |
|---|---|
| `lgx2_230m` | `d29d961bf6f7d7c5a40bf477944a82ee984cc8f64ae987a066bd7763584435d3` |
| `lgx2_344p8m` | `709da78b467f8e97983960837966765fd9f8e4813f0d50e49211b8617dc228f3` |
| `iphone6_book34_238m` | `e17e8d62b15f0d8f94312b4520f8c301953c1209af6ee25699e79e52f2ba0878` |
| `iphone6_bottom_middle_238m` | `6617bc27d4d72bfa432e7acd67eed050bc8f38fe8c141c1a46a98f1e0f3029d2` |
| `iphone6_topleft_238m` | `2d0c360bd5ad9804f94ae936638a2aa31d2ed40423d6c85afe78c82656061de1` |
| `iphone6_book93_238m` | `bf04555dde3cb98b49933f58d17761753f6d488ca8b31671fe800b490dabfb9e` |
| `iphone6_response_308m` | `efa368706446bf52b7302a05311381ba2c566089c9faec78d2d8fb2db419481f` |
| `iphone6_response_312m` | `615c3efeaf85b6664d61e5d7a7d9a3206cdec71b6a26890b76450bdee9b991c5` |

## 3. 이미 compatible overlapping sweep가 있는가?

**검토한 기록에는 동일 조건의 연속 overlapping sweep로 검증된 세트가 없다.**

| 조합 | 명목 대역 관계 | 판단 |
|---|---|---|
| LG 230 ↔ 344.8 MHz | 240–314.8 MHz에 **74.8 MHz gap** | overlap 기반 band alignment 직접 적용 불가. Stored Fs의 Nyquist 폭을 receiver BW로 바꿔 계산하면 안 됨 |
| iPhone6 238 ↔ 308 MHz | 268–278 MHz에 **10 MHz gap** | 대역 overlap 없음. 서로 같은 화면/위치/전송 파형인지도 미기록 |
| iPhone6 238 ↔ 312 MHz | 268–287.5 MHz에 **19.5 MHz gap** | overlap 없음 |
| iPhone6 308 ↔ 312 MHz | 312의 명목 49 MHz 구간 전체가 308의 60 MHz 구간 안에 포함 | 정렬 재현성 시험 후보는 될 수 있으나 **명목 합성 대역 확대는 0 MHz**. 화면/위치/gain/timing 동일성이 미검증 |
| iPhone6 238 MHz 네 파일 | 같은 nominal RF band | 독립 화면·probe 위치 조건이 섞여 있음. bandwidth 확장용 sweep가 아님 |

`390M_60M_124.08571M_topmiddle.rIs`, `311m_23m_110.11059m.rIs`, `313.9m_25m_110.11059m.rIs`, `444Page.rIs` 등은 현재 manifest의 model unresolved 상태를 유지한다. 이 파일을 LG나 iPhone6 sweep의 중간 band로 임의 편입하지 않는다. `311m_55.05487m_20m.rIs`는 **iPhone6s**이므로 iPhone6 자료로 합치지 않는다.

이 결론은 저장된 자료의 provenance 범위에 대한 것이다. 사용자가 별도로 관측한 넓은 sweep 내 복원 가능성을 부정하는 것이 아니며, 그 실험의 band별 IQ·측정 설정을 받으면 별도 세트로 연결할 수 있다.

## 4. iPhone 6 (238 MHz)의 유효한 기존 복원·위상 근거

### 4.1 올바른 endian으로 처리한 P24 결과

근거: `coherent_results/three_devices_big_endian/iphone6/metrics.json`와 `frame_diagnostics.csv`. 입력은 `iphone6_topleft_238m`이다. 처리 코드는 `coherent_hsv_resampling.py`의 `>i2` reader, 4-point Catmull–Rom fractional sampler, frame별 column shift 및 row-linear phase fit이다.

| 항목 | 저장된 결과 |
|---|---:|
| 처리 frame 수 | 24 |
| 기존 line-rate 가정 | 112,805.083 Hz |
| raster | 1880 × 1100 |
| raw samples / line | 1100.0010523 |
| raw samples / raster cell | 1.0000009566 |
| resampling 출력률 | 124.0855913 MS/s, k=1 |
| 자동 active crop | 1334 × 750, maximum local-variance circular crop |
| 전체 평균 amplitude-normalized phase concentration | 0.198677 → 0.220290, 1.10878배 |
| active-crop concentration | 0.201802 → 0.227276, 1.12623배 |
| odd/even log-magnitude correlation | 0.513911 |
| odd/even horizontal-edge correlation | 0.012114 |
| odd/even weighted phase agreement | 0.063226 |
| odd/even weighted phase RMSE | 1.745214 rad |
| frame2–24 가로 profile alignment score | 약 0.993568–0.999302 |
| frame2–24 row-linear phase 이후 complex coherence | 약 0.002433–0.080962 |

`progress_P024.png`를 이번 점검에서 직접 확인했다. AM 평균에는 큰 어두운 직사각형 영역, 강한 세로선, 일부 숫자/버튼 유사 구조가 보인다. 이는 완전한 화면 fidelity, true RGB, 또는 broadband coherent reconstruction의 검증이 아니다. **가로 profile은 매우 잘 정렬되지만 complex frame 반복성은 약한 사례**로 기록한다.

P24의 phase fit은 같은 frame/reference의 여러 row에서 smoothing·unwrap·weighted least-squares를 수행한 뒤 그 frame의 coherence를 계산한다. 독립 holdout phase validation 설계가 아니다. odd/even 비교도 동일 reference/timing 추정을 공유한다. 따라서 수치를 stitching 정합 성공률이나 물리 SNR로 재명명하지 않는다.

### 4.2 세로선 phase 기록의 의미

`vertical_line_phase.csv`에는 strongest stripe **x=351 (0-based)**를 0° 기준으로 한 상대 residual phase가 있다. 이 column의 row phase concentration은 약 0.80021이다. 다른 예는 x=317에서 −94.07°/0.50277, x=327에서 +28.35°/0.55851, x=872에서 −135.01°/0.07920이다. 마지막처럼 concentration이 작은 선의 대표 위상은 신뢰도가 낮다.

이 값은 row 공통 위상을 제거한 뒤의 수신 complex stripe 통계다. receiver absolute RF phase, DSI bit phase, DDIC pin phase 또는 column-driver 발사 위상으로 식별되지 않았다. 새로운 tuning의 위상 기준으로 그대로 가져갈 수도 없다.

### 4.3 유효 TF 결과

현재 참조할 파일은 `coherent_results/tf_big_endian/iphone6/tf_metadata.json`이다.

- row time 8.864848759 µs, equivalent raster-cell time 8.058953417 ns.
- row STFT: window 1100 samples, NFFT2048, 저장된 Fs/N 기준 약112.805 kHz, bin spacing60.5887 kHz, 6 frames 평균.
- column-position 분석: window64 samples, hop8, NFFT64, Fs/N≈1.93884 MHz, 4 frames와 row stride4로1880 line spectra 평균.
- `true_resolution_hz`라는 기존 필드명은 Fs/window-length 값을 담고 있다. 실제 spectral resolving power/ENBW는 window를 함께 고려해야 하므로 필드명을 문자 그대로 해석하지 않는다.
- column 축은 line 내 시간 위치이며 같은 physical column의 여러 row 관측을 원래 연속 시간으로 연결한 것이 아니다.

### 4.4 보존돼 있지만 물리 추론에서 제외할 결과

`tf_results/iphone6/reconstruction_p488*.png`, `reconstruction_p488_metrics.csv`, `tf_metadata.json`은 과거 little-endian 처리 계열이다. `TF_DRIVER_STUDY_KR.md` 첫 정정 문단이 해당 복원·STFT·위상·상관값을 폐기 대상으로 명시한다. 예컨대 P488의 image correlation0.0244나 “UI가 안 보인다” 결론을 올바른 raw decoding의 성능 한계로 인용하면 안 된다. `make_iphone6_attempt.py`는 이미 생성된 PNG의 표시·median·row/column-template 제거 도구이며 올바른 IQ 재분석 근거가 아니다.

2026-10-22 MATLAB licensed baseline의 Apple 입력은 **iPhone6s/311 MHz**이다. 그 P8의 좋은 키패드 결과 또는 phase 수치를 iPhone6/238 MHz의 새 MATLAB 결과로 설명하지 않는다.

## 5. LG X2 (344.8 MHz)의 기존 근거

P24 big-endian 결과: `coherent_results/three_devices_big_endian/lgx2/metrics.json`.

- 입력 `lgx2_344p8m`; stored Fs136.565510 MS/s, configured BW60 MHz.
- prior fH88679.652541 Hz, raster1478×1022, raw1539.9869766 samples/line, 1.506836572 samples/cell.
- fractional output k=2, 181.261209794 MS/s. 이것은 수신 대역폭 증가가 아닌 output grid 변경이다.
- 전체 평균 phase concentration0.185535→0.535078(2.88397배), active crop0.184221→0.667282(3.62217배).
- odd/even weighted phase agreement0.901781, phase RMSE0.482012 rad, horizontal edge correlation0.497688.

새 MATLAB P8 결과의 provenance는 `matlab_agentic_lab/results/licensed_baseline_20261022/lgx2`다. `frame_progression.csv`에서 AM odd/even correlation은 P4 0.606001→P8 0.729325, P8 coherent/incoherent mean ratio0.57143이다. `frame_parameters.csv`의 frame2–8 held-out mixture coherence는 0.008359–0.496199로 넓게 분포한다. 최신 결과는 training-row/validation-row phase를 분리하지만 가로 정렬은 같은 reference를 쓰고, frame1은 자기 자신 비교다.

과거 P24와 새 P8의 지표·crop·phase fit·정규화가 다르므로 두 숫자를 같은 성능 척도의 개선 전후로 연결하지 않는다. 공통 결론은 해당 단일 band의 시간 반복성이 관측된다는 것이며, band 간 transfer와 phase alignment는 새 수집에서 검증할 항목이다.

## 6. 기존 자료를 stitching 측정에 사용할 범위

1. LG344.8/iPhone6 238 MHz를 첫 재방문 중심 후보와 raw-format/타이밍 baseline으로 사용한다.
2. 같은 한 캡처를 software subband로 나눈 시험은 코드·phase convention·delay 추정의 control로 사용할 수 있다. 실제 retune 사이 재현성 검증과 구별한다.
3. iPhone6 308/312 MHz 두 캡처는 동일 화면/위치 여부가 확인된 뒤 overlapping repeatability 예비시험 후보가 된다. 현재 명목 passband 계산으로는 새로운 BW를 추가하지 않는다.
4. 새 sweep는 동일 pattern/geometry/gain/clock, actual fc/Fs/BW readback, tuning/settling/start timestamps, dropout 기록, anchor revisit를 함께 저장한다. 기존 capture들이 같은 프로토콜로 수집됐다고 소급 가정하지 않는다.

**현재 상태:** 기존 원시 자료와 reconstruction provenance는 정리됐지만, LG/iPhone6에 대한 band-to-band complex overlap validation이나 새로운 stitching 수집은 수행되지 않았다.
