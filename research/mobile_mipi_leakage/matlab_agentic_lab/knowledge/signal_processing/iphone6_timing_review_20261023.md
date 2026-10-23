# iPhone 6 재복원 전 기존 결과·타이밍 검토

검토일: 2026-10-23 (Asia/Seoul). 범위: 코드와 저장된 메타데이터/CSV의 읽기 검토. 원시 IQ 연산, MATLAB 실행, 새 복원 화면 생성은 수행하지 않았다. profile drift 회귀만 기존 CSV에서 계산했다.

## 1. 결과 계보

- TF_DRIVER_STUDY_KR.md:3은 과거 little-endian Python 결과의 복원·STFT·위상·상관 수치를 명시적으로 폐기한다. 따라서 tf_results/iphone6/reconstruction_p488*.png의 실패와 image correlation 0.0244를 올바른 디코딩의 한계로 인용하면 안 된다.
- make_iphone6_attempt.py:16–21은 기존 PNG의 median/row-column 평균 제거만 한다. 원시 복원이 아니다. P488,1880×750 표시는 :26–27에 하드코딩되어 있다.
- 현재 analyze_iq_tf.py:36–41과 coherent_hsv_resampling.py:103–110은 big-endian interleaved signed int16 I,Q를 읽는다. 현재 코드 정정이 과거 tf_results PNG의 재생성을 뜻하지 않는다.
- 유효한 기존 iPhone 6 결과는 coherent_results/three_devices_big_endian/iphone6/ 및 coherent_results/tf_big_endian/iphone6/이다. 238 MHz top-left 한 파일의 P24다.
- matlab_agentic_lab/results/licensed_baseline_20261022/iphone6s/는 iPhone 6s 311 MHz 자료다.

## 2. 입력과 수치 의미

| 항목 | 기존 값 | 상태 |
|---|---:|---|
| 저장 Fs | 124.085710 MS/s | 파일명/외부 메타데이터, header 내 값 아님 |
| 명목 BW | 60 MHz(238/308 MHz),49 MHz(312 MHz) | 외부 메타데이터 |
| fH | 112805.083 Hz | 기존 raster 가정 |
| sample/line | 1100.00105225755 | Fs/fH 파생 |
| total rows | 1880 | 기존 가정, active1334와 다름 |
| sample/frame | 2068001.97824419 | rows×sample/line 파생 |
| 1100열 출력률 | 124.0855913 MS/s | 출력 grid |
| 750열 출력률 | 84.60381225 MS/s | 출력 grid |

coherent_hsv_resampling.py:55–67,426–434가 위 geometry를 고정한다. 1334×750 crop은 :238–247의 maximum local-variance circular window이며 물리 blanking 검출값이 아니다. 강한 clutter가 선택을 좌우할 수 있다. 출력 column을 실제 pixel time으로 확정하지 않는다.

취득 API의 actual/coerced Fs 기록이 있으면 파일명과 대조한다. 없으면 Fs를 조건부로 쓰되 초기 timing 탐색은 sample 단위로 수행할 수 있다. BW60/120 MHz나 RF중심238 MHz를 Fs 대신 넣지 않는다.

## 3. 유효한 BE P24 진단

metrics.json:64–77:
- odd/even log-magnitude correlation 0.5139109353.
- odd/even horizontal-edge correlation 0.0121140200.
- weighted phase agreement 0.0632264167.
- weighted phase RMSE 1.7452138662 rad.

frame2–24의 가로 profile correlation은 약0.993568–0.999302이나 row-phase 보정후 complex coherence는 약0.002433–0.080962이다. 반복 세로 profile 정렬과 전체 complex 화면 반복성은 다른 문제다.

knowledge/stitching/mobile_capture_inventory.md:102의 기존 시각 검토에는 AM에 큰 직사각형과 일부 숫자/버튼 유사 구조가 이미 보인다고 기록되어 있다. 이 P24 AM을 control로 먼저 표시한다.

### 저장된 shift로부터 추가 timing 후보

frame_diagnostics.csv의24개 shift를 frame index0…23에 선형회귀했다. raw IQ를 읽지 않았다.

- shift slope = −0.3293769363 columns/frame.
- aligned_start=nominal−shift×cell_samples(:464)이므로 period 보정 후보 = +0.3293772514 samples/frame.
- 후보 frame period = **2068002.30762144 samples**.
- 1880 rows 유지시 조건부 fH=**112805.06503318 Hz**, fv=60.0026941666 Hz.

반복 clutter를 추적한 값일 수도 있으므로 최종 timing이 아니다. 이전2068001.97824419와 독립구간에서 비교할 초기후보다. fH를0.1 Hz 바꾸면1880행 동안 약1.83 sample의 line-end 위치 변화가 생기므로 fractional 미세탐색이 필요하다.

## 4. 기존 알고리즘 한계

1. **line/frame 독립검출 없음.** coherent_hsv_resampling.py:433,452는 rows×sample/line을 frame period로 쓴다. 단일 가로 profile shift는 frame내 누적 row기울기, vertical slip, 불규칙 blanking을 고치지 못한다.
2. **period ambiguity.** 최대 autocorrelation peak가 물리 row라는 보장은 없다. packet/blanking/clutter가 배수·분수 지연을 만들 수 있다. L,2L,L/2와 다른 강한 peak를 긴지연 frame recurrence 및 영상2차원 구조로 비교한다. 이는 RF/ADC Nyquist alias와 별개다.
3. **crop 확인편향.** 전체 raster와 row/column profile을 먼저 보존한다. rows1880은 후보이며 variance crop으로1334×750를 만들었다고 검증된 것이 아니다.
4. **phase fit 독립성 부족.** coherent_hsv_resampling.py:175–201은 동일 frame/reference로 smoothing·unwrap·weighted LS 후 coherence를 잰다. :265–279의 odd/even도 timing/reference를 공유한다.
5. **row-phase CFO ambiguity.** row간격 위상 관측은 fH 배수 ambiguity가 있다. compareRasterAverages.m:76–93처럼 격행 학습이면 일정2-row spacing에 대해 fH/2 ambiguity도 생길 수 있다. sparse reliable-row gaps도 unwrap을 어렵게 한다. full-sample-time CFO 확인전 row slope를 실제 RF 주파수로 확정하지 않는다.
6. **AM을 먼저 확인.** 약한 phase coherence에서 phase추정 자유도를 늘리면 간섭을 강화할 수 있다. AM, 미보정 complex, global-phase, 검증된 row-phase 평균을 같은 scale로 유지한다.
7. **Cubic은 anti-alias filter가 아님.** sampleFractionalRaster.m:3–4에 명시된다. 750열 출력84.604 MS/s에는 명목60 MHz centered complex passband가 들어가지만 원본 out-of-band noise/spur는 filter없이 접힐 수 있다. 1100열 grid는 원Fs와 거의 같아 첫control로 적합하다.
8. **full-band가 최적은 아님.** full-band AM과 같은 capture의 subband들을 비교한다. PSD최대값/stripe상관만으로 bestband를 고르지 않고 독립edge재현성과 화면구조로 검증한다.

## 5. 재시도 순서

1. 확정 iPhone6 6개와6s1개를 구분하고 byte수,범위hash,endianness,offset을 기록한다.
2. iPhone6s 현재 P1/P4/P8 baseline을 제시한다. licensed_baseline_20261022/iphone6s/frame_progression.csv의 P8 AM odd/even r=0.8992340784, coherent/AM=0.798215는 그capture결과다.
3. iPhone6 각파일의 BE full-band AM 단일frame/P4/P8을 만들고1880×1100 및 두period후보를 control로 유지한다.
4. sample-domain envelope/power의 line/long-frame lag를 독립탐색한다. subband peakfamily와 L배수/분수후보를 비교한다. 확인된 frameperiod에 대해 totalrow후보 및 fractionallineperiod를 미세탐색한다.
5. 앞구간에서 timing/filter를 정하고, 뒤의 겹치지 않는구간에서 영상/edge재현성을 평가한다. row/column template제거잔차는 별도diagnostic이다.
6. 맞는timing에서 P16/P32/... 동일contrast 평균진전을 표시한후 complexphase유효성을 확인한다.
7. 화면,probe위치,fc가다른 모든capture를 동일geometry로 성공했다고 묶지 않는다.

## 6. 경계·독립성

compareRasterAverages.m:16–19는 실제파일크기로 최대frame수를 제한하고 :53–55는 finite frame을 순차읽는다. 이원칙을 유지한다. readFrame:204–211의 범위hash는 provenance지만 startshift의 작은경계overlap과 원본중복block은 별도확인한다.

TempestSDR raw playback loop는 새 독립관측이 아니다. 반복재생의 표시안정성을 실제P증가에 따른 noise감소로 보고하지 않는다. 독립검증구간 사이에 최소1frame여유를 두고 interpolation/filter support까지 겹치지 않는지 확인한다. 같은bytesblock은 중복증거지만 hash차이만으로 확률적독립성이 증명되지는 않는다.

## 7. 근거 경로

기준: research/mobile_mipi_leakage/.
- TF_DRIVER_STUDY_KR.md, make_iphone6_attempt.py, analyze_iq_tf.py, coherent_hsv_resampling.py.
- coherent_results/three_devices_big_endian/iphone6/{metrics.json,frame_diagnostics.csv}.
- matlab_agentic_lab/signal_processing/{sampleFractionalRaster.m,compareRasterAverages.m,mobileBaselineConfig.m}.
- matlab_agentic_lab/knowledge/stitching/mobile_capture_inventory.md.
- DATASETS.md, raw_iq/RAW_IQ_RELEASE_MANIFEST.json.

이노트는 기존코드·결과 감사와 재시도 설계이며 새로운측정값·복원성공보고가 아니다.
