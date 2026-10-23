# iPhone 6s 기존 복원·원시자료 점검 — 2026-10-23

담당: iphone6s_result_audit. 범위: 저장된 결과, 원본 파일 존재/크기, 설정 코드와 provenance 검토. 이 점검에서 MATLAB 또는 IQ 재처리를 실행하지 않았고 원본·기존 코드를 수정하지 않았다.

## 1. 확인한 결론

**iPhone 6s는 올바른 big-endian IQ로 실행된 MATLAB P8 결과에서 키패드 화면이 식별된다.** P008_comparison.png와 review_overview.png를 직접 열어 확인했다. 원형 12개 키, 1–9 및 0 숫자, 별/샵 기호, 하단 통화 버튼 윤곽, 좌하단 AssistiveTouch 위치가 원본 사진과 대응한다. 밝고 강한 세로선은 남아 있다. 작은 상단 글자, 원래 색상, 모든 세부가 복원됐다는 뜻은 아니다.

현재 MATLAB baseline의 Apple 입력은 iPhone 6s / 311 MHz이다. 별도 iPhone 6 / 238 MHz 결과로 설명하면 안 된다. 이전 P200 제공 이미지는 화면의 위치·구조를 검토하는 참고이지만, 저장소 README가 little-endian 역사 자료로 구분하고 있으므로 현재 big-endian 결과와 위상·RF 성능을 직접 비교하지 않는다.

## 2. 원시파일 identity

- 경로: C:/Users/leechanghoon/Desktop/mobile/0625/311m_55.05487m_20m.rIs
- 이번 파일 stat 확인: 1,069,200,000 bytes. Manifest와 동일한 크기.
- Format: headerless big-endian signed int16 interleaved I,Q, 4 bytes/complex.
- 복소 샘플 수: 267,300,000 (bytes에서 계산).
- Stored Fs: 55.054870 MS/s, RF center: 311 MHz, receiver BW: 명목 20 MHz. 파일명·기존 기록 유래이며 header에서 읽힌 장비 readback이 아니다.
- 길이: 4.855156320 s (샘플 수/Fs 계산).
- Manifest 기대 SHA-256: d55e8616140e4658f4fdf8bc7bfa63276fc17a9640121fea15952d25c9621af7. 이번 점검에서 전체 hash 재계산하지 않음.
- 모델 미확인 별도 파일: 20260625_fs55.05487m_fc311m_25m_smallh_iphoneergentcallidisplay.rIs (25 MHz 표기). 같은 center/Fs만으로 이를 6s라고 합치지 않는다.

## 3. 재현 가능한 최신 수치

근거: results/licensed_baseline_20261022/iphone6s/metrics.json, frame_parameters.csv, frame_progression.csv.

| 항목 | 확인 값 |
|---|---:|
| Run ID | 20261022_041904_607 |
| Raster frames | 8 |
| prior line rate | 112,613.234 Hz |
| line period | 488.884547974 samples / 8.879951001 µs |
| frame period | 917,636.666798 samples |
| frame rate | 59.996371104 Hz |
| full raster | 1877 rows × 750 columns |
| active crop | rows [1400:1877,1:856], columns 1:750 →1334×750 |
| raw samples/raster column | 0.651846063966 |
| raster column time | 11.839934668 ns |
| P4 odd/even AM correlation | 0.827105635 |
| P8 odd/even AM correlation | 0.899234078 |
| P8 coherent/incoherent mean ratio | 0.798215032 |
| P2–P8 held-out row mixture coherence | 0.729097251–0.807590757 |
| P8 uncorrected coherent power | 440.398438 count² |
| P8 global-phase corrected power | 6417.67236 count² |
| P8 row-phase corrected power | 6408.08398 count² |

Global phase 보정으로 큰 상쇄가 줄며, 이 P8에서는 row-linear 보정이 global보다 우월하지 않다. 이것은 원하는 신호/잡음이 분리된 SNR 증가 수치가 아니다. Phase fitting은 row 일부를 분리해 평가하지만 가로정렬과 기준frame은 공유된다. 반복적인 세로선도 상관·coherence에 기여할 수 있다.

보간은 4-point Catmull–Rom complex evaluation이고 nearest-AM 대조군이 있다. 한 출력열당 1점을 만드는 가상 raster rate 84.4599255 MS/s는 실제 ADC 재측정률이나 검증된 MIPI pixel clock이 아니다.

## 4. 직접 본 이미지와 수치 배열 위치

- 공유용 6분할: results/licensed_baseline_20261022/iphone6s/P008_comparison.png
- 원본/P1/P4/P8 비교: results/licensed_baseline_20261022/review_overview.png
- 단독 P1/P4/P8 AM, coherent, global coherent, HSV 및 MAT: signal_processing/outputs/20261022_041904_607/iphone6s/
- 수치 배열: 위 outputs 폴더의 raster_final.mat (am, nearestAm, coherent, globalCoherent, uncorrected, rowConsistency, activeRows/Cols, normalization).
- 위상 색은 측정 complex angle의 상대색이며 원래 화면 RGB가 아니다. masked HSV는 별도 P008_phase_hsv_log_masked.png.
- 원본 참고사진: ../provided_restoration_analysis/iphone6s_original.png
- 역사적 P200 직접 열어 봄: ../provided_restoration_analysis/iphone6s/iphone6s_P200_Coherent_HSV_median_off.png. 정확한 기존 세부를 보존하되 physical inference에는 provenance 제한을 적용한다.

## 5. 재사용 코드와 다음 실행 조건

- signal_processing/mobileBaselineConfig.m: 위 6s timing/crop/metadata.
- signal_processing/readRisIqBlock.m: big-endian IQ reader.
- signal_processing/sampleFractionalRaster.m: complex cubic/nearest control.
- signal_processing/compareRasterAverages.m: frame마다 가로정렬, global/row phase 대조, checkpoint PNG/MAT/CSV.
- signal_processing/runMobileBaseline.m: PSD/STFT/주기탐색과 raster orchestration.

추가 누적을 실행한다면 cfg.devices를 iphone6s 하나로 선택하고 max_frames/checkpoints를 명시한 새로운 output root를 사용한다. 기존 파일 전체는 약291frames 분량이며 P200까지 독립된 연속 구간을 읽는 것이 길이상 가능하지만, late-frame phase 안정성과 timing drift는 실제 처리로 검증해야 한다. TempestSDR EOF loop를 새로운 관측frame으로 세면 안 된다.

이 검토에서 새로 확인된 실시간 수신기 설정 파일은 없다. 위 timing은 legacy_benchmark.py에서 이어진 성공 raster fit이고 hardware readback으로 승격하지 않는다. 사용자의 실시간 복원 성공 진술은 새 재분석의 동기이며, 이번 노트는 이를 부정하지 않는다.

## 6. 참고한 로컬 기록

- ../DATASETS.md
- ../raw_iq/RAW_IQ_RELEASE_MANIFEST.json
- ../README.md, Result provenance
- ../vendor/legacy_benchmark.py, make_devices()
- results/licensed_baseline_20261022/REPORT_KO.md
- results/licensed_baseline_20261022/iphone6s/metrics.json
- results/licensed_baseline_20261022/iphone6s/frame_parameters.csv
- signal_processing/mobileBaselineConfig.m
- signal_processing/compareRasterAverages.m
- knowledge/stitching/mobile_capture_inventory.md (iPhone 6와 6s 구분)
