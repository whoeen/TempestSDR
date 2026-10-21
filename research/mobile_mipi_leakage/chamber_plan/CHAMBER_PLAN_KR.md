# 3기종 화면 누설: 프레임 변동 해석과 챔버 수신 후보

작성일: 2026-09-21. 대상: LG X2(2019), Galaxy S4 LTE, iPhone 6s.

**장비 정보를 반영한 변경:** 사용 안테나는 Aaronia HyperLOG 7060이며 공식 정격은 **700 MHz–6 GHz**다. 기존 복원 중심 344.8/171.5/311 MHz는 모두 정격 밖이다. 이 LPDA를 사용하는 오늘 실험에서는 **700 MHz 이상을 탐색**한다. 기존 중심 재현에는 그 대역을 지원하는 별도 안테나 또는 기존 probe가 필요하다. 정격 아래에서 신호가 전혀 안 잡힌다는 의미는 아니지만, 감도·정합·방향성 보장 없이 결과를 비교하게 된다. [Aaronia 공식 사양](https://aaronia.com/en/breitband-antenne-hyperlog7060)

Aaronia LNA는 정확한 모델이 미확인이고, 사용자는 대역별 tunable BPF 3개로 필요한 범위를 지원한다고 설명했다. 아래 계산에는 확인되지 않은 이득·NF·실제 통과폭을 넣지 않았다. 수신기가 이전 기록의 USRP-2940인 경우에만 공통 RF 탐색 범위는 **700 MHz–2.2 GHz**로 좁아진다.

## 1. 먼저 정정할 부분

이전의 “프레임 간 변동 행렬이 high rank”라는 설명은, 모든 세로선이 각기 다른 프레임에서 하나씩 나타나 평균 영상에서 합쳐진다는 뜻이 아니다. 아래 두 행렬을 구별해야 한다.

\[
Y_k\in\mathbb R^{H\times W},\quad
\bar Y=\frac1P\sum_{k=1}^P Y_k,\quad
\Delta Y_k=Y_k-\bar Y.
\]

- 평균 이미지 \(\bar Y\): 반복해서 남는 화면과 고정 세로선이 함께 포함된다.
- 변동 \(\Delta Y_k\): 고정 평균을 제거한 뒤 남는 프레임별 밝기·선 세기·선 폭·미세 위치·잡음 변화다.
- 이전 LG X2 effective rank 108.64는 선택한 119개 column에서 \(\Delta Y_k\)를 쌓은 `(frame × row) × candidate-column` 행렬의 값이다. 전체 평균 이미지의 공간 rank나 전체 간섭원 개수와 같은 수치가 아니다.

같은 column에 있는 선들의 세기가 독립적으로 조금씩 변하고 각 픽셀에 잡음이 있어도 변동 행렬은 high rank가 될 수 있다. 평균을 제거해 고정 성분을 지웠다는 사실만으로 source가 분리되지는 않는다.

### 기존 40프레임에서 직접 확인한 결과

각 정렬 log-AM frame을 row 방향으로 평균하고, column profile에서 61-column 이동평균을 빼 좁은 세로선 profile을 구했다. 평균 profile의 절댓값이 큰 peak 12개를 5 column 이상 떨어지게 선택했다.

| 기종 | 각 frame profile과 평균 profile의 상관계수 중앙값 | 선택한 12개 peak의 동일 부호 출현율 최솟값 | 평균 진폭의 절반 이상인 frame 비율 최솟값 |
|---|---:|---:|---:|
| LG X2 | 0.790 | 92.5% | 80.0% |
| Galaxy 171.5 MHz | 0.948 | 100% | 92.5% |
| iPhone 6s | 0.980 | 100% | 95.0% |

**주요 세로선은 같은 위치에서 반복되고, 그 위에 변동이 겹친다.** LG X2는 다른 두 기종보다 변동이 크다. 이 통계는 정렬 후 row-average profile에 대한 것으로, 모든 약한 선이 매 프레임 같은 진폭으로 존재한다거나 각 픽셀의 선이 동일하다는 주장은 아니다. 화면 자체의 column 구조도 profile에 포함될 수 있다.

- [LG X2 프레임별 profile](lgx2_frame_stripes.png)
- [Galaxy 프레임별 profile](galaxy_s4_lte_171p5M_frame_stripes.png)
- [iPhone 프레임별 profile](iphone6s_frame_stripes.png)

위 그림 A는 frame별 profile, B는 같은 profile에서 40-frame 평균을 뺀 변동이다. B는 작은 변동을 보기 위해 별도 대비를 적용했으므로 A/B 색 강도를 직접 비교하면 안 된다.

## 2. 왜 원하는 common-mode만 분리하지 못했나

같은 무늬 \(b(x)\)의 세로선이 모든 row에 반복되면

\[
I=\mathbf1_H b^T,\qquad \operatorname{rank}(I)=1.
\]

선이 100개 있어도 이 모델의 rank는 1이다. 서로 다른 row 방향 진폭 모양을 가진 몇 묶음이면 그 수에 해당하는 rank가 추가된다. 따라서 세로선은 RPCA의 저랭크 \(L\)에 들어갈 수 있고, 작은 글자·가는 윤곽은 희소 \(S\)나 잔차로 빠질 수 있다.

Frame×pixel 표현에서도 정적 화면과 고정 간섭은 모두 temporal signature \(\mathbf1_P\)를 가진다. 이 signature에 맞춘 matched estimator는 둘 다 보존한다. 공간 matched 실험에서는 \(H\)를 순수 common-mode 기준 측정으로 얻지 못해 RPCA 결과에서 학습했으므로, \(H\)에도 세로선이 섞였다. 이 결과는 검증된 목표 신호 기준을 사용하는 matched subspace 전반의 실패를 뜻하지 않는다.

또한 LPDA 한 채널이 수신하는 것은 여러 전류원의 장이 합쳐진 값이다. Common-mode라는 전기적 정의 자체가 낮은 영상 rank나 고유한 주파수 표식을 보장하지 않는다. 의도한 DSI 누설과 panel/전원/clock 간섭 모두 common-mode 방사일 수 있다. \(|s+i|\)와 \(\log|s+i|\)는 \(s\)와 \(i\)의 선형 합도 아니다. 기존 영상 분해는 물리 전류 성분의 직접 분해가 아니다.

BPF는 목표와 간섭의 주파수가 분리돼 있을 때 유효하다. 같은 통과대역에 겹친 성분은 함께 남는다. 챔버도 외부 유입을 줄일 뿐, 기기 내부의 다른 방사원을 제거하지 않는다. 더 나은 목표 subspace에는 알려진 화면 패턴·차동/공통모드 기준 측정·공간/편파가 다른 동시 수신 등 추가 식별 정보가 필요하다.

## 3. 붙여준 교재 식과 차동→공통모드 변환

붙여준 교재 3.2.1–3.2.2의 식은, 주기 \(T\), 진폭 \(A\), 50% 폭 \(\tau\), 동일한 0–100% 선형 rise/fall time \(t_r\)인 trapezoidal pulse train에 대해

\[
|c_n^+|=2A\frac{\tau}{T}
\left|\operatorname{sinc}(n\tau/T)\right|
\left|\operatorname{sinc}(nt_r/T)\right|,
\quad \operatorname{sinc}(x)=\frac{\sin\pi x}{\pi x}
\]

를 준다. 이는 **전압 파형의 고조파 진폭**이며, 안테나가 받는 전력의 완성된 식은 아니다. 전력/PSD에서는 해당 진폭 계수의 절댓값 제곱이 들어간다. 이상적인 50% duty와 대칭 edge 조건에서는 clock의 짝수 고조파가 사라지지만 실제 비대칭·duty 오차는 이를 바꾼다. Data lane에는 실제 pixel/packet bit sequence가 있으므로 전체 data spectrum을 순수 clock의 홀수 고조파만으로 나타낼 수 없다.

Common-mode 전압과 differential 전압의 정의는

\[
v_{CM}=\frac{v_P+v_N}{2},\qquad v_{DM}=v_P-v_N
\]

이다. 예를 들어 DC bias를 제외한 두 선이 \(v_P(t)=a(t)\), \(v_N(t)=-a(t-\Delta t)\)이면

\[
V_{CM}(f)=\frac{1-e^{-j2\pi f\Delta t}}2 A(f)
\simeq j\pi f\Delta t\,A(f)\quad (2\pi f\Delta t\ll1).
\]

시간 skew 하나만으로도 주파수에 의존하는 변환 항이 생긴다. 이는 하나의 예이며 실제 변환은 amplitude/impedance/return path/connector 불균형까지 포함한다. \(t_r=t_f\) 가정과 P/N의 완벽한 일치 가정은 서로 다르다. MIPI 기기라는 이유만으로 둘 다 성립하지 않는다. 제조사의 설명도 differential pair의 skew·edge·진폭 불일치가 방사를 증가시킬 수 있다고 명시한다. [TI Clock Conditioner Owner’s Manual, §6](https://www.ti.com/lit/ug/snaa103/snaa103.pdf)

전체 경로는 개념적으로

\[
I_{CM}(f)=H_{V_{DM}\to I_{CM}}(f)V_{DM}(f)+I_{CM,\mathrm{other}}(f),
\]
\[
V_{RX}(f)=H_{\mathrm{antenna+propagation}}(f)
H_{\mathrm{radiation}}(f)I_{CM}(f)
H_{\mathrm{BPF}}(f)G_{\mathrm{LNA+RX}}(f)+N(f).
\]

전기적으로 짧은 common-mode 방사체의 단순 모델에서는 장 세기가 대략 \(f I_{CM}\ell/r\)에 비례할 수 있으나, 공진 영역이나 실제 스마트폰 chassis에는 이 비례를 그대로 외삽할 수 없다. [TI EMI Fundamentals](https://focus.ti.com/lit/ug/spru889/spru889.pdf)

따라서 해상도·DDR·rise time만으로 최적 수신 중심주파수 하나를 결정할 수 없다. Clock harmonic이 강하다는 사실과 화면 정보가 강하다는 사실도 동일하지 않다. 화면 의존 sideband/변조가 있는지를 확인해야 한다. 단순 선형 DM→CM 변환은 입력에 없던 새 주파수를 생성하는 주파수 변환기도 아니다.

### Rise/fall 정의를 통일한 edge corner 예시

교재는 0–100%, D-PHY 자료는 20–80%를 사용한다. 선형 trapezoid 가정에서

\[
t_{20-80}=0.6t_{0-100},\qquad
f_{edge}=\frac{1}{\pi t_{0-100}}=\frac{0.6}{\pi t_{20-80}}.
\]

| 가정한 D-PHY 20–80% rise time | 선형 0–100% 환산 | 교재의 점근선 교차 corner |
|---:|---:|---:|
| 50 ps | 83.3 ps | 3.82 GHz |
| 100 ps | 166.7 ps | 1.91 GHz |
| 200 ps | 333.3 ps | 0.955 GHz |
| 300 ps | 500 ps | 0.637 GHz |

이들은 휴대폰별 실측값이 아닌 민감도 예시다. Corner는 방사가 사라지는 cutoff 또는 필터의 -3 dB 주파수가 아니다. 과거 문서에서 20–80% D-PHY 수치를 교재 0–100% 식에 그대로 대입한 예시는 같은 정의로 환산해야 한다. D-PHY 자료는 rise/fall 허용 범위를 제시하지만 두 값의 정확한 동일성을 보장하지 않는다. [MIPI/Synopsys DevCon 2017, pp. 7–8](https://www.mipi.org/hubfs/2017%20DevCon%20Hsinchu%20City/Hsinchu-Synopsys-Enabling-Higher-Data-Rates.pdf)

## 4. 기존에 실제 복원한 수신 조건

| 기종 | RF 중심 | 파일명/기록상의 nominal BW | 저장 complex IQ rate | 복원 line rate | 과거 자료의 역할 |
|---|---:|---:|---:|---:|---|
| LG X2(2019) | 344.8 MHz | 60 MHz | 136.565510 MS/s | 88.679653 kHz | 주 기준 |
| Galaxy S4 LTE | 171.5 MHz | 20 MHz | 55.816790 MS/s | 116.153425 kHz | 화면 가독성이 있는 주 기준 |
| iPhone 6s | 311 MHz | 20 MHz | 55.054870 MS/s | 112.613234 kHz | 주 기준 |
| Galaxy S4 LTE 추가 대조 | 111.9 MHz | 20 MHz | 110.891050 MS/s | 116.153241 kHz | 기존에 더 약한 화면 성분 |

기존 자료는 magnetic probe 수집 계열이다. LPDA의 공간 결합·편파·거리·안테나 응답이 달라 동일 중심이 최적이라는 보장은 없다. LG 230 MHz의 과거 측정도 있으나 344.8 MHz보다 약한 것으로 기록됐다. 파일명의 BW는 실제 RF/IF 전달함수의 측정된 -3 dB 폭과 동일하다고 확정할 수 없다. 특히 기존 124/136 MS/s 자료에는 파일명에 대응하는 뚜렷한 roll-off가 없었다. 오늘은 장비 설정과 실제 filter passband/ENBW를 같이 기록해야 한다.

기존 로그에서 LG의 +8 MHz offset, 즉 약 352.8 MHz 중심 16 MHz subband가 상대적으로 선명한 관찰도 있었다. 이는 probe 기반 과거 관찰이며 해당 저주파 대역을 지원하는 수신 경로에서 재확인할 보조 후보다. Galaxy의 +16 MHz subband(약 187.5 MHz)와 iPhone의 +4 MHz subband(약 315 MHz)는 line-rate prominence 후보였으며 가독성 최고 대역으로 검증된 값은 아니다. 모두 HyperLOG 7060 정격 밖이므로 오늘 LPDA 후보와 구별한다.

## 5. 해상도·주사율로 계산할 수 있는 비트율

기존 복원 timing은 약 60 Hz다. RGB888, 압축 없음, 매 주사마다 전체 화면 전송을 가정하면 활성 화면 payload는

\[
R_{payload}=W H f_V\times24.
\]

Lane 수 \(N\)에 대해 \(R_{lane}\ge R_{payload}/N\), 기존 forwarded-clock DDR D-PHY에서는 \(f_{CLK}=R_{lane}/2\)다. DDR는 이미 계산한 data rate를 다시 두 배로 만드는 항이 아니다. ST는 lane rate·lane 수·bits per pixel의 관계 및 burst 전송이 pixel clock보다 빠르게 동작할 수 있음을 설명한다. [ST AN4860](https://www.st.com/resource/en/application_note/dm00287601.pdf), [ST DSI 모드 설명](https://wiki.st.com/stm32mpu/wiki/DSI_internal_peripheral), [TI D-PHY half-rate clock 설명](https://www.ti.com/de/lit/gpn/ds90ub940n-q1)

| 기종 | 활성 해상도 × 60 Hz | 활성 payload, 전체 lane 합 | 4 data lanes 가정: 최소 lane rate | 해당 최소 DDR clock |
|---|---|---:|---:|---:|
| LG X2 | 720×1440 | 1.493 Gbit/s | 373.25 Mbit/s | 186.62 MHz |
| Galaxy S4 LTE | 1080×1920 | 2.986 Gbit/s | 746.50 Mbit/s | 373.25 MHz |
| iPhone 6s | 750×1334 | 1.441 Gbit/s | 360.18 Mbit/s | 180.09 MHz |

해상도 근거: [LG 2019 X2 공식 제원](https://www.lg.co.kr/media/release/20860), [Samsung S4 공식 제원](https://www.samsung.com/in/support/mobile-devices/what-type-of-display-is-used-in-samsung-galaxy-s4/), [Apple iPhone 6s 공식 제원](https://support.apple.com/en-mt/111952).

실제 lane 수, RGB coding, packet overhead, blanking, HS duty/burst, command/video mode, compression 여부는 해당 기기 설정에서 확인하지 못했다. **표의 clock은 실제 측정 clock이 아니다.** 2 data lanes라면 표의 lane rate와 clock은 두 배다. Command mode에서 정지 화면을 매 frame 재전송하지 않는다면 활성 payload 가정부터 달라진다. 공식 화면 해상도는 serial link 설정을 확정해 주지 않는다.

## 6. 오늘 사용할 RF 중심주파수 탐색 후보

HyperLOG 7060의 정격 안에서 후보를 잡기 위해 아래 **명시적인 가정 시나리오**를 사용한다. 기존 중심 344.8 / 171.5 / 311 MHz의 재현은 해당 대역용 안테나/probe가 있을 때 별도로 수행한다.

\[
R_{lane}=\alpha\frac{WHf_V\,24}{4},\qquad 1\le\alpha\le1.5.
\]

여기서 alpha는 활성 payload 대비 실제 HS serialization 속도의 여유/overhead/burst를 묶어 놓은 실험 계획용 인자다. 1–1.5는 측정된 범위나 엄격한 상한이 아니다. 이 가정이 틀리면 실제 peak는 창 밖에 있을 수 있으므로 전체 sweep을 생략하면 안 된다.

| 기종 | 4-lane clock 후보 창 | 3차 clock harmonic 가정 창 | 5차 clock harmonic 가정 창 |
|---|---:|---:|---:|
| LG X2 | 187–280 MHz | 560–840 MHz | 933–1400 MHz |
| Galaxy S4 LTE | 373–560 MHz | 1120–1680 MHz | 1866–2800 MHz |
| iPhone 6s | 180–270 MHz | 540–810 MHz | 900–1351 MHz |

짝수 harmonic 및 data-dependent 연속 spectrum도 확인한다. 표는 이상적 clock 모델에 기초한 우선 탐색 창이다. 기존 344.8/171.5/311 MHz를 clock fundamental이라고 확인한 것이 아니므로 이 수들을 무조건 3배·5배 해서 D-PHY harmonic이라고 명명하지 않는다.

### HyperLOG 7060 + USRP-2940 조건으로 제한한 후보

| 기종 | 4-lane 시나리오: 먼저 자세히 볼 RF 구간 | 짝수 harmonic도 포함한 보완 구간 | 추가 가정에 따른 탐색 기준점 |
|---|---|---|---|
| LG X2 | 700–840 MHz, 933–1400 MHz | 746–1120 MHz | 약 816, 1359 MHz |
| Galaxy S4 LTE | 1120–1680 MHz, 1866–2200 MHz | 746–1120 MHz, 1493–2200 MHz | 약 1256, 2093 MHz |
| iPhone 6s | 700–810 MHz, 900–1351 MHz | 720–1081 MHz | 약 760, 1267 MHz |

이 표의 RF 구간은 모델상 성분을 찾아볼 구간이며 고정 BPF 폭이 아니다. 기준점은 아래 geometry 가정에서 나온 값으로 실측 peak나 최적 중심을 뜻하지 않는다. 2-lane일 때는 원래 시나리오의 주파수가 두 배가 되므로, 전체 700–2200 MHz sweep을 함께 수행한다. 전체 RF 폭 40 MHz를 정격 안에 두려면 중심은 720–2180 MHz, 폭 80 MHz라면 740–2160 MHz 안에 둔다. 실제 filter transition 여유가 필요하면 경계에서 더 떨어진 중심을 사용한다.

기존 raster geometry를 실제 serialization pixel timing으로까지 가정하면 LG 약 272 MHz, Galaxy 약 419 MHz, iPhone 약 253 MHz의 DDR clock 예시가 나온다. 해당 3차/5차는 LG 약 816/1359 MHz, Galaxy 약 1256/2093 MHz, iPhone 약 760/1267 MHz다. **이것은 추가 가정이 강한 계산 예시이며 정확한 clock 예측으로 사용하지 않는다.** 특히 iPhone은 750-column 전체 line이 pixel serialization 시간이라는 가정, Galaxy는 geometry/ghost의 불확실성이 있다. 수치는 `conditional_geometry_clock.csv`에 별도로 분리했다.

모델이 불확실하므로 위 수신기 조건에서는 약 700 MHz–2.2 GHz를 겹치는 수신 창으로 훑고, 위 후보 창을 먼저 자세히 본다. 2-lane 시나리오는 최초 표의 모든 창을 두 배로 옮긴다. 예를 들어 iPhone의 3차 창은 약 1.08–1.62 GHz가 된다. 따라서 1 GHz 이상을 배제할 이유는 없다. 2.2 GHz보다 높은 주파수까지 지원하는 다른 수신기를 쓴다면 LNA/BPF와 교집합을 확인해 HyperLOG의 6 GHz 상한 안에서 탐색을 확장할 수 있다.

이전 기록의 수신기가 USRP-2940이라면 공식 RF 범위는 50 MHz–2.2 GHz다. Galaxy의 5차 창 중 2.2 GHz 초과는 해당 수신기로 직접 측정할 수 없다. 40 MHz/120 MHz 모델에 따라 instantaneous BW도 다르다. **오늘 수신기 모델은 아직 확인되지 않았으므로 2.2 GHz 상한은 조건부다.** HyperLOG 7060 모델은 사용자 답변으로 확인했고, LNA/BPF의 구체적인 정격값은 미확인이다. [NI USRP-2940 사양](https://download.ni.com/support/manuals/374192d.pdf)

## 7. 수신 BPF/디지털 LPF 대역폭 후보

이 문서의 \(B_{RF}\)는 **중심 양쪽을 합친 전체 RF 통과폭**이다. 예를 들어 \(f_c=1.25\) GHz, \(B_{RF}=40\) MHz이면 1.23–1.27 GHz이고, baseband는 대략 ±20 MHz다. Filter transition band와 실제 -3 dB/flat/stop-edge 정의는 별도로 기록한다.

| 기종 | 오늘 먼저 비교할 전체 RF 폭 | 좁은 대역 대조 | 추가 넓은 대역 |
|---|---|---|---|
| LG X2 | 20, 40, 60 MHz | 5, 10 MHz | 80 MHz, 지원 시 100 MHz |
| Galaxy S4 LTE | 40, 60, 80 MHz | 5, 10, 20 MHz | 지원 시 100 MHz |
| iPhone 6s | 20, 40, 60 MHz | 5, 10 MHz | 80 MHz, 지원 시 100 MHz |

이는 최적 BW 확정값이 아니라 **SNR과 세부 윤곽의 손실을 비교할 sweep 후보**다. 각 중심에서 실제 analog/RF passband가 충분히 넓은 IQ를 한 번 저장하고, 동일 IQ에 5/10/20/40/60/80/100 MHz 디지털 필터를 적용하면 시간 변동을 줄여 비교할 수 있다. 외부 BPF를 좁혀서 이미 잃은 sideband는 디지털 처리로 다시 생기지 않는다.

USRP-2940 40 MHz 모델이라면 60/80/100 MHz 동시 수집은 지원하지 않으므로 표의 넓은 대역 비교는 120 MHz 모델 등 지원 수신기에서만 수행한다. 대역별 BPF 3개는 각 수신 주파수에 맞는 것을 선택한다. 실제 여러 필터를 직렬 연결할 경우 통과대역은 각 필터 통과대역의 교집합에 의해 제한되고, 삽입손실은 더해진다. 넓은 BW 비교 시 cascade 전체의 실제 amplitude/phase 응답을 기준으로 판단한다.

Complex IQ sample rate는 최소 전체 complex BW보다 높아야 하며 filter transition 여유가 필요하다. 예를 들어 지원되는 rate 중 \(f_s\gtrsim1.25B_{RF}\)를 계획상의 여유로 둘 수 있다. 이것은 RF carrier가 1 GHz이므로 IQ도 2 GS/s여야 한다는 뜻이 아니다. RF mixer가 해당 대역을 baseband로 내린다.

### 왜 Galaxy에서 더 넓은 대역도 우선 시험하나

단순한 centered double-sideband AM 모델에서 한쪽 envelope 주파수 \(b\)를 보존하려면 \(B_{RF}\gtrsim2b\)다. Pixel timing \(f_p\)에서 가로 \(p\) pixel을 한 주기로 하는 무늬는 \(b=f_p/p\)이므로

\[
p\gtrsim\frac{2f_p}{B_{RF}}.
\]

이는 모델상의 sinusoidal period 척도이며 실제 해상도의 엄격한 상한/보장값이 아니다. 비선형 검파, 실제 packet mapping, transition band, SNR, frame 동기 오차가 영향을 준다.

| 전체 RF BW | LG f_p≈90.63 Mpixel/s | Galaxy f_p≈139.53 Mpixel/s | iPhone f_p≈84.46 Mpixel/s |
|---:|---:|---:|---:|
| 10 MHz | 18.13 pixel/주기 | 27.91 pixel/주기 | 16.89 pixel/주기 |
| 20 MHz | 9.06 | 13.95 | 8.45 |
| 40 MHz | 4.53 | 6.98 | 4.22 |
| 60 MHz | 3.02 | 4.65 | 2.82 |
| 80 MHz | 2.27 | 3.49 | 2.11 |

여기서 pixel timing은 기존 raster geometry로부터 얻은 근사치다. 실제 lane rate 측정값이 아니며 화면 bit decoding 해상도를 주장하지 않는다. 큰 중심주파수와 넓은 modulation BW는 서로 다른 조건이다. 1.5 GHz에서 5 MHz만 남기면 그 주위의 좁은 정보만 남는다. 고조파로 이동했다는 이유로 윤곽 손실이 자동 복구되지는 않는다.

## 8. ES 과제의 '5 MHz'를 코드로 확인

확인한 파일:

- `external/es-coursework/make_bandwidth_sweep.py`
- `external/es-coursework/coherent_tempest.py`, `raised_cosine_response`
- `bandwidth_sweep/fc742p5_bandwidth_metrics.json`

LPF 5 MHz의 설정은 beta=0.25 raised cosine이며 다음과 같다.

- |baseband f|≤3 MHz: flat passband
- 3<|f|<5 MHz: transition
- |f|≥5 MHz: zero
- 전체 flat 폭=6 MHz, 전체 nonzero support 폭=10 MHz
- 해당 실험의 pixel rate≈148.5 MHz

따라서 약 49.5 pixel/주기(148.5/3)까지는 flat, 약 29.7 pixel/주기(148.5/5)는 stop edge다. 더 짧은 주기의 글자 내부/윤곽 구조가 크게 줄어드는 것은 후처리 대역제한으로 설명할 수 있다. 이 관찰은 D-PHY source rise/fall corner가 5 MHz라는 증거가 아니며, LVDS/FPD-Link 실험의 임계 폭을 휴대폰 DSI에 그대로 옮길 근거도 아니다. 휴대폰은 각 pixel timing/누설 mapping으로 다시 비교해야 한다.

## 9. LPDA에서 고주파는 더 멀리 가나

고주파라는 이유만으로 더 멀리 전파되지 않는다. 원거리·자유공간·편파/정합 이상 조건에서

\[
P_r=P_tG_tG_r\left(\frac{\lambda}{4\pi r}\right)^2.
\]

동일 송신 전력과 동일 송수신 안테나 gain을 고정하면 주파수를 두 배 높일 때 수신 전력은 약 6 dB 낮아진다. Free-space 파가 주파수에 비례해 더 흡수된다는 의미가 아니라 gain을 고정했을 때 수신 유효 면적이 \(\lambda^2\)에 비례한다는 관점도 포함된다. 같은 EIRP의 원거리 전력밀도 자체는 \(1/r^2\)로 감소한다. [Analog Devices의 Friis 식 설명](https://www.analog.com/en/resources/technical-articles/why-millimeter-wave-requires-a-different-approach.html)

스마트폰 방사는 동일 \(P_tG_t\) 조건이 아니다. 고주파에서 DM→CM 변환, 케이블/기판/chassis 공진, source edge spectrum, 안테나 gain/AF가 달라져 더 큰 수신값이 나올 수 있다. 이는 source/안테나 응답이 유리한 경우다. LPDA의 지원 주파수, antenna factor, 편파, coax loss, LNA gain/NF를 보정해 비교해야 한다. 근접장 probe 결과와 원거리 LPDA 결과도 그대로 등치하지 않는다.

DC도 구별한다. RF 1 GHz는 물리적인 DC가 아니다. SDR를 1 GHz에 tune하면 그 주위가 baseband DC 부근으로 내려오므로 RF 300 MHz와 RF 1.5 GHz 모두 각각 baseband DC 주변에서 분석할 수 있다.

## 10. 오늘 실험 순서

1. **환경과 수신 설정 고정**: 일정 화면 밝기·주사율·거리·방향. 외부 통신원을 줄이고 DUT는 비행기 모드, Wi-Fi/Bluetooth도 확인. 챔버가 DUT 자신의 무선 송신/전원/패널 간섭을 없애 주지는 않는다. Battery-only와 USB/충전 케이블 연결은 서로 다른 방사 조건으로 기록한다.
2. **수신 범위 설정**: HyperLOG 7060은 700 MHz 이상에서 사용한다. 이전 USRP-2940을 쓴다면 2.2 GHz까지 탐색한다. 344.8 / 171.5 / 311 MHz 재현은 별도 저주파 안테나 또는 기존 probe가 있을 때 수행한다.
3. **대역 탐색**: 위 조건에서 700–2200 MHz를 겹치는 창으로 스캔한다. 전체 BW 40 MHz면 중심 720–2180 MHz를 20 MHz 간격으로 훑는 방법이 있다. 위 기종별 후보 구간을 우선 확인한다. 짧은 IQ로 후보를 찾고 최종 후보에서 1–3초 이상 저장한다. 60/80/100 MHz 비교는 수신기와 RF chain이 동시 지원하는 경우만 수행한다.
4. **화면 의존성으로 선택**: 같은 위치에서 서로 다른 알려진 고정 화면 A/B, 가로/세로 막대 또는 글자 패턴을 수집한다. 총 RF power나 line-rate peak만으로 최고 대역을 고르지 말고, 화면 변경에 따른 성분 변화와 실제 윤곽 보존을 함께 본다. Pattern A/B 반응은 화면 관련성의 근거이며 DSI 전류의 독점적 증거는 아니다.
5. **동일 IQ의 BW sweep**: 5/10/20/40/60/80/(100) MHz를 동일 filter family로 적용하고 화면/제거 성분 및 독립 반복 구간을 비교한다. 모든 필터의 전체폭/한쪽폭/flat/stop을 명시한다.
6. **물리적 source 확인**: 후보 대역이 잡히면 가능할 때 lane clock 설정/기준 신호 또는 국소 probe 관측과 대응시킨다. 순수 common-mode reference가 생기면 matched subspace의 H를 그 기준으로 구성한다.

강한 대역외 신호가 front end를 압축시키는 경우 수신 BPF를 LNA 앞에 두면 도움될 수 있다. 반대로 매우 약한 신호에서는 BPF insertion loss가 noise figure를 악화시키므로 “BPF를 달면 항상 SNR이 좋아진다”는 가정은 하지 않는다. 모든 비교에서 gain/AGC와 filter insertion loss를 기록한다. 여기의 BPF는 수신 경로에 적용하는 것이며 DSI 송신 파형을 변형하는 실험과 구별한다.

## 계산 및 재현 파일

- `../chamber_analysis.py`: 기존 frame profile 진단 및 후보 계산
- `calculations.json`: 전체 계산값과 가정
- `bitrate_and_prior_capture.csv`: payload/lane/clock 하한 및 기존 수신 조건
- `conditional_clock_search_windows.csv`: 4-lane/2-lane, 1–5차 시나리오
- `hardware_aware_candidates.csv`: HyperLOG 7060 + 조건부 USRP-2940 범위에 제한한 후보
- `receiver_center_limits.csv`: 전체 RF 폭별 정격 내 중심주파수 범위
- `conditional_geometry_clock.csv`: geometry→serialization 추가 가정 예시
- `bandwidth_detail_scale.csv`: 전체 RF 폭과 sinusoidal pixel period의 관계
- `edge_corner_examples.csv`: 동일 rise-time 정의로 환산한 corner

이 문서는 오늘 새로 수행한 RF 측정 결과가 아니다. 기존 capture와 기록의 재분석, 공식 자료, 명시적 가정에 따른 실험 계획이다.
