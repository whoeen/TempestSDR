# iPhone 6 11-band sweep: Chapter 5 algorithm audit

검토일: 2026-10-23. 역할: 원문 및 구현 수학 검토. 본 에이전트는 MATLAB과 실제 IQ 처리에 접근하지 않았다. 아래 제안과 실제 실행 결과를 구분한다.

## 1. 첨부 원문을 이번에 읽은 범위

- 첨부: C:/Users/leechanghoon/Desktop/Chapter5_Stitching multiple narrowband recording into a single wideband_Exploiting quasiperiodic electromagnetic.pdf
- 크기 1,451,677 bytes, SHA-256 fa3a41d10f8897d62298a19303829bf5ec406b72fde348765db98e92271f98f0.
- 첨부의 **15쪽 모두**를 텍스트로 읽었다. 인쇄 쪽 109–123에 대응한다. §5.1과 §5.2는 완전하며, §5.3은 Eq.5.43 뒤에서 잘린다. 5장 전체 또는 HMM 실험 전체가 포함된 문서는 아니다.
- 수식/그림 시각 대조: 첨부 3–11, 14–15쪽 = 인쇄 111–119, 122–123쪽. 원문 별도 155쪽 PDF의 109–123쪽과 공백을 제거한 텍스트가 **15쪽 전부 일치**한다. 결과: source_page_comparison.json.
- 전체 추출문과 렌더는 cache/에 보존하며 cache/.gitignore로 공유에서 제외한다. 이 노트는 저자 본문 전체 번역이나 재배포본이 아니다.
- 기존 reading_109_155.md의 수식 부호 지적을 이번 첨부 렌더에서 재확인했다. 기존 기록을 읽었다는 것만으로 이번 첨부 검토를 대신하지 않았다.
- 기본 출처: Christian David O’Connell, *Exploiting quasiperiodic electromagnetic radiation using software-defined radio*, Cambridge, 2018. 공식 기록 https://www.repository.cam.ac.uk/handle/1810/290902 (DOI 10.17863/CAM.38085).

## 2. 이번 측정에 원문 기호를 대입한 값

사용자 진술: iPhone 6, 같은 캡처 화면, USRP 2940R, 명목 순간 BW 120 MHz, LNA/BPF 없음, 프로브와 전화기 clamp 고정, 중심 100:60:700 MHz의 순차 11개 캡처. ADC/IQ 파일의 실제 Fs는 이 문서 작성 시점에 미확정이다. 다른 iPhone 캡처의 Fs를 이 sweep에 대입하지 않는다.

원문은 overlap **폭**에 그리스 문자 Υ를 쓴다. 사용자 λ=50%는 비율 λ=Υ/B_in이라고 정의하면 맞다. 중심 이동 비율과 overlap 비율은 서로 보수 관계이며, 이번에는 양쪽 모두 0.5라 구별이 숨겨진다.

| 항목 | 이번 값 | 근거 |
|---|---:|---|
| 한 캡처 명목 폭 B_in | 120 MHz | 사용자 진술 |
| 중심 이동 Δfc | 60 MHz | 파일 중심 목록/사용자 진술 |
| overlap Υ=B_in−Δfc | 60 MHz | 기하 계산 |
| overlap 비율 Υ/B_in | 50% | 원문 p119 실험 선택과 일치 |
| 중심 범위 | 100–700 MHz | 폭 600 MHz |
| 명목 전체 RF 범위 | 40–760 MHz | 양 끝 중심 ±60 MHz |
| 전체 합성 폭 B=11(120−60)+60 | 720 MHz | p111 Eq.5.2 |
| 전체 합성 RF 중심 fc | 400 MHz | 양 끝 평균 |
| 원문 positive-analytic 내부 Fs_out=2B | 1.44 GS/s | p111 §5.2 |
| 인접 2개 합성 폭 | 180 MHz | B=120+60 |
| 연속 k개 합성 폭 | 120+60(k−1) MHz | 동일 기하 |

1.44 GS/s는 **계산상의 출력 격자**다. 실제로 1.44 GS/s로 측정했다거나 그만큼 독립 정보를 확보했다는 뜻이 아니다. 원문은 실제 스펙트럼을 0…B에 올려 실수 계수 LP/HP 필터를 적용하려고 Fs_out=2B를 택했다. 복소 baseband −B/2…B/2에서 support-aware frequency weights를 적용하는 구현은 다른 격자를 사용할 수 있으나 원문 literal implementation과 구분한다.

각 캡처의 유효 폭은 실제 아날로그·DDC 응답 및 Fs로 검증한다. 유효 폭을 B_use라고 할 때 실효 overlap은 B_use−60 MHz다. B_use가 100 MHz라면 40 MHz가 겹치며 50%가 아니다. B_use≤60 MHz이면 이 중심 간격으로 양의 overlap이 보장되지 않는다.

## 3. 원문 §5.2 순서와 구현 식

### 3.1 전처리와 공통 시간 좌표

p112는 각 band에 Chapter 4의 periodic averaging을 선택적으로 수행하고 timestamp와 pixel-clock 추정으로 거친 영상 위치를 맞춘다고 명시한다. §5.2 자체는 새로운 clock tracker/relative CFO 추정기를 주지 않는다.

- Raw complex IQ를 보존한다. 각 band를 AM 또는 HSV 그림으로 바꾼 뒤 그림끼리 더하는 것은 이 절의 stitching이 아니다.
- 복소 평균은 시간축과 위상 정렬 후에 수행한다. 대조군으로 magnitude 평균과 미보정 complex 평균을 같이 둔다.
- 공통 frame/packet 반복 길이는 데이터로 확인한다. iPhone의 이전 1880/1881-row 가정을 그대로 고정하지 않는다.
- capture마다 동일 상태가 반복된다는 근거가 없으면 여러 프레임을 강제로 한 프레임으로 접지 않는다. 프레임 polarity 또는 패킷 상태가 번갈아 바뀌면 2-frame 이상 superperiod도 후보로 둔다.

일반적인 시간 warping 및 complex average 표현은 다음과 같다. 이는 이식용 구현 명세이며 §5.2에 같은 식이 인쇄돼 있다는 주장이 아니다.

\[
\bar v_b(u)=\frac{\sum_{k\in\mathcal K} a_k(u)\,v_b(t_{b,k}(u))e^{-j\theta_{b,k}(u)}}{\sum_{k\in\mathcal K}a_k(u)}.
\]

여기서 u는 공통 원시 시간 좌표, t_b,k(u)는 각 실제 capture의 fractional sample 위치다. a_k는 유효 관측 마스크/고정 가중치다. θ는 근거 있는 clock/LO 위상 보정이다. 샘플마다 자유 위상이나 그림 내용에 맞추는 변형을 허용하면 원하는 결과를 강제로 만들 수 있으므로 모델 자유도를 제한한다.

### 3.2 공통 Fs로 rational resampling (첨부4 / p112 Eqs.5.7–5.12)

입력률 Fs_in, 출력률 Fs_out의 비율을 p/q≈Fs_out/Fs_in으로 정한다. 원문 Eq.5.7의 R는 반대로 Fs_in/Fs_out, 즉 출력 한 sample당 입력 위치 증가량이다. MATLAB resample(x,p,q)에 넣을 비율과 뒤집지 않는다.

원문의 LCM은 **두 샘플링률을 rational integer ratio로 맞추기 위한 계산**이다. MIPI lane clock/frame/packet의 최소공배 주기를 추정하라는 식이 아니다. Fs 실측값이 소수/비정수일 때 이를 문자 그대로 큰 정수 LCM으로 만들면 계산량이 폭증한다. rational approximation 허용 오차를 record하고 누적 시간 오차를 별도로 검사한다.

주파수 합성 전 보간은 anti-imaging, 감소 resampling은 anti-aliasing이 필요하다. fractional raster display용 cubic interpolation이 원시 wideband resampler 검증을 대신하지 않는다.

### 3.3 RF 위치 배치 (첨부4 / p112 Eq.5.13)

원문 내부 좌표:

\[
\widetilde w_b[n]=w_b[n]\exp\{j2\pi(f_{c,b}-f_c+B/2)n/F_{s,out}\}.
\]

이번 11-band에서 내부 중심은 60,120,…,660 MHz다. 전체 RF 40–760 MHz가 내부 0–720 MHz에 대응한다. 최종 출력은 p118 Eq.5.37대로 exp(−j2π(B/2)n/Fs_out)를 곱해 −360…+360 MHz baseband로 이동한다.

### 3.4 delay/phase 상관 convention (첨부5–6 / pp113–114 Eqs.5.14–5.20)

다음 한 정의를 전체 코드에 사용한다.

\[
r[d]=\sum_n\widetilde w_b[n+d]y_b[n]^*
=\operatorname{IFFT}\{W_bY_b^*\}[d].
\]

FFT의 negative lag를 배열 뒤에서 올바르게 재배치하고 선형 상관에는 Nfft≥N+P−1로 zero-pad한다. 알려진 신호 w[n]=e^{jφ}y[n−d0]라면 최대점은 d0, peak phase는 φ다. 따라서

\[
\hat d=\arg\max_d|r[d]|,\quad
\hat\phi=\arg r[\hat d],\quad
x_b[n]=\widetilde w_b[n+\hat d]e^{-j\hat\phi}.
\]

원문 Eq.5.14는 이 r의 복소켤레를 정의하고 Eq.5.17은 위 r를 계산한다. Eq.5.20의 n−τ를 Eq.5.17과 그대로 결합하면 delay 부호가 반대다. 첨부 수식 원화에서 확인한 불일치다. 기존 verification/verifyStitchConventions.m은 +7,−11,0 sample synthetic 사례를 검증했으며, 새 측정의 stitching 성공을 입증하는 시험은 아니다.

원문 Eq.5.18은 한 프레임에 해당하는 delay 구간을 검색하며 zero-lag를 포함한다. 강한 line-period peak가 여러 개 나오므로 한 peak만 보고 결정하지 않는다. 화면 위치/row timing에 일치하는 후보들을 held-out time windows에서 비교한다.

**첫 band는 예외:** p112–113은 y1=w0로 직접 넣고 정렬/필터를 생략한다. p119 Algorithm4에는 예외가 빠져 있다. y0=0과 상관해 phase/delay를 추정하지 않는다.

### 3.5 fractional delay 및 상대 CFO: 모바일 구현 확장

§5.2의 argmax는 integer lag, phase는 상수다. 120 MHz 이상 실제 합성에서는 fractional delay와 잔여 CFO를 점검해야 한다.

- Fractional delay: coarse peak 주변 정밀 검색 또는 overlap cross-spectrum phase slope를 이용한다. w(t)=e^{jφ}y(t−τ)이면 arg(WY*)≈φ−2πfτ. 보정은 W(f)exp(+j2πfτ−jφ). 여러 고립 tone만 남으면 τ가 모호하므로 넓은 유효 overlap과 독립 segment가 필요하다.
- Relative CFO: coarse time 정렬 후 overlap 신호의 cross product를 짧은 창마다 누적한 c_j=Σ w_aligned[n]conj(y[n])로 phase-vs-time을 얻는다. arg c_j≈φ+2πδf t_j를 fit한 뒤 exp[−j(φ+2πδf t)]를 적용한다. 낮은 coherence 창을 mask하고 phase wrap/cycle slip을 검사한다.
- CFO가 overlap coherent integration을 이미 지운 경우 짧은 창 또는 2차원 delay/CFO 탐색으로 초기화한다. 사후 선형 fit만으로 신호가 사라진 상관을 복구할 수 없다.
- sample-rate drift는 delay-vs-time의 slope이며 CFO와 같지 않다. 창별 지연을 τ(t)=τ0+εt로 fit해 fractional resampling으로 보정한다. 공통 clock source가 확인되지 않은 상태에서 carrier CFO를 그대로 pixel-rate drift로 바꾸지 않는다.
- 아날로그 gain 차이를 보정하려면 별도 calibration variant로 기록한다. 정렬된 q를 y에 LS fit하는 γ=(qᴴy)/(qᴴq)를 사용할 수 있지만, 각 band의 분산을 무조건 같게 만들면 실제 RF 스펙트럼까지 변조한다. 원문 기본은 scalar phase와 delay 보정이다.

클램프로 위치를 고정하면 공간 경로의 변동을 줄인다. 독립 LO retune 위상, 스마트폰 clock drift, AGC/수신 gain, DSI burst schedule, 시간에 따른 주파수 offset까지 고정됐다는 뜻은 아니다.

### 3.6 crossover (첨부7–11 / pp115–119 Eqs.5.22–5.37)

합치기 전에 old band를 low-pass, incoming band를 high-pass로 complementary weighting한다. 합의 진폭을 2배 만드는 overlap bump를 방지하는 단계다.

\[
f_{x,b}=f_{c,b}-f_c+\tfrac12(B+\Upsilon-B_{in}).
\]

이번 전체 합성에서 crossover 내부 위치는 90,150,…,630 MHz다. 저자는 W=8 L-R, 즉 4차 Butterworth를 forward/backward로 적용한 zero-phase squared-magnitude response를 사용했다. Cutoff에서 각 branch의 amplitude는 0.5 (−6.02 dB)다.

일반 digital Butterworth order n=W/2의 frequency response는 다음처럼 직접 평가할 수 있다.

\[
L_b(f)=\frac{1}{1+\left|\frac{\tan(\pi f/F_s)}{\tan(\pi f_{x,b}/F_s)}\right|^{2n}},\qquad H_b(f)=1-L_b(f).
\]

정규화 경계 f=0와 Nyquist를 별도로 처리하고 0/0 또는 Inf/Inf를 만들지 않는다. 이는 DC-normalized Butterworth의 **forward/backward steady-state** 응답이다. complex causal H 자체를 real-valued라고 부르면 안 된다. 인쇄 Eq.5.23의 일반 분자 ωx는 정규화 DC gain 관점에서 ωx²여야 하지만 예제 ω̃x=1에서는 차이가 사라진다.

\[
Y_{b+1}(f)=L_b(f)Y_b(f)+H_b(f)X_b(f).
\]

**FFT 직접 weighting이 성립하는 조건:**

1. 한 block이 실제 복소 파형의 반복 한 주기이고 끝/시작이 일치하면 DFT bin에서 위 L,H를 곱하는 circular filtering은 그 반복 신호의 정상상태 필터링이다. causal IIR을 무한 반복 실행할 필요가 없다.
2. 일반 유한 기록에서는 이 방법이 끝과 시작을 붙인다. zero-padding 및 충분한 guard를 둔 linear convolution 근사, 또는 overlap-save/overlap-add가 필요하다. IIR response는 무한 길이라 padding 길이를 impulse-response tail 오차로 정한다.
3. filtfilt도 유한 입력의 edge extension/initial-condition 규칙이 있다. 이상적 |H|² weighting과 경계 sample까지 동일하다고 주장하지 않는다. 같은 유효 구간에서 비교한다.
4. 한 frame에 비정수 residual carrier cycles가 남거나 복소 phase seam이 있으면 단순 frame FFT를 periodic 정상상태로 간주할 수 없다. CFO/phase slip 검사 후 필요하면 더 긴 superperiod 또는 비주기 처리를 택한다.
5. DFT grid에 중심 주파수를 억지로 정수 bin으로 반올림하면 잔여 frequency offset이 생긴다. time-domain exact complex modulation 또는 해당 격자를 만족하는 resampling을 사용한다. 반올림 오차는 반드시 Hz로 저장한다.

## 4. W=8을 이번 11개에 그대로 복사할 때의 구체적 위험

50% overlap이 같다고 filter order W=8이 항상 충분하지 않다. B/Fs_out가 변하고 crossover의 normalized frequency가 달라지면 원문 Fig.5.7의 비overlap 감쇠가 발생한다.

이번 기하 B=720 MHz, Fs_out=1440 MHz, W=8에서 직접 수식 평가한 값:

| 내부 crossover | overlap 시작에서 incoming high-pass weight | overlap 끝에서 old low-pass weight |
|---:|---:|---:|
| 90 MHz | 0.03552 | 0.08444 |
| 330 MHz | 0.25568 | 0.25919 |
| 390 MHz | 0.25919 | 0.25568 |
| 630 MHz | 0.08444 | 0.03552 |

없는 band의 해당 weight를 보충할 수 없으므로 중앙 crossover에서 overlap 바로 밖의 감쇠가 크다. 모든 band가 동일 underlying spectrum의 이상적인 rectangular 120 MHz 조각이라는 단순 대조에서도, 순차 L-R 합성의 내부 120…600 MHz grid상 amplitude transfer는 약 **0.70356…0.99910**이다. 실제 IQ 실험이 아니라 scalar 수학 응답 검사이며 Python에서 계산했다. 세부: lr_response_audit.json.

따라서 다음을 별도 라벨로 비교한다.

- **원문 baseline:** W=8 L-R, 원문 analytic positioning, 정렬 후 합산. 전체 effective transfer/edge loss를 표시.
- **L-R order variant:** W를 높여 tail을 줄이되 direct SOS/FFT response로 수치 안정성을 검사.
- **support-limited crossover variant:** 실제 overlap [fL,fH]에서 u=(f−fL)/(fH−fL), old weight=(1+cos πu)/2, incoming=1−old. overlap 밖은 해당 존재 band의 weight 1, 없는 band 0. 이것은 원문 literal L-R이 아닌 변경 방법이다.

같은 잔여 complex phase가 맞지 않으면 complementary weight 합 1만으로 seam cancellation을 막을 수 없다. 원문 Eq.5.35가 신호별 equality를 보증하지 않는다.

## 5. 실행할 조합과 출력

### 5.1 실용적인 조합

1. 단일 band 11개: 원시 AM, 시간 정렬 AM, global-phase-corrected complex mean, 위상 HSV, PSD, averaging 진행 P=1,2,4,8,….
2. 인접 pair 10개: (100,160),…,(640,700). 각 합성 폭 180 MHz. 동일 alignment를 원문 LR과 support-limited crossover에 적용해 비교.
3. 연속 triplet 9개: nominal 240 MHz. pair에서 추정한 edge와 residual 확인.
4. 전체 11개: nominal 720 MHz. 저주파→고주파와 역순/중앙 anchor에서의 parameter accumulation을 비교. 다만 reverse sweep는 같은 데이터의 계산 방향 대조이지 새 측정 반복성 검증이 아니다.
5. 연속 구간 전체는 단일 포함 66개, 길이≥2는55개다. **임의 두 band 55쌍과 구분**한다. 55개 임의 두 band 중 양의 nominal overlap은10개뿐이며, center가120 MHz 이상 벌어진45쌍은 직접 상관 alignment 근거가 없다. 중간 band chain이나 독립 기준 없이는 coherent pair 결과라고 부르지 않는다.

여러 조합을 위해 IQ 전체를 매번 resample하지 않고, 검증된 각 band의 시간 모델/complex template와 인접 edge estimates를 재사용한다. 최소 한 독립 시간 구간은 fit에 쓰지 않고 보관한다.

### 5.2 각 edge에 저장할 수치

- 입력 SHA, raw offset/length, endian/IQ sign, Fs/fc/BW 근거, gain, capture 순서.
- usable overlap 주파수 mask, DC spur/간섭 mask, spectral energy 분포.
- integer lag와 fractional lag(s 및 input/output samples), phase(rad), CFO(Hz), sample-rate drift(ppm), complex gain.
- 상관 peak/두 번째 후보, train/held-out normalized complex coherence, 잔여 phase-vs-frequency와 phase-vs-time.
- LR/대안 weights와 combined transfer, 유효 경계 crop, grid/anti-alias 설정, 정확한 phase reference.
- 원본 screenshot과 복원본의 정렬/평가에 사용한 transformation. screenshot은 연구자의 ground truth이며 복원 waveform을 생성하는 입력으로 사용하지 않는다.

위상 HSV 색은 상대 RF 위상이다. 실제 iPhone RGB로 해석하지 않는다. 약한 magnitude/낮은 coherence 위치는 mask한다.

## 6. 정합과 중단 판정: 원문에는 없는 실측용 기준

숫자를 임의의 보편 성공 threshold로 정하지 않는다. 다음 물리적 오차 예산과 held-out 결과로 범위를 정한다.

- 공통 유효 overlap의 normalized coherence: ρ=|Σx y*|/sqrt(Σ|x|²Σ|y|²). 높은 값은 복소 반복성을 나타내며 원하는 화면 내용이나 SNR의 증거가 아니다. 강한 clock/driver clutter도 ρ를 높일 수 있다.
- 주파수/위상 ambiguity: spectrum의 대부분이 단일 tone이면 phase는 잘 맞아도 delay가 정해지지 않는다. 넓게 분포한 정보 bin과 text-correlated ROI가 필요하다.
- 목표 잔여 phase sweep 예산을 π/6이라 두면 |δf|T<1/12. 한60Hz frame T≈16.7ms에서는 약5Hz, 1s coherent average에서는 약0.083Hz가 된다. 이 값은 제안한 오차 예산의 계산이지 측정된 oscillator 정확도가 아니다.
- delay error의 phase sweep 예산은 2πB_eff|δτ|<π/6, 즉 |δτ|<1/(12B_eff). 유효 overlap60MHz에 대해서 약1.39ns. 이는 overlap 내 변화량 기준이며 절대 RF 중심 phase는 별도 scalar phase로 흡수한다.
- 한 edge에서 train이 높고 held-out가 붕괴하거나, delay/CFO가 시간에 따라 모형으로 설명되지 않거나, text edge가 단일band보다 흐려지면 전체 chain을 성공으로 승인하지 않는다. 실패 edge 앞뒤를 각각 독립 결과로 보존한다.
- P 증가로 coherence만 상승하고 문자선명도/독립 ROI가 악화되면 더 누적하지 말고 drift/소스혼합을 먼저 점검한다.
- all11 결과가 불량해도 좋은pair/triplet을 버리지 않는다. 전체대역확장과 실제text정보증가를 별도로 기록한다.

## 7. MIPI-DSI에 옮길 때의 구분

첨부 후반 pp119–123은 HDMI/TMDS 3색선+clock의 혼합과 10-bit character transition을 다룬다. threshold0.3, 10-bit blanking template Eq.5.40, disparity reset을 MIPI에 그대로 대입하지 않는다.

- MIPI RGB888에는 TMDS의 8→10 encoding을 전제하지 않는다. DSI byte packet, lane round-robin, HS entry/exit, clock lane, display scan clock을 따로 모델링한다.
- 알려진 packet header/SoT 등은 원리상 phase/time anchor 후보이지만, lane mapping/HS mode/수신 결합 모델을 검증해야 한다. RF에서 강한 주기열이 관찰된다는 것만으로 그 바이트열을 decode했다고 주장하지 않는다.
- 여러 clock이 하나의 완전반복 주기를 갖는다면 그것은 source의 rational commensurability 문제다. 원문 LCM(Fs_in,Fs_out)와 다르다. 서로 독립 clock이면 단일 정확한 LCM period가 없을 수 있으며 source-specific alignment 또는 제한된 관측창이 필요하다.
- 모든 성분에 단일 CFO/시간 warp가 통하는지 확인한다. 한 driver component에 맞춘 위상 보정이 원하는 DSI component를 흐릴 수 있다.
- 전체 합성720MHz가 개별 MIPI lane bit rate보다 작을 수도 있다. 넓어진 대역으로 text 영상이 선명해지는 것과 bit/byte/RGB 값을 식별하는 것은 다른 검증 단계다. 원문 p110의 B′>fb 동기는 충분한 정보 확보를 위한 설계 설명이며 혼합 lane의 역문제를 자동으로 해결하지 않는다.

## 8. 최소 구현 순서 요약

A. 실제 파일 metadata·format·Fs 확정 → B. 11 band 단독 진단/시간 모델 → C. 한 capture의 가상 subband로 부호·보간·crossover 검증 → D. 10 실측 인접 pair의 overlap 정합(train/held-out) → E. 정합된 pair에 원문 W8/대안 weights 비교 → F. 3개 이상 chain 및 all11 → G. 원시 대조·중간 수치·screen 비교 갤러리.

원문에 없는 확장(CFO, fractional lag, clock drift, gain fit, support-limited weights)은 명시적으로 구별한다. 실패 판정을 통과시키기 위해 ground truth 문자나 screen을 신호 복원에 합성하지 않는다.
