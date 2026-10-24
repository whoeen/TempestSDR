# iPhone 6 stitching 재검증 — 2026-10-24

## 결론

**100–700 MHz 전체 및 100+160 MHz의 coherent 화면 복원 성공은 아직 입증되지 않았다.** 기존 출력은 정렬 후보를 적용한 합성 영상이다. 이번에는 실제 IIR 연산, 좁은 공통 대역, 명목 RF 이동량 보정, EM Eye 방식의 영상 결합, iPhone 6s fractional 주기 통제 실험을 실행했다.

- 실제 LR IIR와 같은 설계의 FFT 구현은 일치한다. **현재 실패의 원인을 “IIR을 쓰지 않아서”라고 설명할 수 없다.**
- 훈련 피크 기반 주파수 이동 보정은 한 좁은 대역의 후속 잔여 위상을 **1.1896 → 0.2108 rad**로 줄였다. 강한 피크를 제거한 coherence는 **0.0456**이므로 payload 정렬 성공은 아니다.
- 11대역에서 **112802.507 Hz** 반복 간격이 관측됐다. byte clock은 식별하지 못했다.
- 100/340/520 MHz 영상 결합은 시행했으나, 문자 구조 대비를 통제하면 배경 표준편차 개선은 **약0.10%**에 불과하다. 유의미한 복원도 향상을 주장하지 않는다.
- iPhone 6s는 정밀한 frame period를 유지하는 효과가 확인됐다. 같은32프레임에서 정수 반올림은 마지막 프레임에 **15.846 출력 열**의 이동을 만든다. cubic만이 원인인 것은 아니다.

[그림 모음](gallery/index.html) · [원문 EM Eye 감사](../../knowledge/stitching/iphone6_followup_20261024/EM_EYE_AUDIT.md) · [RF 수치 상세](../../knowledge/stitching/iphone6_followup_20261024/RF_CYCLE_RESULTS.md)

## 1. 입력과 평가 범위

| 항목 | 값·근거 |
|---|---|
| 단말 | 이번 sweep은 iPhone 6 |
| 입력 | 사용자 제공 black글_fc100,160,…,700MHz.rIs 11개 |
| 저장 Fs | 사용자 확인 124.0828 MS/s, complex IQ |
| 수신 대역 | 사용자 보고 nominal120 MHz; 실제 통과대역 교정값은 미확인 |
| 중심 이동 | 60 MHz; nominal overlap60 MHz |
| nominal 합집합 | 두 대역180 MHz, 전체720 MHz(40–760 MHz) |
| 셋업 | probe/clamp 고정, LNA/BPF 미사용 — 사용자 설명 |
| 원시 형식 | 기존 검증의 big-endian int16 I,Q interleaved, header0 가설 유지 |
| timing | 기존 training 기반 period/origin/DC를 유지; 새 평가 구간에서 재추정하지 않음 |

신규 파일은 별도 폴더에 저장했고 raw를 변경하지 않았다. 기존 train0–7/test16–23은 이미 관찰된 진단 구간이다. 후속64–71 역시 같은 정지화면·동일 취득의 후반부이며, 이번 분석 중 반복 확인했으므로 전역적으로 blind인 검증이라고 하지 않는다. 새 패턴에 대한 일반화는 검증하지 않았다.

MATLAB R2026b에서 실행했다. 현재 연결된 설치에서 확인된 제품은 MATLAB과 MATLAB Copilot이다. Signal Processing / Wavelet Toolbox의 fsst/wsst/filtfilt를 실행했다고 주장하지 않는다. FFT, filter, 자체 SOS와 원시 IQ 읽기는 실제 MATLAB 연산이다.

## 2. Chapter5의 어느 부분을 구현했는가?

| 질문 | 기존 구현 | 이번 확인 |
|---|---|---|
| upsampling | 실제 측정 guard를 둔4배 FFT 보간 후6점 Lagrange fractional sampling | 이 과정은 새로운 RF 정보를 만들지 않음 |
| 공통 grid | 2^21 samples/주기, 약125.765 MS/s | 입력124.0828 MS/s와 구별 |
| downsampling | AM 후 명시적 주파수영역 저역통과·계수 절단 | 출력 Nyquist의0.9까지 통과, Nyquist에서0; 단순 interpft 축소가 아님 |
| delay | 공통 Fourier-bin complex circular correlation 후 fractional peak 최적화 | Chapter5의 zero-padded linear correlation과 같은 구현이 아님 |
| phase offset | 지연 보정 후 복소 내적의 위상, training fit을 후속 구간에 고정 | 큰 peak 자체는 유효 정렬 증거가 아님 |
| m[i] | **미적용** | Chapter5 p114 Eq5.21의 blanking 위치 마스크. 실제 DSI active/blank/HS 대응을 확인하지 못함 |
| crossover/LR | W8의 실수 zero-phase 정상상태 응답을 FFT 계수에 곱함 | 실제 base-MATLAB SOS 정방향·역방향 IIR도 별도로 실행 |
| paper의 L/M FIR 재표본화 | 문자 그대로 재현하지 않음 | 기존은 주기 Fourier/guarded interpolation 구현. 차이를 기록 |

### m[i]는 두 문헌에서 다른 기호다

Chapter5 Eq5.21의 마스크는 총 raster 폭·높이와 active 크기로 정의된다:

    m[i] = 1 if (i mod w_T)>=w_D or (i mod (w_T*h_T))>=w_T*h_D; otherwise 0.

이는 첫 대역의 전체 화면 위치를 맞추기 위한 합성 blanking 마스크다. **EM Eye Eq2의 m[n]는 raw USRP IQ**다. MIPI packet 고정 bit열과도 별개다. 현재 재구성용1100×1881을 실제 panel total/active timing이라고 가정해 마스크를 만들지 않았다. DSI command/burst mode에서는 idle/HS/header/blanking 대응부터 확인해야 한다.

### 실제 IIR 결과

1. Butterworth4를 두 SOS로 구현하고 정방향·역방향으로 적용했다. 유효 크기응답은 W8이다.
2. 360 MS/s, crossover90 MHz 시험에서 LP+HP 합의 최대 오차1.67e−15, crossover에서 양쪽 amplitude0.5를 확인했다.
3. 실제 fc100 waveform 일부에서도 periodic padding128 samples 후 FFT 정상상태 응답과 상대 RMS 약4.05e−16으로 일치했다. 패딩 없는 유한 경계는 차이가 있었다.
4. 실제100+160 template pair 전체에 적용한 별도 비교도 완료했다. 새 SOS는 **실제 합성률503.060285 MS/s**에 맞춰 설계했다. 기존 FFT 가중치의 설계률 약359.998288 MS/s와 다르며, 최대 가중치 차이는0.0610이다.
5. 새 설계와 같은 Fs의 FFT 응답을 비교하면 train/test 상대 RMS는 각각 **8.813e−16 / 8.809e−16**이다.

이것은 자체 filter() 양방향 처리이며 MATLAB filtfilt의 초기조건·끝점 확장 정책을 복제한 것이 아니다. 주기 패딩의 수렴은 실제 기록의 frame seam이 물리적으로 닫혔음을 증명하지 않는다.

[실제 pair IIR 수치](pair_100_160_literal_iir/audit.json) · [비교 그림](pair_100_160_literal_iir/comparison_shared_scale.png) · [경계 검증](lr_finite_iir/audit.json)

## 3. 100+160 MHz의 delay·phase·주파수 이동 결과

### 기존 넓은 overlap

| IQ 가정 | 추정 delay | phase | training coherence | 기존 test coherence |
|---|---:|---:|---:|---:|
| I+jQ | −201.8344 µs | 3.0750 rad |0.006375|0.001370|
| I−jQ |1850.4218 µs|−0.9132 rad|0.014442|0.002130|

이는 주기 상관의 수학적 후보이며 실제 전파 지연이라고 해석하지 않는다. 해당 추정값을 넣어 생성한 화면을 성공적인 광대역 복원으로 부르면 안 된다.

### 새 좁은 대역 진단

nominal 공통 RF103–157 MHz를6 MHz 창9개로 나누고, frame0에서 추정하여 frame64에 적용했다. 양쪽 IQ 부호, 강한 피크 주변 제거 전후를 비교했다. 전체 FFT보다 작은 공통 계수 grid로 계산했지만 지연의 ambiguity는 여전히 frame period에 대해 modulo이다.

I−jQ/106 MHz 창이 가장 높은 후속 coherence를 보였다. 처음 출력은 로컬 frame coordinate만 사용했으므로, 이후 전체 시각의 주파수 이동 exp(j2π frac·(frameIndex+u))를 반영해 다시 실행했다. 이전 출력은 LOCAL_FRAME_CONVENTION.md와 함께 보존했다.

| 단계 / 106 MHz 창 | frame64 coherence | 잔여 phase | 설명 |
|---|---:|---:|---|
| 명목 RF 이동, global frame phase 포함 |0.292516|1.189636 rad|train delay10.931485 µs|
| 훈련 공통 피크로 RF 이동 보정 |0.292619|0.210769 rad|delay10.932877 µs, phase−1.340230 rad|
| 같은 보정, training 상위10피크±8bin 제거 |0.045630|0.256964 rad|효과가 강한 반복 성분에 의존 |

훈련100/160 공통 피크30쌍의 RF_B−RF_A 중앙값은 **+714.039 Hz**, MAD2.546 Hz다. 서로 다른 period를 반영한 공통-grid 이동량은 **1000497.381376 cycles**, 명목값 대비 **−11.939933 cycles = −716.031 Hz/T_A 기준**이다. 이 보정 후 추가 정수 branch는0으로 선택됐다.

주파수·위상 정렬의 일부는 개선됐지만 coherence나 문자 복원은 개선되지 않았다. 주파수 축 보정값을 저장 Fs 자체의 오차라고 단정하지 않는다. LO와 sampling clock 교정 오차, source drift 등의 분리가 필요하다.

[새 명목 진단](narrow_overlap_100_160_global_phase/overview.json) · [훈련 RF 보정 후](narrow_overlap_100_160_calibrated/overview.json)

### 120 MHz가 넓어서 algorithm이 무효인가?

절대 대역폭120 MHz 자체가 무효 사유는 아니다. 공통 대역에 동일한 재현 가능한 성분이 있고 복소 전달함수·주파수·시간축이 맞아야 한다. 넓은 대역에서는 여러 방사원, 주파수별 이득/군지연, lane별 결합 차이가 하나의 delay+phase 모델에 들어오므로 그 가정이 더 쉽게 깨질 수 있다. 위치를 clamp로 고정해도 별도 취득의 LO phase와 송신 timing이 자동으로 고정되지는 않는다.

비연속 대역의 coherent RF 합성은 공통 시간·위상 기준이나 검증된 protocol reference가 추가로 필요하다. 빈 주파수 대역은 미관측 상태로 남는다. 영상 영역 결합은 그와 달리 RF 위상 연결 없이도 시험할 수 있다.

## 4. 실제로 측정한 cycles와 RGB888 lane 모델

### 측정된 반복 간격

11개 band의 training/후속각2^22 samples에서 Welch PSD와 긴 FFT 피크를 계산했다.

- 최대 밀도의 근접 피크 간격군: **112802.507 Hz**, training368차분/11대역.
- 대응 후속337차분 중앙값: **112802.609 Hz**.
- 주기 약 **8.86505 µs**, 기존 Fs/1100=112802.545 Hz와 일치.
- 이는 row/packet 반복 후보다. 실제1native행이나750pixel payload라고 확정하지 않았다.
- 분석 frame 후보는2069100 samples, **16.675156 ms / 59.969455 Hz**.
- 56.4 kHz 부근도 일부 보이지만 지지 범위가 작다.
- 대역 간 동일 RF 피크 대응은 I−jQ에서201쌍, I+jQ에서8쌍이다. RF polarity 가설을 I−jQ 쪽으로 지지한다.
- I−jQ의 **14.812010 MHz** comb 후보13지점은 2.115990 MHz 후보와 대부분 같은 지점을 설명한다. 다른44.548861/11.137215/8.909772 MHz 후보도 동일 지점의 harmonic-index alias를 가진다. 이 중 하나를 byte clock이라고 선택할 근거가 부족하다.

각 band의 상위64피크까지만 보존되어 전수 스펙트럼 분석이 아니다. 적합 오차·표준오차는 선택한 지점과 모델에 조건부이며 장비 교정 불확도를 포함하지 않는다. 60.03 MHz seed가 top12에 없다는 사실은 그 가설의 기각을 뜻하지 않는다.

### iPhone6 lane 수

[공개 회로도 mirror PDF p20](https://w.electrodragon.com/w/images/7/74/IPhone_6_SCH.pdf)은 N61 display DATA0/1/2+CLK를 보여 **3 data lanes**를 지지한다. Apple 공식 배포·revision 및 실제 DUT 일치는 독립 확인하지 못했으므로 하드웨어 우선 가설이다. Clock pair까지 합쳐4 differential pairs인 것과4 data lanes인 것은 다르다.

RGB888, N lanes에서:

    R_lane = f_b = 8*f_byte = 2*f_DDR
    payload pixel throughput = N*f_byte/3
    lane별 component 배치 반복 byte ticks = 3/gcd(3,N)

| 가정 | lane별 배치 주기 | 배치 반복 주파수 |
|---|---:|---:|
|3 data lanes|8 UI|f_byte|
|4 data lanes|24 UI|f_byte/3|

배치의 반복과 데이터 값의 반복은 다르다. 현재 흑백 화면은 R=G=B와00/FF가 많아 lane 모델 식별력이 낮다.

750×1334를60 Hz로 전부 갱신하고 RGB888·압축 없음·3lane이면, payload duty100%에서도:

- f_byte ≥ **60.03 MHz**
- f_DDR ≥ **240.12 MHz**
- R_lane ≥ **480.24 Mbit/s**

이는 실제 측정값이 아닌 조건부 하한이다. Packet/HS overhead와 idle 시간이 있으면 더 높은 rate가 필요하다. Command-mode update율과 panel refresh율이 다르면 전제를 다시 계산해야 한다.

### Packet reference 후보

D-PHY HS sync0xB8, 조건부 RGB888 video header, DCS write header, 활성화된 EoTp 등을 후보로 삼을 수 있다. 예를 들어 VC0·한 packet에750pixels라는 조건에서 video header는3E CA 08 09, DCS command1byte 포함 header는39 CB 08 12다. **실제 decode값이 아니다.** SoT는 lane마다 병렬이고 매 packet마다 반드시 발생하지 않는다. Header ECC는 payload 복원 ECC가 아니다.

[프로토콜·속도·packet 상세](../../knowledge/stitching/iphone6_followup_20261024/MIPI_CYCLE_HYPOTHESES.md)

## 5. EM Eye distortion-guided combination 실행 결과

EM Eye §V Eq2–3은 각 대역의 AM 영상, grayscale 극성 보정 등을 거쳐 영상을 합친다. RAW10 CSI-2 예시의 B2/B6 bit-slot 주기를 RGB888 DSI에 그대로 옮길 수 없다. 영상 결합을 실행하기 위한 수학적 필수조건이 byte cycle의 사전 식별은 아니다. Cycle 모델은 좋은 대역과 왜곡 원인을 찾는 데 도움이 된다.

이번 baseline:

- 11개 band를 각각 training-only 이미지 translation·grayscale polarity·scale로 정합.
- 후보100/340/520 MHz에서 best single, equal mean, 제약 결합 비교.
- 알려진 실험 패턴의 배경/문자영역을 training100 MHz 영상에서 선택. 원본 screenshot pixels와 neural network는 입력에 사용하지 않음.
- w≥0, Σw=1, ridge 및 training anchor 문자-gradient projection≥0.8.
- 논문 Eq3의 문자 그대로 복제는 아니며, 전체 contrast를 줄여버리는 해를 제한한 변형이다.
- 선택 가중치 **[0.8, 0, 0.2]**, best single100 MHz.
- 다른 대역의 영상 정합 상관도가 낮다. Training feature correlation은340 MHz0.1554,520 MHz0.0582다.

단순 ROI 표준편차는 줄지만 구조도 함께 약해진다. Training 구조 대비를 기준으로 고정 gain을 맞춘 다음 후속64–71을 비교하면:

| 방법 | 배경 ROI 표준편차 |
|---|---:|
|100 MHz 단일|0.491594|
|동일 가중 평균|0.620484|
|제약 결합|0.491087|

제약 결합의 감소는 약0.103%이며, 문자 정확도 개선은 확인하지 못했다. 따라서 현재 자료에서 nonadjacent multiband 결합의 실질적 이득을 주장하지 않는다.

[결합 수치](image_fusion/overview.json) · [대비 통제](image_fusion/contrast_matched_control/metrics.json) · [문자 비교](image_fusion/contrast_matched_control/contrast_matched_text.png)

## 6. iPhone6s가 선명했던 이유: 같은32프레임 실험

이전6s 취득은 fc311 MHz, Fs55.054870 MS/s, nominal BW20 MHz로 이번 iPhone6 sweep과 다른 자료다.

- 정밀 line period: **488.884547974 samples**
- 정밀 frame period: **917636.666798 samples**
- 출력750열에 대한 비율: **0.651846 input samples/output column**. 원본 물리pixel당 샘플 수라는 뜻이 아니다.
- 모든 arm에서 line period와 raster mapping을 동일하게 유지했다.
- 비교: precise frame period / saved per-frame alignment / rounded frame period × nearest/cubic.

frame period를917637로 반올림하면 31frame 간격 뒤10.329262 input samples=15.846168 output columns 이동한다. 비교 그림에서 숫자·작은 글자가 번진다. Fractional period를 유지한 nearest도 선명하다. **따라서 정밀한 시간축은 중요하지만 cubic 보간만의 효과로 설명할 수 없다.**

Saved per-frame residual alignment는 이번 같은 crop의 비교에서 추가 이득을 입증하지 못했다. Cubic은 평균 진폭도 약13.8% 낮춰 nearest와의 차이에 filter response가 포함된다. Rounded cubic의 odd/even 상관도가 오히려 높아지는 사례가 있으므로 이 상관도를 fidelity라고 사용하지 않는다.

별도로 기존 complex averaging에서 global phase correction은32frame의 상쇄를 크게 줄였다. 이 결과는 AM frame-period 통제와 구별하며, power ratio를 SNR 향상으로 부르지 않는다.

[직접 비교 수치](iphone6s_frame_period_P032/metrics.json) · [글자 확대](iphone6s_frame_period_P032/period_comparison_text.png)

## 7. Synchrosqueezing/TF 분석을 resampling에 연결하는 방법

[MATLAB fsst](https://www.mathworks.com/help/signal/ref/fsst.html)는 STFT 에너지를 순간주파수 축에 재배치하는 도구다. [wsst](https://www.mathworks.com/help/wavelet/ref/wsst.html)는 별도 wavelet 방식이다. 그림이 선명해지는 것과 RF 대역폭·pixel 정보가 증가하는 것은 다르다.

유효한 다음 연결은 다음과 같다:

1. 반복 성분과 정보 sideband를 구분해 선택 대역을 DDC하고 antialias filter 후 필요한 rate로 축소한다.
2. 분리된 성분의 ridge/phase를 추적해 잔여 CFO·위상잡음을 보정한다. 여러 성분이 섞인 전체 IQ의 angle을 한 carrier phase로 취급하지 않는다.
3. 별도로 HS/packet/row event의 도착시각을 추적하여 sample-clock drift/time warp를 추정한다. 단일 RF ridge의 주파수 이동만으로 raster resampling을 결정하지 않는다.
4. 복소 fractional resampling·정렬을 적용하고, 추정에 사용하지 않은 payload/time 구간에서 검증한다.
5. 동일한 frame 수와 동일한 표시 scale로 AM/PM 정보 보존과 문자 구조를 비교한다.

이번 연결 세션에는 관련 Toolbox가 없어 fsst/wsst는 실행하지 못했다. 기존 STFT 및 이번 PSD·주기 분석은 수행했지만 이를 synchrosqueezing 실행 결과라고 표시하지 않는다. m[i]를 대체할 DSI-specific HS/blanking mask와 실제 f_byte/f_DDR의 확정도 아직 남아 있다.

## 8. 재현·한계 기록

모든 신규 MATLAB entrypoint는 lab root의 audit*.m 및 renderIphone6sPeriodComparison.m이다. 결과 폴더가 있으면 덮어쓰지 않는다. 원시 IQ 경로는 기존 resolver를 사용한다. IQ와 PDF 전문은 일반 Git blob에 넣지 않는다.

- 수치검증: broadband synthetic delay/phase 부호, LR LP+HP·crossover·pole stability, 실제 waveform/실제 pair IIR↔FFT,6s 저장 결과 replay.
- 정적분석: 새 entrypoint에 syntax error 없음. RF audit와 fusion의 사용되지 않은 할당 warning은 기록.
- IIR 동등성은 RF source identity나 screen fidelity를 검증하지 않는다.
- 모든 phase는 명시된 상대 기준이며 absolute 방사 phase나 column-driver identity가 아니다.
- 'clutter'는 강한 반복 성분을 가리키는 작업상 표현이다. 회로 발생원을 특정한 것은 아니다.
- full sweep을 더 넓게 합치는 것보다 먼저 **음의 RF 축·주파수 이동 교정·DSI event timing·정보가 있는 overlap**을 확보해야 한다.

### 원문 위치

- 사용자 제공 Chapter5, 논문쪽109–123: resampling p112, delay/phase/mask p113–114, crossover 및 W8 관련 절. 구현별 차이는 위 표 참조.
- 사용자 제공 2024-552-paper.pdf: EM Eye, NDSS2024, DOI10.14722/ndss.2024.24552. 특히 pp3–7 §III–V, Fig5/7, Eq1–3, pp15–16 RAW10 및 Fig18. 전체 읽기 범위와 미독 범위는 감사 노트에 기록했다.
