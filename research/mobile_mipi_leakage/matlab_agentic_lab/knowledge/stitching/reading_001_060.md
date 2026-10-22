# O'Connell 원문 읽기: PDF 1–60쪽

- 작성일: 2026-10-22 (Asia/Seoul)
- 검토자 역할: stitching source identification / foundations reader
- 원문: Christian David O'Connell, *Exploiting quasiperiodic electromagnetic radiation using software-defined radio*, University of Cambridge, September 2018. 학위 승인·저장소 등록 연도와 표지 연도는 구분한다.
- 1차 출처: https://www.repository.cam.ac.uk/items/fd179846-3549-4bf1-9ba5-abb703ca44d8 ; DOI https://doi.org/10.17863/CAM.38085
- 검토한 로컬 PDF: C:/Users/leechanghoon/Desktop/연구/다중모니터 복원/TMDS/Exploiting quasiperiodic electromagnetic.pdf
- 동일성: 155쪽. 부모 작업자가 계산한 SHA256 aa81cb80e1e91e0ef928934302d222b087336edbb53af866b176181d6c1e4876. 이 노트의 검토자는 해시를 별도 재계산하지 않았다.
- 범위: **1–60쪽의 추출 본문을 페이지 순서대로 모두 읽었다.** 표지·선언·목차·빈 페이지 포함. 그림/수식 원페이지를 별도로 렌더링해 31, 41, 46, 49, 50, 51, 55, 57, 60쪽을 육안 대조했다. 나머지 페이지는 본문·수식 추출문·그림 설명 읽기까지이며 모든 그림을 확대 육안 검사했다고 주장하지 않는다.
- 권리: 저장소는 All rights reserved로 표시한다. 원문 PDF/추출문/렌더 이미지는 로컬 ignored cache에만 유지하고 이 독자 작성 노트만 공유한다.

## 페이지 및 절 커버리지

| PDF/인쇄 쪽 | 절 | 읽은 내용과 이번 연구와의 관계 |
|---|---|---|
| 1–4 | 표지, 선언, 요약, 감사 | TMDS HDMI/DVI가 주 실험 대상. 복소 평균→대역 합성→HMM의 전체 연구 연결 확인 |
| 5–8 | 목차 및 빈 페이지 | 2장 기반, 3장 탐지, 4장 PLL/평균, 5장 stitching/문자 회복, 6장 결론, 부록 TMDS/testcard 구조 |
| 9–18 | 약어, 표기, 기호 | fc, fb, fp, fh, fv, fs는 별개. displayed/full video mode 구분. 복소 위상·unwrap 정의 |
| 19–26 | 1장 전체 | 준주기성을 반복 관측으로 이용하는 문제 설정, 기존 문헌, 차폐와 연구 범위, 수신 중심 실험 |
| 27–30 | 2.1 | TMDS 변환/균형, bitpulse와 spectrum, 영상·blanking의 반복성과 fp=fb/10 |
| 30–32 | 2.2 | 차동 불균형, edge와 잔류 전자기장. Figure2.3은 시뮬레이션/개념도 |
| 32–34 | 2.3 | 원거리 log-periodic/근거리 H-field probe, preamp, SDR 구성 |
| 34–44 | 2.4 | analytic/IQ/DDC, magnitude/phase, 하드웨어, 단위 보정, LO/DC artifacts |
| 44–45 | 2.5 | full video timing과 유리수 resampling. 타이밍 오차의 누적과 raster shear |
| 45–51 | 2.6 | AM raster, 동적 범위 표시, HSV phase, gradient와 barcode 문제 |
| 51–52 | 2.7 | 같은 위치 두 관측의 합/차 SNR 추정; 강한 모델 가정 |
| 52–55 | 2.8 | 실제 거리 대신 on/off 기록 혼합으로 합성 감쇠; 독립된 실제 거리 대조 |
| 55–57 | 2.9 | VGA, Scan, Stitch 데이터셋의 장치/대역/Fs/안테나 구성 |
| 57–58 | 2.10 | 기반 장의 제한과 결과 정리 |
| 59–60 | 3장 시작 및 3.1 앞부분 | VESA/CEA 모드 138개, 79개 sweep, 실제와 명목 clock 차이. 61쪽 이후는 다른 검토자 담당 |

## 원문 실험 조건: stitching 이전에 알아야 할 사실

### 영상/복소 신호 모델

- 27–30쪽: TMDS는 색 채널의 8비트를 10비트 문자로 전송한다. 동일한 intensity라도 DC balance 상태 때문에 최대 9문자의 주기가 생길 수 있다. 3개 RGB data lane과 별도 pixel clock을 전제한다. 비트율 fb=10fp, fh=fp/wT, fv=fh/hT는 이 영상 모드 모델에 속한다.
- 29쪽: 화면 내용의 정지/느린 변화, 행의 비슷한 배경/글자, 그리고 blanking/control character의 반복을 사용한다. 일반적인 TMDS blanking 비율(수평 10–20%, 수직 약5%까지)은 모바일 DSI에서 그대로 적용할 입력값이 아니다.
- 27–28쪽 식2.1–2.2의 직사각형 bit pulse 모델은 sinc 제곱 envelope와 fb 정수배 null을 설명한다. 실제 전이 형상, 차동-공통모드 변환 및 RF 수신경로가 추가되므로 이를 모든 실측 RF의 절대 null이라고 쓰면 안 된다.
- 35–39쪽: IQ 진폭은 norm, 위상은 atan2(Q,I), 순시주파수는 이웃 복소 샘플의 위상차에서 얻는다. 위상 기준은 수신 LO다. 복소 baseband 대역폭 B는 Fs≥B로 담을 수 있다(37쪽). 원문 5장에서 Fs=2B를 택하는 것은 후속 알고리즘의 대역 배치에 따른 선택이지 IQ Nyquist법칙의 보편 조건이 아니다.
- 44–45쪽: raster 표본화가 1sample/pixel이 되도록 재표본화하더라도 원래 수집 대역의 정보량은 증가하지 않는다. 큰 타이밍 오차는 shear, 작은 오차는 frame 누적으로 drift한다. 모바일의 burst/command packet은 단순 pixel-clock resampling만으로 설명하지 못할 수 있다.

### 장치/측정 경로

| 원문 위치 | 조건 |
|---|---|
| 32–34쪽 | WA5VJB PCB log-periodic 400–1000MHz; Schwarzbeck VUSLP9111B 200–4000MHz; Langer XF-R400-1 H-field probe 30–6000MHz; PA303 preamp |
| 39–40쪽 | B200: 56MHz 명목 대역; X300+UBX160: 160MHz대역/200MHz 최대 sample clock. 원문의 특정 하드웨어 실험이며 USRP2940R의 사양 근거로 대체하지 않음 |
| 40쪽 식2.33–2.35 | 50ohm 연결된 signal generator −30dBm tone으로 ADC units→voltage 배율 보정. 주파수/수신 설정이 달라지면 배율도 달라져 각 구성마다 보정 |
| 41–44쪽 Fig2.9–2.11 | 원하는 tone이 LO/DC에 놓일 때 위상 궤적/진폭 왜곡 관찰. 원문은 1MHz LO offset을 사용해 tone을 보호. offset값은 모든 모바일 측정의 고정 권장값으로 해석하지 않음 |

Stitching 측정에는 실제 RF LO와 DSP shift를 별도 저장해야 한다. fc라고 기록한 값 하나로는 DC제거 notch나 LO spur 위치를 재현하지 못한다. AGC/gain 보정과 IQ correction 설정도 주파수별로 기록해야 한다. 하드웨어마다 내부 보정 동작이 다르므로 원문 B200/X300 결과만으로 2940R의 동작을 확정하지 않는다.

## Stitch 데이터셋: 두 실험을 구분

57쪽 2.9.3을 원페이지로 확인했다.

| 구분 | 개별 수신 대역 B | Fs | 겹침 | 개수/총 합성대역 | 기준 영역/화면 |
|---|---:|---:|---:|---|---|
| 저대역 이미지 비교 | 1MHz | 이 문단에서 별도 수치 명시 없음 | 0.5MHz | 9개 / 5MHz | 428.4MHz=17fp 부근; testcard |
| 고대역 문자/색 회복용 | 160MHz | 200MS/s | 80MHz | 3개 / 320MHz(기하학적 계산) | 756MHz=3fb 부근; testcard 색상 상자를 확대 |

- 공통 대상 full video mode는 800×525 total raster, fp25.2MHz, 표시 영역640×480@60Hz이다.
- 고대역 실험의 756MHz는 pixelclock의 3배가 아니라 **bit rate252MHz의3배**다.
- 두 실험의 50% overlap은 원문의 실제 설계값이다. 모바일의 최적 overlap이라는 실증 결과는 아니다.
- 공통 기록 경로: X300, HDMI connector 위 XF-R400-1 near-field probe, PA303.
- 원문 VGA 데이터셋(56쪽)은 RaspberryPi2ModelB+rev1.2→3m HDMI-DVI→Samsung710T, fc428MHz, B20016MHz/Fs16MHz 또는 X300고대역, WA5VJB원거리+30dB preamp. 이 조건을 Stitch 데이터셋 전부에 혼용하지 않는다.
- Scan 데이터셋(56–57쪽)은 50MHz대역/50MS/s, fc35,85,…,3935MHz의 79개 **비중첩** 기록으로 장치 탐지용이다. spectrum sweep과 coherent stitching은 데이터 요구 조건이 다르다.

## 사용자 기존 영상 해석에 연결되는 원문 근거

1. **gradation의 줄무늬**: 46–47쪽 Fig2.12는 TMDS uniform-color 구간과 gradient 구간의 복원 양상이 다름을 보여 준다. 색 channel별 coupling이 다르고 codeword가 intensity에 비선형적으로 변하면서 barcode 형태가 나타난다. 이는 원문 HDMI의 설명이다. 모바일 원/gradient에서 유사한 모양이 보인다는 이유로 TMDS나 LCD column driver로 확정할 수 없다. 가능한 후보를 좁히는 비교 근거로 사용한다.
2. **HSV**: 49–51쪽 Fig2.14–2.15는 H=측정 상대위상, V=진폭, S=표시 설정이다. amplitude 대비가 약한 글자가 phase 대비로 보이는 예가 있다. 실제 화면 RGB복원과는 다르다. carrier/clock offset을 제거하지 않으면 rainbow banding이 나온다. gradient는 phase를 추가해도 자동 복원되지 않는다.
3. **공간 고정**: 51쪽 Fig2.16에서 near-field probe를 조금 옮기자 red box 상대 밝기가 역전한다. 서로 다른 probe위치에서 찍은 reference를 그냥 빼면 역상이 남을 수 있다. stitching sweep 중 폰/케이블/프로브/손/주변 배치를 고정하는 근거다.
4. **MIPI 자체의 언급**: 47쪽 저자는 MIPI-DSI, VGA, FPD-Link/LVDS, CRT도 amplitude raster로 관측했다고 쓴다. 하지만 이 범위에는 MIPI의 장치별 파라미터나 MIPI stitching 성공 실험이 없다. 모바일 적용 가능성의 선행 관찰로만 인용한다.
5. **고정 간섭**: 60쪽 Fig3.1에 화면 fh31.5kHz/fv60Hz 주변 구조와 별도로 약150Hz간격의 background peak가 공존한다. 따라서 주기 peak가 있다고 원하는 화면 변조임이 바로 증명되지는 않는다.

## 해석 시 보존해야 할 가정과 원문 점검 사항

### SNR 추정 (51–52쪽)

- 식2.59–2.65는 두 관측에서 동일한 deterministic signal, 동일한 위치/전달경로, 정확한 정렬, 독립·동일 분산 Gaussian noise를 전제한다.
- 제시한 최종비율 μ/σ는 field ratio다. 일반적인 raster 전체가 평균0인 복소 변조일 때 E[v]를 사용하는 형태를 곧바로 전체신호 power SNR로 해석할 수 없다. 정렬오차/내용변화/고정clutter가 있으면 차분에 원하는신호가 남거나 noise가 상쇄된다.
- 모바일 결과에서 식을 그대로 적용하기 전에 averaging across repeat observations at matched samples, ROI, 분산의 복소 정의, signal/noise 분리 기준을 명시한다. 비교 두 장이 양쪽에서 같은 이미지를 반복한 것인지도 검증한다.

### 거리 합성 (52–55쪽)

- 식2.67은 device-on 기록을 α=d0/d로 줄이고 off 기록을 1−α로 섞는 empirical mixture다. 실제거리 측정도 별도로 수행하여 9m/2개벽과 0.25m 기반 합성의 raster를 비교한다(600frame평균).
- 이 방식은 실제 공간의 multipath/흡수/방향성 변화가 없다. 독립적 같은분산의 두 noise를 α와1−α로 더하면 noisevariance가 [α²+(1−α)²]σ²가 되므로 모든 α에서 background power가 정확히 보존되는 생성모델이 아니다. 모바일 noise/clutter benchmark에는 실제 on/off controls와 별도의 검증을 둔다.
- 원문 r=c/(2πf) 경계는 간단화한 source model이다. 실제 near/far-field 판정은 source와 안테나 크기 및 geometry도 고려해야 한다.

### 코드에 그대로 옮기지 않을 표현

- 35쪽 real signal Fourier transform을 even이라고 설명하지만 일반적으로는 Hermitian symmetry다. magnitude/power가 even인 것과 복소 spectrum 자체를 구분한다.
- 같은 쪽 Hilbert transform의 phase 설명은 ±90degree 형태를 의미한다. 전주파수 linear-phase filter로 오해하지 않는다.
- 49쪽 3σ clipping에서 원문 0.03%라는 수치는 Gaussian 3σ tail의 정확한 값이 아니다(양쪽 총약0.27%). 그림표시 clip일뿐 physicaldata를 잘라내는 처리에 직접 사용하지 않는다.
- 56쪽 short integer의 집합 표기에 음수가 빠져 있지만 IQ를 unsigned로 재해석하는 근거로 쓰면 안 된다. 실제 파일/수신 APIformat을 확인해야 한다. 현재 모바일 RIS는 기존 검증의 signed big-endianint16설정을 유지한다.

## 모바일 stitching 설계에 주는 구체적 요구

- HDMI의 full-video-mode template를 폰에 이식하지 말고 실제 MIPI burst/frame의 반복 구간을 선정한다.
- 같은 주파수에서 A-B-A 식 anchor를 재방문해 화면/기기의 변화를 측정한다. 원문의 quasi-periodicity를 실험 데이터로 검사하는 과정이다.
- 각 overlap에서 단순 peak값뿐 아니라 독립 구간의 복소 coherence, residual phase slope와 delay, 주파수별 amplitude ratio를 저장한다. 강한 panel/clock간섭이 alignment를 독점하는지 content-change control로 점검한다.
- 같은 위치/gain에서 실제 broadband capture를 얻을 수 있다면 이를 가상 subband로 잘라 stitch해서 보존오차를 먼저 확인한다. 이것은 sequential retune repeatability의 증명과는 별도의 구현 검증이다.
- phase-based 비교의 ADC format, LO/DSP주파수, gain/IQ/DCcorrection, 실현Fs, droppedsample, 타임스탬프를 metadata에 포함한다.

## 상태

이 노트는 원문 1–60쪽에 대한 완료된 독해 기록이다. 61–155쪽의 내용은 이 작성자에게 배정되지 않았으며 전체 원문 완료 선언은 다른 검토자 기록과 합쳐 판단해야 한다. 새 모바일 측정, 대역 stitching 실행, MATLAB reconstruction은 이 작업에서 수행하지 않았다.
