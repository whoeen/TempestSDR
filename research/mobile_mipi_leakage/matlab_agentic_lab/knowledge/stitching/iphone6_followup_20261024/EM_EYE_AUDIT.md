# EM Eye 원문 감사와 iPhone 6 다중 대역 영상 결합 설계

작성일: 2026-10-24. 역할: 원문·수식 검토. MATLAB 실행은 하지 않았다. 아래에서 **원문 명시**, **수식 감사**, **본 연구 제안/가설**을 구분한다.

## 1. 출처와 실제 읽은 범위

- 논문: Yan Long, Qinhong Jiang, Chen Yan, Tobias Alam, Xiaoyu Ji, Wenyuan Xu, Kevin Fu, **EM Eye: Characterizing Electromagnetic Side-channel Eavesdropping on Embedded Cameras**, NDSS Symposium 2024, San Diego, 26 February–1 March 2024.
- 논문에 인쇄된 DOI: [10.14722/ndss.2024.24552](https://doi.org/10.14722/ndss.2024.24552). 저자 프로젝트 링크: [EM Eye](https://emeyeattack.github.io/Website/). 이번 검토는 로컬 PDF를 읽었으며 이 링크의 현재 웹 내용을 별도로 검증한 것은 아니다.
- 로컬 원본: C:/Users/leechanghoon/Desktop/2024-552-paper.pdf. 크기6,987,450 bytes,17쪽. SHA-256: c5e5a536335dde250f158e5ca7e576b49b990bd4b7c09c8d37d5d379e4f54bb7.
- 정독: printed/PDF pp3–7의 §III, §IV, §V 전체; p8의 평가 방법과 번역 모델 한계; p13의 한계/결론; pp15–16의 Appendices B/C/D와 Fig18; p17의 색상 추론 한계 및 장비; p1의 제목·저자·venue.
- 추가 확인: p14 reference[8] 서지. pp9–12는 관련 키워드 주변을 확인했으며 그 모든 문단을 정독했다고 주장하지 않는다. p2 역시 이번 정독 범위 밖이다. **17쪽을 추출했다는 사실과17쪽을 전부 읽었다는 주장은 다르다.**
- 시각 확인: p4 Fig5/Eq1, p6 Eq2, p7 Fig7/Eq3, p15 RAW10 배치식, p16 Fig17/18. PyMuPDF2배 렌더를 확인하고, p4/p7은 Poppler144 dpi 렌더로 재확인했다. Full text와 렌더는 이 폴더의 ignored cache/에만 보존한다.

## 2. 가장 중요한 차이: RF stitching과 image fusion

**원문 §V, pp6–7, Fig7:** 각 대역에서 AM 기반 단일대역 영상을 먼저 만든다. 극성을 보정하고 histogram equalization을 적용한 뒤, 서로 다른 대역의 **영상을 가중 합산**한다. 그 다음 별도의 supervised pix2pix image-to-image 단계가 이어진다.

| 단계 | EM Eye가 요구하는 정합 | Chapter5 coherent stitching과의 차이 |
|---|---|---|
| 단일대역 영상 | frame/row timing, AM sample-to-raster mapping | 복소 RF 위상이 보존될 필요는 없음 |
| 다중대역 영상 합산 | 같은 장면·동일 영상 좌표·대비/극성의 일관성 | 대역 간 LO phase와 RF overlap 위상을 맞추지 않음 |
| Image-to-image | 별도 paired training data와 scene 분포 | 측정되지 않은 정보를 의미적 prior로 추정할 수 있음 |

따라서 기존 iPhone 자료에서 AM 문자 구조는 보이지만 complex coherence가 낮다는 결과와 **영상 영역 결합을 시험할 수 있다는 판단은 양립**한다. 그러나 fusion 영상은720 MHz의 연속 복소 파형, bit열, RGB를 물리적으로 복원한 결과가 아니다. 서로 다른 대역이 같은 내용의 같은 위치를 표현해야 하며, 장면 변경·노출/밝기 변경·다른 방사원 혼입이 있으면 이 가정부터 깨진다.

## 3. Eq1: 논문의 누설 모델과 그 범위

**원문 p4 Eq1:**

I_EM^[l,h] = R_base{ z + b_clk + F_filt[l,h,F_data(I_GT)] }.

- F_data는 영상에서 송신 bit stream으로 가는 mapping이다. 예시는 RAW10 CSI-2,2 data lanes다.
- F_filt는 선택 대역의 전파/전달 특성을 묘사한다. z는 잡음, b_clk는 안정한 clock 진폭이 만드는 offset의 단순화다.
- 원문은 전달함수를 정확히 측정하기 어렵다고 인정하고, sampled range 안의 상수 같은 단순 근사도 관측 영상의 왜곡을 재현한다고 설명한다(p5).
- 이는 calibrated antenna/common-mode 회로 모델이나 iPhone DSI PHY 모델이 아니다. Data와 clock 여러 wire의 방사가 함께 수신된다고 명시한다(p4–5).

**원문 p5:** 데이터 방사를 디지털 bit의 넓은 baseband spectrum으로 해석한다. 모든 에너지가 clock에 의도적으로 AM 변조되어 실리는 단일 carrier라고 가정하지 않는다. 204 MHz와255 MHz에서 edge/gray-scale 정보가 다르게 보였고, 예시 장치의51 MHz byte 주파수 및 harmonic 주변이 강했다고 보고한다. iPhone의 RF tuning center, D-PHY forwarded clock, lane bit-rate를 이 값과 동일시하면 안 된다.

**본 감사의 물리적 해석:** 좁은 수신 대역에서 강한 clock phasor C와 작은 data 성분 d가 겹치면 |C+d| ≈ |C|+Re{d exp(−j arg C)}가 된다. 상대 위상/결합이 바뀌면 영상의 밝기 변조 방향이 바뀔 수 있다. 이것은 Eq1의 상수 offset만으로 모든 극성 현상을 설명한다는 뜻이 아니며, 실제 수신 위상과 혼합을 고려한 근사 설명이다.

## 4. Fig5: RAW10 packing, cycles, inter-bit

**원문 Fig5 p4, Appendix B p15**의2-lane RAW10 배치는 다음과 같다. 각 high byte는 한 pixel의 B2…B9를 담는다. 네 pixel의 B0/B1은 별도의 packed byte에 모인다.

| Per-lane byte slot | Lane0 | Lane1 |
|---:|---|---|
| 0 | Pixel0 B2…B9 | Pixel1 B2…B9 |
| 1 | Pixel2 B2…B9 | Pixel3 B2…B9 |
| 2 | Pixels0–3의 B0/B1 packed byte | Pixel4 B2…B9 |
| 3 | Pixel5 B2…B9 | Pixel6 B2…B9 |
| 4 | Pixel7 B2…B9 | Pixels4–7의 B0/B1 packed byte |

그 다음8-pixel 묶음으로 진행한다. **Byte 안의 LSB-first와 pixel의10 bits를 B0→B9 순서로 한 lane에서 연속 전송한다는 주장은 다르다.** Fig5는 후자를 지지하지 않는다. 이 배치 스케줄은 lane당5 byte times=40 bit times 뒤 반복되지만 다음 pixel 값이 달라지므로 파형 자체의 완전한40-bit 주기를 뜻하지 않는다.

### 4.1 원문의 DDR 문장에 있는 내부 불일치

P4는 f_clk가 bit 주파수 f_b의 두 배라고 서술하지만, 바로 이어 **f_clk=204 MHz, byte 주파수=51 MHz**라고 적는다. 후자의 수치와 DDR의 두 edge/clock 관계는 다음을 뜻한다.

f_bit,lane = 8 f_byte,lane =408 Mbit/s =2 f_clk,

f_byte,lane = f_clk/4 =51 Mbyte/s.

즉 해당 문장의 비율 방향은 수치 예와 모순된다. 이를 그대로 복사해 f_DDR, f_byte를 뒤집으면 안 된다. 두 lane의 합산 byte throughput과 lane당 byte-clock 역시 구분한다. 이 수치는 Raspberry Pi Cam V1 예시이며 iPhone 측정치가 아니다.

### 4.2 ‘8-bit cycle’은 무엇인가

**원문 §V-B p6:** B2와B6가8-bit cycles의 같은 반복 주파수에 나타나며, 그 두 배의 주파수에 inter-bit variation이 반영될 수 있다고 설명한다.

여기서8-bit는 **bit position이 다음 전송 byte에서 재등장하는 직렬화 간격**이다.8 pixels,8 frames,8개의 USRP samples가 아니다. RAW10의 packed-LSB 슬롯 때문에 이것을 모든 송신 bit에 적용되는 유일한 정확 주기로 확장할 수도 없다.

**설명을 위한 조건부 Fourier 유도:** 길이8의 반복 모티프에서 B2 성분을 위치q=0, B6를q=4에 놓고 나머지 bit·필터·lane를 잠시 제외하면 harmonic k의 계수는

C_k ∝ B2 + B6 exp(−j2πk·4/8) = B2 + (−1)^k B6.

따라서 a=f_bit/8에서의 혼합과2a에서의 혼합은 서로 다른 조합을 포함한다. 이것이 **대역별로 상보적 정보를 가질 수 있다**는 간단한 예다. 이 식은 논문에 인쇄된 유도가 아니라 본 감사의 설명 모델이다. 실제 방사에는 전이 pulse, 다른 bits, packed slots, 여러 lane/clock의 결합과 RF 전달함수가 포함된다.

복소 C1,C2가 정확히 알려지고 다른 항이 없으면 두 미지수의 선형식을 풀 수 있지만, EM Eye는 주로 |C|에 해당하는 진폭 정보만 쓰므로 sign/phase와 bit ordering을 잃는다. ‘2a를 수신하면 B2와B6를 개별 decode한다’는 결론은 나오지 않는다. 서로 다른 대역의 영상 평균이 원 bit열을 자동 복원한다는 주장도 아니다.

## 5. Eq2, Fig18: IQ, sample 수, raster

**원문 p6 Eq2:**

I_EM[i_r,i_c] = (1/n_samp) Σ_(n=n1)^n2 a[n],

a[n] = F_amd(m[n]), n_samp=n2−n1+1,

n1= floor{Fs(i_f T_f+i_r T_r+i_c T_c)},

n2= floor{Fs(i_f T_f+i_r T_r+(i_c+1)T_c)}.

**m[n]은 USRP가 출력한 discrete complex IQ 측정값**이다. 송신 MIPI bit열이 아니다. 일반적인 AM baseline은 a[n]=|m[n]|로 명시할 수 있지만, 논문은 F_amd라는 함수 표기로 적고 모든 세부 파라미터를 열거하지는 않는다.

**수식 감사:** 인접 pixel interval에서 이전 n2와 다음 n1이 같고 양쪽을 inclusive하게 합하면 경계 sample이 중복된다. 재현 구현은 이 literal convention을 기록하거나, half-open interval [n1,n_next)로 바로잡아 명시해야 한다. Fs T_c<1이면 half-open bin이 비므로, 원래 physical pixel을 억지로 채우지 말고 sampling이 지지하는 더 거친 output grid/분수 sample 적분을 정의해야 한다. 같은 IQ sample을 여러 pixel에 반복한 것은 해상도 증가가 아니다.

**원문 Appendix D pp15–16, Fig18:** 먼저 blanking을 포함한 raw raster를 만들고 crop한다. Raw height≈T_f/T_r, 최대 raw width≈Fs T_r다. 논문은 보여주는 이미지의 가로폭을 비례 확대했다고 명시한다. 따라서 출력 PNG의 폭을 RF sampling 또는 physical pixel 수로 사용하면 안 된다.

T_fd, W_EM=Fs T_fd/H_EM 등의 식은 row/frame blanking과 active 영역의 정의를 따라 해석해야 한다. 모바일 command/burst DSI에서 이 raster가 곧 physical column 순서라는 가정은 별도 검증 사항이다.

### 5.1 Chapter5의 m[i]와 비교

기존 Chapter5 printed p114 Eq5.21의 m[i]는 w_T,w_D,h_T,h_D로 만든 **synthetic binary blanking-location mask**다. 예를 들어 horizontal/vertical blanking 위치에1을 놓아 영상의 translational offset을 찾는 template다. 일반적으로 밝은 blanking이라는 그 문서의 관측 가정도 포함한다.

- EM Eye m[n]: complex USRP IQ measurements.
- Chapter5 m[i]: 위치 정렬에 사용하는 binary mask.
- MIPI 송신 bit sequence: 이 둘 중 어느 것도 아님.

## 6. 극성 보정과 threshold: 명시된 것과 빠진 것

**원문 p5, §V-A p6, Appendix C pp15–16:** data/clock wire의 방사가 섞이면 reconstructed gray-scale polarity가 뒤집힐 수 있다. 저자는 wire를 따로 연장해 측정한 대조로 설명한다. 단일대역 영상은 data-wire-only simulation과 비교해 필요할 때 밝기 polarity를 반전하고, histogram equalization으로 clock offset의 contrast 영향을 줄인다.

이 **영상 밝기 극성**은 I+jQ/I−jQ의 **IQ spectrum polarity**와 다르다. |conj(z)|=|z|이고 |−z|=|z|이므로 IQ conjugation이나 global π phase 자체는 AM 영상 밝기를 반전시키지 않는다. 영상 반전은 I′=a−I와 같은 표현이다. 검증된 DSI forward simulation이 없는 현재 자료에서는 training 영상 간 상대 contrast sign을 추정할 수 있지만, 이를 실제 wire/RF polarity 측정으로 표현하지 않는다.

**원문 §V-B p7:** 너무 noisy한 components를 제거하는 thresholding criterion을 reference[8]와 유사하게 사용한다고만 설명한다. 구체적인 수치, threshold 계산식, selection metric, 자동화/수동화 비율은 이 절에 없다. Reference[8]은 Jieun Choi, Hae-Yong Yang, Dong-Ho Cho, *Tempest Comeback: A Realistic Audio Eavesdropping Threat on Mixed-signal SoCs*, CCS2020이다(p14). 그 논문 자체는 이번 검토 범위 밖이다. 따라서 임의의 threshold를 ‘EM Eye 원문의 설정’이라고 부르면 안 된다.

## 7. Eq3의 재현성과 퇴화해 감사

**원문 p7 Eq3:**

I_hat = Σ_i w_i I_i,

[w_i] = min_[w_i] ||c − S(I_hat)||.

S는 사람이 **single-color로 보이는 영역을 수동 선택**하는 segmentation이고 c는 선택한 constant gray-scale다. 일반적인 사용 대역 수는1–3이라고 적는다. 인쇄식은 i=0…N으로 합하지만 설명은 N개 bands이므로 구현은 N개 배열0…N−1로 표기를 정리해야 한다. 또한 optimizer는 엄밀히 min이 아닌 argmin을 반환해야 한다.

| 빠진 정의 | 실제 영향 |
|---|---|
| norm 종류·ROI pixel normalization | L1/L2/robust loss와 ROI 크기에 따라 가중치가 달라짐 |
| w의 부호/범위/합 제약 | 음의 큰 계수로 background와 문자 모두 상쇄할 수 있음 |
| c의 선택·스케일·고정 여부 | 목표 밝기나 출력 gain이 식별되지 않을 수 있음 |
| registration·pixel correspondence | 서로 다른 장면 위치를 더할 위험 |
| noise threshold 상세 | 같은 원문 조건의 재현이 불가능 |
| ROI 선택/형태 보존 평가 | flat ROI loss만 줄이고 글자까지 지우는 해 가능 |

**퇴화 예:** c=0이 허용되면 w=0은 전역 최솟값0이다. c도 함께 최적화하면 (w,c)→α(w,c), α→0으로 loss가 줄어든다. **고정 c≠0인 경우 w=0이 언제나 최적이라고 말해서는 안 된다.** 다만 ROI별로 각 입력을 zero-mean 처리해 X_R^T1=0이 되면 L2 loss는 ||X_Rw||²+|R|c²여서 w=0이 다시 최솟값 중 하나다. 상관된 대역은 X_R의 rank를 낮추고 여러 w를 같은 ROI 평탄도로 설명할 수 있다. ROI만 평탄하게 만들었다는 것은 영상 내용 복원 증거가 아니다.

## 8. RGB888 DSI에 옮길 때 성립하는 것과 가설

**성립 가능한 연구 방향:** 단일대역 AM 영상들이 주파수에 따라 서로 다른 왜곡/contrast를 가진다면, RF phase alignment 없이 image fusion을 비교할 수 있다. 여기에는 ‘DSI는 무조건 low-rank’라는 가정이 필요 없다.

**직접 옮길 수 없는 부분:** RAW10의4-pixel/5-byte packing, Bayer/debayering,2-lane mapping,204/51 MHz 값은 RGB888 DSI의 값이 아니다. iPhone의 실제 lane 수·HS bit-rate·packet mode·blanking·clock continuity가 검증되지 않았고 RGB888 역시 현재 가정이다.

**조건부 RGB888 byte-round-robin 유도:** uncompressed3-byte color tuple(C0,C1,C2)을 L data lanes에 byte 단위 round-robin으로 배분한다고 가정한다. Color/lane 할당의 최소 반복은 aggregate lcm(3,L) bytes이고, lane당 반복 시간은3/gcd(3,L) byte times다.

| L lanes | 반복 tuple 수 | lane당 byte slots | lane당 bit-position motif |
|---:|---:|---:|---:|
| 1 | 1 | 3 | 24 bit times |
| 2 | 2 | 3 | 24 bit times |
| 3 | 1 | 1 | 8 bit times |
| 4 | 4 | 3 | 24 bit times |

예를 들어 RGB 순서의2 lanes에서는 lane0이 R0,B0,G1을, lane1이 G0,R1,B1을 받는6-byte 묶음이 반복된다.3 lanes라면 각 lane이 한 color 위치를 계속 받는다. 실제 byte color order는 별도 확인해야 한다. Packet header/CRC/SoT, lane start/stop과 blanking이 payload 배치를 끊을 수 있다. 이 표는 **할당 스케줄의 주기**이며 RF 파형에 반드시 특정 tone이 생기거나 bit값이 반복된다는 뜻이 아니다.

이 가정의 lane byte rate는 f_bit,lane/8, aggregate payload byte throughput는 L f_byte,lane다. Continuous payload에 한해 pixel throughput=(L/3)f_byte,lane이다. 전체 frame rate·해상도에서 HS instantaneous rate를 얻으려면 packet overhead와 duty cycle을 알아야 한다. 현재 Fs=124.0828 MS/s, RF BW120 MHz, raster1100×1881만으로 f_byte/f_DDR/f_bit를 확정할 수 없다.

## 9. 구현 가능한 non-generative fusion baseline 제안

아래는 **EM Eye 아이디어에서 출발해 모호한 설정을 보완한 새 baseline**이다. Eq3의 완전한 동일 재현으로 표기하지 않는다. 기존 unit/raw 결과를 덮어쓰지 않는다.

1. **입력과 split 고정.** 각 band를 별도 AM로 복원하고 raw-derived float raster를 사용한다. 표시용 PNG, equalization된8-bit 이미지를 원래 radiometric 데이터로 쓰지 않는다. Training으로 timing/registration/contrast sign/normalization/masks/weights를 모두 정한 뒤 독립 frames에 고정한다.
2. **Image registration.** 같은 장면의 training AM 구조에서 제한된 translation/필요한 raster wrap을 추정한다. Band마다 vertical stripe가 강하므로 gradient/반복 feature의 정합을 따로 기록하고 무제한 elastic warp로 글자를 맞추지 않는다. 실제 screenshot pixel을 정합 target/weight fit에 넣지 않는다.
3. **Scale/polarity 명시.** Training에서 robust location/scale을 정해 고정한다. 상대 영상 sign이 모호하면 두 가설을 유지하거나 해당 band를 제외한다. Train/test histogram을 각각 맞추면 test fit이므로 피한다. 원문 histogram equalization을 비교할 경우 training에서 정한 LUT를 고정하고 별도 ablation으로 표시한다.
4. **단순 대조 먼저.** Training-selected best single band, equal weights, inverse training disagreement proxy weights, constrained distortion-guided weights를 같은 입력·scale로 비교한다. 서로 다른 frame의 차이는 jitter/내용 변화도 포함하므로 이를 자동으로 순수 noise나 SNR이라고 부르지 않는다.
5. **작은 조합부터.** 원문의1–3-band 관례를 따라 사전 지정 pair/triple로 시작한다. 모든11개를 먼저 더하거나 많은 조합 중 test가 좋아 보이는 조합을 고르지 않는다. 기존 화면을 보고 고른 후보는 exploratory selection임을 기록한다.

### 9.1 예시 목적함수

정합된 training image vectors를 columns로 가진 X, flat candidate ROI 선택행렬 P_R, ROI 평균 제거행렬 C_R를 정의한다. X의 normalization은 training에서 고정한다. Baseline weights w0, ridge λ를 사용해

min_w  ||C_R P_R Xw||²/|R| + λ||w−w0||²,

subject to w≥0, 1^T w=1, q^T w≥κ.

여기서 q_i=<G_E x_i,G_E x_anchor>/||G_E x_anchor||²는 **training에서만 고른 반복 구조 영역 E**의 anchor 대비 gradient gain이다. q_anchor=1이므로 κ≤1이면 anchor-only 해가 feasible하다. 이 제약은 flat-ROI 최적화가 실제 구조까지 지우는 것을 줄이려는 장치다. λ,κ,ROI 후보를 test로 tune하지 않는다. q는 물리적인 영상 신호 검출 확률이 아니다. Anchor에 강한 vertical stripe가 있으면 이 제약은 stripe도 보존할 수 있다. 따라서 E의 선택 근거와 전역 row/column 성분 대 국소 반복 구조의 변화도 분리해 보고하고, q 증가를 원하는 영상 성분의 증가로 자동 해석하지 않는다.

Simplex는 w=0을 막고 음의 큰 상쇄를 제한한다. 그래도 정보가 없는 band/부정확한 registration 때문에 평탄해질 수 있으므로 아래 평가가 필수다. 위 목적함수는 small dense covariance와 bounded simplex search/projected optimization으로 구현 가능하며, 설치되지 않은 추가 Toolbox를 전제할 필요가 없다. 음의 weights를 허용하는 모델은 별도의 bounded signed-L1 실험으로 분리하고 문자/edge 손실과 coefficient 불안정성을 함께 기록한다.

### 9.2 독립 검증과 중단 기준

- **검증 구간 이력:** 지난 AM64 실험은 해당 3개 대역의 frames0–63을 이미 사용했다. 그 결과를 본 뒤 그 일부를 새 blind test라 부를 수 없다. 2026-10-24 좁은 대역 100/160 MHz 실험에서는 frame64도 사용된 것을 저장된 overview.json에서 확인했다. 따라서 후속 영상 결합의64–71은 결합 파라미터 추정에 사용하지 않은 후속 구간으로 평가하되, 전역적으로 아직 보지 않은 blind 데이터라고 표시하지 않는다. 새 독립 검증에는 전체 access log 확인 후 다른 구간 또는 재수집이 필요하다.
- Training weights·geometry·normalization·display scale·ROI를 고정한 test에서 ROI의 residual variation, ROI 밖의 edge retention, repeated-feature consistency와 clipping율을 보고한다. Loss만 낮아지거나 글자가 지워진 경우 improvement로 채택하지 않는다.
- Best single/equal/inverse-disagreement와 비교하고, training ROI 하나를 빼는 sensitivity, frame-block bootstrap 및 weight 변화도 기록한다. 같은 raw file의 static scene 재현은 noise/time generalization이며 새로운 화면 내용에 대한 일반화는 아니다.
- Ground-truth screenshot은 **학습·가중치·픽셀 채우기에 사용하지 않는다.** 최종 설정을 고정한 뒤 원본 대비 평가가 필요하면 별도의 evaluation-only 자료로 사용하고 정합/metric 조건도 공개한다. 같은 screenshot으로 hyperparameter를 고르고 성능까지 보고하면 순환 평가다.
- 결과는 ‘registered multiband AM image fusion’으로 표시한다. 물리적인720 MHz coherent waveform이나 DSI bit 복원으로 부르지 않는다. 저 rank/high rank로 원하는 회로가 자동 분리됐다는 주장도 하지 않는다.

## 10. Image-to-image의 한계와 현재 연구에 적용할 판단

**원문 p7 §V-C:** supervised aligned pix2pix conditional GAN을 쓴다. Training scene의 variation 범위와 비슷한 test에서 잘 된다고 설명한다. 평가 기본 설정은 두 dataset에서 각각3000개 중2700개 training, 총600개 test,100 epochs, RF sample rate8 MHz다. 일반화 평가와 dedicated sensor/controller 재학습을 구분한다(pp7–8).

**원문 p8:** 작은 textual objects 같은 세부를 translation network가 왜곡할 수 있어 untranslated multiband image를 참조하라고 명시한다. **원문 p7 및 Appendix G p17:** color는 EM 물리로 얻은 것이 아니라 image semantics/training examples로 추론되며 실제 color와 달라질 수 있다고 명시한다.

따라서 현재 전화기 테스트 문자열 연구의 첫 baseline에는 GAN·diffusion·inpainting을 넣지 않는 편이 해석 가능하다. 이후 사용하더라도 원본 AM, non-generative fusion, learned output을 별도 보존하고 생성/추론된 glyph·color를 측정 복원으로 평가하지 않아야 한다. EM Eye 최종 영상 예시의 모든 개선을 Eq3 하나의 성능으로 인용해서도 안 된다.

## 11. 실행자에게 전달할 결론

- 기존 실패한 complex-overlap chain과 별도로 image-level multiband fusion을 시험할 근거는 있다.
- Eq3는 실험 재현에 필요한 제약/threshold가 충분히 명시되지 않은 heuristic이다. 제약·scale·ROI와 fresh held-out를 추가한 baseline으로 실행하고 변경을 공개한다.
- ‘Cycles/inter-bit’는 직렬화 스케줄과 Fourier 가중 조합에 대한 설명이다. Envelope를 수신했다는 사실만으로 bit ordering·RGB888·lane rate가 복원되는 것은 아니다.
- RAW10의 배치와 CSI 예시 숫자는 iPhone DSI에 직접 대입하지 않는다. 회로·packet·lane·clock은 별도로 확인할 가설이다.
- 이번 문서는 paper audit와 설계안이며, 새로운 MATLAB 처리나 iPhone fusion 성공을 보고하는 결과 문서가 아니다.
