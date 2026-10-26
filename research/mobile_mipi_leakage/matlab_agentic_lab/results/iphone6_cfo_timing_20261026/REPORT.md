# iPhone 6: CFO·시간축 분리 보정과 100+160 MHz stitching

실행일: 2026-10-26. 원시 IQ로 실제 MATLAB 실행 완료. [결과 갤러리](gallery/index.html).

## 결론

- Signal Processing Toolbox와 Wavelet Toolbox 26.2를 R2026b에 설치했고 실제 resample/filtfilt/fsst/cwt 실행을 확인했다.
- AM row 반복 위치를 추적해 시간 정렬을 개선했다. 100 MHz AM train/assessment 상관은 0.368 → 0.726 → 0.835, 160 MHz는 0.301 → 0.730 → 0.734였다(고정 기준 → 훈련 affine 모델 → 프레임별 추적).
- CFO는 160 MHz 수신본에 +712.642796 Hz의 상대 오프셋 후보로 추정했다. 100 MHz가 기준이다. CFO와 시간축 보정은 별개의 추정량이며, ADC 절대 주파수를 교정했다고 주장하지 않는다.
- 실제 LR IIR stitching을 수행했으나 화면 payload의 광대역 coherent 합성 성공은 확인하지 못했다. 강한 spectral bin 주변을 제외하면 평가 coherence가 0.019–0.043 수준이다.
- 이번 대조에서는 8프레임 pilot mean의 overlap coherence가 frame72 단일 결과보다 낮았다. 보정된 frame72 단일 결과의 overlap coherence 0.282에 비해, 같은 모델의 8프레임 pilot-referenced mean은 0.122였다. 통계는 혼합 신호의 일치도이며 화면 정확도/SNR이 아니다.

## 1. 설치·실행 증거

설치 위치: C:/Program Files/MATLAB/R2026b. MPM2026.8, 종료 코드0. prodcontents.json에 Signal Processing Toolbox26.2와 Wavelet Toolbox26.2가 등록됐다.

- 최초 PowerShell 공식 input-template 요청은 HTTP Access Denied였다. 공식 웹 도구에서 같은 MathWorks URL의 전체497행을 확보해 checksum을 보존하고 요청 제품만 활성화했다.
- 기존 MATLAB 세션은 신규 native builtin 등록을 인식하지 못했다. 사용자 창을 유지하고 새 MATLAB batch 프로세스에서 연구를 실행했다.
- resample, Butterworth SOS/filtfilt, FSST/IFSST, CWT 실행 통과. FSST inverse relative error **1.878594e-15**.
- 두 실제 batch 분석 모두 종료 코드0. 기존 MATLAB MCP에서는 최종 비교 그림을 표시용으로 렌더링했다.
- [설치 실행 확인](install/verification.json), [첫 분석 로그](matlab_run.log), [추적 보정 로그](matlab_followup.log).

## 2. 원본과 분할

| 항목 | 값 / 상태 |
|---|---|
| 입력 | Downloads/black글_fc100MHz.rIs, black글_fc160MHz.rIs |
| 표본률 | 124,082,800 complex samples/s — 사용자 제공 |
| 수신 대역폭 | nominal120 MHz — 사용자 제공, 별도 교정 아님 |
| 디스크 표현 | headerless big-endian int16 interleaved I,Q, read-only |
| RF 부호 | 원래 I+jQ를 conjugate. 이후 RF=nominal fc+보고 fbb |
| DC | 각 대역 첫 훈련 프레임에서 고정 추정·제거 |
| 훈련 | zero-based frames0–7 |
| 평가 | frames72–79. 이번 고정 모델 fitting에는 사용하지 않음 |
| 추적 평가 | 같은72–79의 AM 이동량을 적용. frozen out-of-sample 평가와 구별 |
| prior 분석 격자 | 1100 columns ×1881 rows; native panel geometry 확정 아님 |
| 원본 화면 | 750×1334 사용자 PNG. 파형 생성·fitting 입력으로 사용하지 않음 |

기존 실험에서 같은 capture의 여러 부분을 이미 열람했다. 전혀 보지 않은 장치/화면에 대한 blind generalization 결과가 아니다. read offset·byte count·입력 identity는 timing/model.json에 보존했다.

## 3. row/HS 주기 추적

첫 프레임의 AM을1100×1881로 접고32-row 평균 프로파일을 만든다. 총58개 블록(1856rows)을 대응 위치의 후속 프레임과 상관해 fractional lag를 구한다. 훈련 자료에서 선택한 블록의 median lag와 훈련0–7의 robust slope로 period를 추정한다. 복소 위상은 시간축 fitting에 사용하지 않았다.

| 추정량 | 100 MHz | 160 MHz |
|---|---:|---:|
| frame period, native samples | 2069099.8844551395 | 2069099.914389405 |
| frame duration | 16.675154691 ms | 16.675154932 ms |
| 분석 row period | 8.865047682 µs | 8.865047811 µs |
| 분석 row rate | 112802.551754 Hz | 112802.550122 Hz |
| frame rate | 59.969458668 Hz | 59.969457800 Hz |
| 훈련 timing residual RMS | 0.0540 samples | 0.1182 samples |
| 고정 모델 평가 residual RMS | 2.2654 samples | 0.4703 samples |
| 추가 추적 후 재측정 RMS | 0.02897 raster samples | 0.04110 raster samples |

row 값은 prior1881-row 가설 아래 계산한 반복 후보다. D-PHY SoT/0xB8, packet header, ECC 또는 RGB888 payload를 디코딩해 HS라고 확인한 결과가 아니다. source/column driver나 clock/clutter가 프로파일을 지배할 수도 있다.

프레임별 추적은 residual[k]=observedAMlag[k]−k(Pfit−P0)를 추가하여 q(k,u)=origin+(k+u)Pfit+residual[k]로 샘플을 얻는다. 출력 raster에서 AM 프로파일을 다시 계산해 잔차를 확인했다. 같은 자료로 정렬한 뒤 재측정하므로 이 작은 잔차를 독립적인 복원 성능으로 해석하지 않는다.

## 4. CFO와 시간축의 분리

RF candidate는 훈련 스펙트럼에서만 선택했다. 서로1 MHz 이상 떨어진 후보3개를 복소 혼합하고32768-sample Hann block의 위상 기울기로 추적했다. 비교 RF 후보는 약155.824944,148.458065,133.759069 MHz이다.

| 후보 | nominal RF 차이 | AM 시간척도 반영 CFO | training 위상 RMS A/B |
|---|---:|---:|---:|
| 1 | 712.703 Hz | 712.643 Hz | 0.548 /0.573 rad |
| 2 | 713.712 Hz | 713.545 Hz | 0.292 /0.673 rad |
| 3 | 654.713 Hz | 654.334 Hz | 2.666 /2.529 rad |

세번째 후보는 위상/주파수 추적이 불안정하다. 3개 median **712.642796 Hz**를 고정 적용했고 후보 모두가 일치한다고 주장하지 않는다. 이전714 Hz는 matching search seed이며 별도 보정으로 중복 적용하지 않았다.

A=100MHz를 시간·RF 기준으로 잡고 r=Pfit,A/Pfit,B라 하면,

- δB=fbb,B−(fc,A+fbb,A−fc,B)r.
- 원본 absolute sample time n/Fs에서 xB,corr[n]=xB[n]exp(−j2πδB n/Fs).
- 그 다음 AM에서 얻은 q(k,u)에 따라 fractional resampling.
- 같은 physical pilot의 native reference는 νA=Fpilot−fc,A, νB=(Fpilot−fc,B)r.
- 새 격자에서 B→A translation D=(νA Pused,A−νB Pused,B)/Fs. 두 보정 적용 조건은 D=1000509.2814419755cycles.

단일 프레임은 exp(+j2πD(k+u)), pilot-referenced means는 이미 frame transport를 적용했으므로 exp(+j2πDu)만 사용한다. 임의 프레임마다 최적 위상을 새로 맞추지 않았다. 적응 시간 추적에서는 추가 샘플 이동의 ν·residual/Fs 위상도 함께 운반했다.

CFO는 순수 complex rotation이므로 같은 원본 sample에서 AM을 바꾸지 않는다. AM의 큰 변화는 timing alignment에서 나온다. interpolation 전 회전 때문에 보간 구현의 미세한 수치 차이는 생긴다. low-amplitude 위상은 유효한 physical phase로 간주하지 않으며 TF 위상 그림에는 amplitude gate를 표시했다.

## 5. Resampling과 IIR stitching

### 시간축

기존 검증된 sampleGuardedIqFft를 사용했다. 실제 주변 sample guard≥512, 4×FFT interpolation과6-point fractional interpolation으로 q(k,u)를 평가한다. 모든 조건은 동일한 interpolator를 사용하므로 'raw' 라벨은 fitted CFO/time correction 전의 고정-prior 격자이며, unmodified ADC byte stream이라는 뜻이 아니다. native-rate TF control을 별도로 보존했다.

정규화 frame grid는2^21 samples, **125.765070184 MS/s**이다. 표시/합성의 계산 격자이며 원래124.0828MS/s 계측률이 증가한 것은 아니다.

### 주파수 합성

- 이전에 지정한103–109MHz(중심106MHz)를 training delay/phase fit에 사용.
- 100/160MHz 전체 guarded overlap도 별도 평가.
- 정수 frequency bin 배치 + fractional translation 후 공통 synthesis grid로 FFT zero-padding.
- 실제 synthesis Fs **503.060280735 MS/s**에서 Butterworth4차 LP/HP SOS 설계.
- MATLAB **filtfilt(sos,g,...)** 실제 실행. forward/backward |H|²가 유효LR8응답.
- periodic guard256 samples. LP+HP effective amplitude unity error **2.5535e-15**.
- AM 후 anti-alias Fourier taper/truncation으로1100×1881 분석 격자로 복귀. 이는 resamplePeriodicAm이며 MATLAB resample과 구별한다.
- m[i] blanking mask 미사용: DSI blanking 위치를 확인하지 못함.
- delay는 한 프레임의 circular alignment. zero-padded finite-record linear-delay estimator와 동일하다고 주장하지 않으며 modulo-frame/comb ambiguity를 유지한다.

### 실제 결과

| 처리 | 평가 overlap coherence | 훈련 상위10 cross-power bin ±8 mask 후 | 평가 잔여 위상 |
|---|---:|---:|---:|
| 8-frame mean, 고정-prior | 0.00924 | 0.01090 | −1.101 rad |
| 8-frame mean, CFO only | 0.10605 | 0.02455 | −1.562 rad |
| 8-frame mean, timing only | 0.00437 | 0.01109 | −2.873 rad |
| 8-frame mean, CFO+timing | 0.12157 | 0.01857 | −0.599 rad |
| 8-frame mean, adaptive timing+fixed CFO | 0.26035 | 0.03005 | −3.062 rad |
| single frame, CFO+timing | 0.28213 | 0.04339 | +2.901 rad |

각 행은 훈련 자료에서 자신의 delay/phase를 추정한 뒤 평가에 고정한다. 마스크도 훈련 자료로만 정한다. 상위10bins의 neighborhood가 겹칠 수 있으므로 '10개의 독립 톤을 모두 제거했다'는 의미가 아니다.

CFO+timing single-frame delay10.933160µs, training phase−1.581914rad. 그러나 second-peak ratio0.947로 comb ambiguity가 남는다. 8-frame mean의 delay−77.645541µs, adaptive mean−130.927579µs 역시 경쟁 peak ratio≈0.996이다. 추정값을 실제 cable propagation delay로 해석하지 않는다.

8-frame mean과 single frame의 alignment 차이를 통제하려고 평균에서 정한 delay/phase를 single frame에 그대로 적용한 비교도 저장했다. CFO+timing single coherence는 이 조건에서도0.26874이며 평균0.12157보다 높다. 따라서 이 파일럿 기준 평균이 현재 자료에 유리하다는 증거가 없다. screenshot 복원도가 향상됐다고 주장하지 않는다.

## 6. TF와 위상 그림

training frame0와 평가 frame72를 각각 분석했다. frame72의 약row1000 부근131072-sample excerpt를 사용했다. 그 시점의 누적 query shift는100MHz−8.381samples(−67.541ns),160MHz−6.209samples(−50.043ns)다.

| 항목 | 설정 |
|---|---|
| 넓은 대역 STFT | Hann1024, window8.142µs, ENBW184.226kHz, FFTspacing61.409kHz |
| 좁은 RF 대역 | nominal106MHz; 모든 상태에서 같은 mixer/AA filter |
| Toolbox resample | p=1,q=16, Kaiser n32,beta8; transient guard 폐기 |
| 분석률 | 7.860316886 MS/s |
| STFT/FSST window | 256,32.569µs; ENBW46.057kHz; FFTspacing30.704kHz |
| CWT | complex analytic/anti-analytic 성분, Morse, COI 표시 |
| 검증 | AA amplitude stopband8.8023e-6, CWT 양쪽 대역 성공 |

32.569µs 창으로713Hz CFO를 주파수축에서 분해할 수 없다. squeezing으로 잃은 RF bandwidth나 원래 없던 해상도를 만들었다고 해석하지 않는다. 이 TF는 row-scale 순간 신호/강한 고정 주파수 구조를 살펴보는 것이고 CFO 수치는 별도 위상 추적으로 평가한다. STFT PSD와 FSST/CWT magnitude의 색상 단위는 다르다.

[후반 TF·위상](tf_heldout72/manifest.json), [single/mean 대조](single_frame_control/overview.json), [추적 보정](tracked/overview.json), [IIR 합성](stitch/overview.json).

## 7. 다음 연구에 주는 근거

1. AM 시간 정렬과 RF phase alignment는 별도 문제다. 전자는 개선됐지만 후자는 충분히 일치하지 않았다.
2. 100/160의 강한 공통 bin을 제거하면 coherence가 크게 내려가므로, 현재 기준 톤이 화면 payload를 대표하는지 추가 확인이 필요하다.
3. 일정한 CFO와 affine time scaling만으로는 위상 점프/프레임별 변화/여러 방사원의 상대 위상을 보정하지 못한다. 더 큰 frame count를 곧바로 평균하면 상쇄가 커질 수 있다.
4. 다음 실험은 known HS/header 구간과 clock/clutter 구간을 구별한 상태에서 phase transport를 검증해야 한다. 이번에 HS packet을 식별했다고 주장하지 않는다.

## 공식 문서와 코드

- [MathWorks MPM](https://www.mathworks.com/help/install/ug/mpminstall.html)
- [FSST](https://www.mathworks.com/help/signal/ref/fsst.html), [CWT](https://www.mathworks.com/help/wavelet/ref/cwt.html)
- [resample](https://www.mathworks.com/help/signal/ref/resample.html), [filtfilt](https://www.mathworks.com/help/signal/ref/filtfilt.html)

실행 entrypoints: verifySignalWaveletInstall, runIphoneCfoTiming26, runIphoneTrackedFollowup26. 원시파일은 수정하지 않았다. 모든 파형 처리는 로컬 MATLAB에서 수행했으며 cloud MATLAB 실행 결과가 아니다.
