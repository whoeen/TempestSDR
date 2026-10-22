# TEMPEST 문헌 연구 노트 — 2026-10-22, 학습 사이클 01

목적은 LG X2, iPhone 6s, Galaxy S4 LTE의 **사용자 보유 측정자료**를 해석할 근거를 쌓는 것이다. 이번 사이클은 문헌 조사이며 새로운 DUT 측정이나 화면 복원 성공을 주장하지 않는다. `sources.jsonl`에 12개 출처, `claims.jsonl`에 출처 또는 추론을 명시한 26개 항목, `reading_log.jsonl`에 실제 읽은 페이지와 미완료 범위를 기록했다. 논문 7개를 공개 저자/학회/대학 접근 경로에서 로컬 PDF로 받았으며, 기존 TempestSDR 학위논문 1개는 원래 경로에서 읽었다. 추가 1개는 웹 PDF 텍스트, 3개는 초록/발췌/데이터 페이지 수준이다. **전체 분야나 모든 원문을 학습 완료한 상태는 아니다.**

## 이번에 바뀐 판단

1. 화면의 주기성과 비트 전송률, 수신 중심주파수를 구별해야 한다. `fc`가 RF receiver 중심이라는 사실만으로 방사원이 그 주파수의 단일 AM carrier를 송신한다고 볼 수 없다. [Kuhn](https://www.cl.cam.ac.uk/~mgk25/pet2004-fpd.pdf) p.4와 [EM Eye](https://www.ndss-symposium.org/wp-content/uploads/2024-552-paper.pdf) p.5는 디지털 전송의 넓은 스펙트럼 일부를 수신한다는 관점을 명시한다. 선택 대역의 complex envelope를 작은 AM/PM로 근사하는 것은 **검증할 모델**이다.
2. [Erdeljan–Kuhn 2024](https://www.cl.cam.ac.uk/~mgk25/emc2024-coherent-demodulation.pdf)의 핵심은 timing과 phase를 함께 맞춘 **복소 평균**이다. HSV는 그 복소 신호를 보여주는 방식이다. 원본 화면 RGB를 복원했다는 뜻이 아니다. PDF 첫 페이지에 식(11)의 2024-09-18 정정이 표시되어 있어 코드에는 정정판을 사용해야 한다.
3. 세로선과 원형 UI 내부 contour를 하나의 LCD-driver 원인으로 묶을 근거는 아직 없다. 잔류 주파수에 따른 hue ramp, 디지털 값에서 방사로의 비단조 대응, 수신 필터의 ringing, clock/data/driver의 혼합을 먼저 구별해야 한다. EMI의 물리적 발생 위치는 안테나/프로브 위치 및 제어 실험으로 확인해야 한다.
4. EM Eye는 **카메라 sensor→ISP, CSI-2** 연구다. 화면 host→display DSI를 입증한 것으로 인용하면 안 된다. [Screen Gleaning](https://www.ndss-symposium.org/wp-content/uploads/ndss2021_4B-2_23021_paper.pdf)은 직접적인 스마트폰 display 문헌이지만, 주 성과는 알려진 숫자 class를 구분하는 것이다.

## 문헌 비교

아래의 수치는 각 논문 실험 조건이다. 사용자 RIS의 설정값으로 옮겨 적지 않는다. PDF 페이지는 파일상 1부터 센다.

| 출처 | 전송/실제 대상 | 관측·대역 | 복조·동기·평균 | 평가·데이터와 적용 제한 |
|---|---|---|---|---|
| Kuhn 2004/2005, pp.4–6,12–14 | LVDS laptop 및 DVI desktop | laptop 예: fc350 MHz, IF50 MHz, AM출력250 MS/s | analog AM, 정밀 raster, 16frames | 3m 문자 복원. 색→방사 진폭은 비단조. 현대 DSI 직접 실증 아님 |
| Marinov 2014, PDF34/57/61 | TempestSDR raster display | SDR frontend별 | 초기 IQ magnitude, resampling, IIR frame smoothing | 후단에서 위상을 다시 얻을 수 없음. 현재 fork 코드는 별도 검토 필요 |
| Erdeljan–Kuhn 2024, pp.1–6 | HDMI→DVI | fc425 MHz, BW40 MHz,64 MS/s | complex autocorrelation lag+phase, fractional resampling,30frames, k3 | fp25.2 MHz,5m. 6D pixel PCA. [저자 데이터](https://www.cl.cam.ac.uk/research/security/datasets/hdmi/) |
| Erdeljan–Kuhn 2025, pp.1–6 | HDMI TMDS | fc325–450 MHz,25 MHz steps,6bands,각 BW40 MHz | 각 band complex average30frames, overlapping-band 정렬, symbol clustering | 12m. TMDS cycle 병합. 화면이 유지되는 band별 측정 필요 |
| EM Eye 2024, pp.3–8,11,17 | CSI-2 등 camera sensor link | 실험8 MS/s; 장치별 중심주파수 상이 | AM/raster/frame average, band1–3개 조합, pix2pix | SSIM/face/caption. [프로젝트](https://emeyeattack.github.io/Website/). 생성 색은 semantic 추론 |
| Deep-TEMPEST 2024, pp.3–9 | HDMI TMDS RGB24 |1600×900@60,fc324 MHz; 읽은 구간에 실제 설정 sample rate 수치 명확하지 않음 | gr-tempest로 complex raster, I/Q를 DRUNet 입력 |3491pairs(1302real), CER/SSIM/PSNR. [코드·데이터](https://github.com/emidan19/deep-tempest). DSI 학습모델 아님 |
| Screen Gleaning 2021, pp.5–8 | iPhone6s/6, Honor6X 등 smartphone display | 수집 BW12.5 MHz,25 MS/s. iPhone6s295 MHz/iPhone6 105 MHz | near-field(<1cm), TempestSDR emage, LeNet 숫자 분류 | digit89.8%,6자리 전체50.5%. [코드](https://github.com/cescalab/screen_gleaning). 일반 화면 복원율 아님 |
| Trip et al.2019, pp.2–5 | LG K4(2016), Samsung J5(2015) |113/31 MHz 복원; 탐색 RBW2 MHz | FSET22/AM524, 화면 on/off 비교,1m chamber |16.65/16.7ms frame. 공개 IQ 확인 못함. [원문](https://eudl.eu/pdf/10.1007/978-3-030-23976-3_9) 직접 다운로드403 |
| USBee2016, pp.1,3–4 | USB2 software-created covert emission | USB480 Mb/s, 관찰240–480 MHz 언급 | 의도적으로 B-FSK 생성/FFT 검출 |20–80 bytes/s. [원문](https://arxiv.org/abs/1608.08397). 수동 화면복원과 문제 설정이 다름 |
| He–Kassam2008, 발췌만 | square-QAM blind equalizer | RF display 실험 아님 | GSA/MMA/CMA에 constellation error | [대학 원문 경로](https://repository.upenn.edu/bitstreams/43d2a5a2-9e1c-48b5-8ffc-e464fe44621c/download)403. 아직 전체 수렴 증명 미검토 |
| De Meulemeester2020, 초록만 | HDMI/DVI/LVDS |10m VDU 사례 | AM 및 FM 영상복원 | [기관 기록](https://researchportal.rma.ac.be/en/publications/differential-signaling-compromises-video-information-security-thr/). 본문 미확보, 상세물리식 미검증 |
| Erdeljan–Kuhn2026, 초록·데이터페이지만 | scrambled DisplayPort | 수신 대역이 bit rate보다 좁은 경우 연구 | 상세본문 아직 미검토 | [5m/8m 데이터와 transmitter-off 참조](https://www.cl.cam.ac.uk/research/security/datasets/displayport/), 본문 접근 timeout |

## 재현에 직접 필요한 교정 사항

### 1. 2024 HDMI 알고리즘의 정확한 역할

`fp=wt*ht*fv`, `fs=k*fp`, `h=round(fc/fp)`를 전제로 원래 복소 IQ의 시간축을 보간하고 `fc-h*fp`를 보정한다. 정정된 식(11)은 다음과 같다.

```text
fp_new = fp * (k*wt*ht/dhat + k*angle(Rss[dhat])/(2*pi*h*dhat))
```

분모의 `h`와 두 번째 항의 `k`를 빠뜨리면 안 된다. `Rss[d]=E{s[n]conj(s[n+d])}`라는 논문의 conjugation convention도 지킨다. 다른 autocorrelation convention을 쓰면 phase 부호를 재유도한다. 총 width/height에 blanking이 포함된다. `h=0`에는 이 식을 그대로 쓸 수 없다. DSI burst/packet에서는 `wt*ht*fv`와 wire의 byte/bit timing 관계부터 프로토콜 역할이 확인해야 한다. 이 식 자체가 DSI clock 식은 아니다.

논문의 HSV rainbow 주기는 `fs/abs(fc-h*fp)` samples다. 사용자 자료에서 residual phase slope를 실제로 추정하고 그 주기로 예측되는 줄무늬와 비교하면 frequency-offset 가설을 검증할 수 있다. resampling과 주파수 보정은 다른 조작이다. k를 늘리는 보간만으로 저장 대역 밖의 정보를 만들 수 없다.

### 2. EM Eye의 오자와 gradient

p.4의 DDR 설명 문장은 clock가 bit frequency의 두 배라고 하지만, 함께 제시한 clock204 MHz/byte51 MHz는 `fb=2*fclk=408 Mb/s`, `fbyte=fb/8=51 MHz`와 일치한다. PDF를 렌더해 문구를 확인했다. 데이터베이스 `T014`는 이 내부 모순을 보존하며 프로토콜 사양과 대조하도록 한다.

p.5–6의 contour 설명은 bit significance가 사라진 band-limited 영상값이다. 완만한 실제 밝기 ramp가 디지털 비트 변화로 바뀌고, 선택대역에서 비단조 amplitude/phase가 되면서 등고선처럼 보일 수 있다. **이는 사용자 이미지에 대한 후보 설명**이다. 해당 DUT의 반복 측정으로 원본 gray ramp와 IQ 분포를 대응시켜야 한다. 논문 p.17은 색 생성이 semantic 추론이라고 명시하므로, 생성 후 그림을 RF로 증명한 색 복원으로 평가하지 않는다.

### 3. 숫자 해석 오류 방지

- Screen Gleaning의 분석 span50 MHz/RBW25 kHz와 실제 capture BW12.5 MHz/sample25 MS/s는 서로 다른 항목이다. 원본 iPhone6s 연구이므로 사용자 파일과 비교할 가치가 크다.
- Deep-TEMPEST의 실측 CER 비교는 raw92.2→complex35.3%, magnitude-only43.6%, fine-tuning29.8%다. 이는 논문 데이터셋의 OCR 결과다. DSI 성공률, 실제 bit error rate, RF SNR 향상값으로 바꾸지 않는다.
- Trip2019의 SNR1.9/5.4 dB는 IF peak voltage비 계산이다. 신호+잡음의 최대치와 noise 최대치를 나눈 값에서 calibrated signal power SNR을 추론하지 않는다. 문중 Samsung J4/J5 불일치도 남겨 둔다.

## 사용자 세로선 가설을 구별하는 다음 실험

아래는 문헌을 바탕으로 제안하는 **우리의 연구설계**이며 결과가 아니다.

| 가설 | 반드시 남길 관측 | 다른 가설과 구별할 변화 |
|---|---|---|
| 잔류 CFO 또는 sample-clock mismatch | frame별 complex correlation angle, phase slope, fractional delay | timing/CFO 보정량과 stripe 주기가 예측식대로 함께 변함 |
| 직렬화된 pixel/byte 값의 비단조 mapping | known grayscale ramp, 원형 단색, level별 IQ cluster, RF대역 | 원형경계 위치보다 디지털 gray level에 contour가 고정되는지 |
| clock/data 혼합 | probe위치와 방향별 complex 평균/위상/증폭 고정 | 부호·위상이 공간적으로 변하고 화면내용과 독립인 성분이 존재하는지 |
| 수신필터 ringing/해상도 손실 | 같은 IQ의 여러 분석대역, filter impulse response | edge 옆 sidelobe 간격이 필터대역에 따라 변하는지 |
| panel driver/power/inversion 기원 | near-field map, 화면pattern,밝기,refresh,프레임phase | panel/FPC 위치 및 구동주기 변화와 함께 따라가는지 |

driver/panel과 MIPI clock를 모두 한 장의 `low-rank + sparse` 분해만으로 분리했다고 주장하지 않는다. low rank 여부는 이미지 배열, frame-stack, lag-Hankel 등 **어떤 행렬을 만들었는지**에 따라 다르다. 고정 세로선은 오히려 매우 낮은 rank일 수 있다. 목표 신호도 간섭도 frame-coherent이면 averaging이 둘 다 강화한다. 따라서 독립 frame/시간블록으로 선택 규칙을 검증하고 목표 대역의 periodicity·coherence를 함께 기록해야 한다.

## 데이터베이스 운영 규칙

- 새 문헌은 먼저 `sources.jsonl`에 안정된 `source_id`, DOI/URL, 접근일, 실제 대상, 공개 여부, 읽기 상태를 기록한다.
- 수치는 `claims.jsonl`에 값/단위, 수집조건, 페이지, 표/식 번호, `source_result`와 `research_inference`를 구분해 추가한다.
- 읽지 못한 페이지를 읽었다고 표시하지 않는다. 논문 초록 수치를 검증된 실험 재현 결과로 올리지 않는다.
- 논문의 원문/페이지 텍스트/렌더는 `.gitignore`의 `cache/` 아래 로컬 보관한다. 메타데이터와 독자적 노트만 저장소 공유 대상으로 둔다. 공개 다운로드 가능 여부와 재배포 권리는 다르다. `cache_manifest.json`에 SHA-256/바이트/페이지 수를 기록한다.
- 다음 우선순위: DisplayPort2026 본문/알고리즘, De Meulemeester2020 원문, He–Kassam2008 전체 수렴 분석, O'Connell2019 Ch.4 tracking, Screen Gleaning의 나머지 robustness/한계, 실제 사용자 RIS에 대한 counterfactual tests.

## 누락과 한계

Galaxy A7(2018)의 **실제 DSI timing/register/lane rate**는 이 문헌 묶음으로 확정할 수 없다. 그 값은 프로토콜 담당이 공식 문서/driver 소스/측정으로 확인해야 한다. 이번 비교 문헌의 fv 또는 fc를 A7 값으로 대입하지 않는다. 또한 논문에서 가정한 noise와 사용자의 동기 간섭은 다를 수 있어 RF chain/신호처리 담당의 실제 PSD·overload·phase stability 검증이 우선이다.
