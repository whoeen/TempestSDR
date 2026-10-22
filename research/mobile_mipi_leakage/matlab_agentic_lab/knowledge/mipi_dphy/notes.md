# MIPI DSI / D-PHY 연구 노트 — 조사 사이클 001 + 002

작성: 2026-10-22 KST · 담당: `mipi_dphy_research` · 상태: **문헌 및 공개 소스 조사**

이 노트의 A7 수치는 수집 IQ를 분석한 측정값이 아니다. 제조사 사양, 공개 커널 설정, 명시적 가정에 따른 계산을 구분한다. LG X2, iPhone 6s, Galaxy S4의 설정은 이 수치로 대체하지 않는다.

## 1. 이번에 확인한 범위

검색 가능한 DB는 `sources.jsonl`(9개 출처), `claims.jsonl`(35개 주장), `reading_log.jsonl`(읽은 범위 및 접근 실패), `a7_2018_numeric_examples.json`(단위와 가정 포함 계산)이다. DB의 `kind`는 프로토콜 사실, 소스 설정, 유도식, 가설을 구분한다. `evidence.locator`는 PDF 페이지나 코드 행을 가리킨다. `page_reading_coverage.jsonl`은 아래 두 문서의 **174개 페이지별 현재 독해 상태**를 기록한다. 과거 reading_log의 미독 표시는 당시 이력이며, cycle_002에서 갱신된 현재 상태와 구분한다.

| 자료 | 실제 읽은 범위 | 남은 범위 / 한계 |
|---|---|---|
| MIPI 공식 D-PHY, DSI-2 소개 | Overview, release, access 및 capabilities 해당 섹션 | 최신 규격의 모든 기능을 구형 단말에 적용할 수 없음 |
| MIPI DSI-2 cockpit 발표, 2021 | PDF 1–34의 추출 텍스트, 그림 7–9 시각 확인 | 이미지로만 된 후반부 품질 예시는 전부 판독했다고 주장하지 않음 |
| Tektronix D-PHY datasheet | PDF 1–8 텍스트, p.4 표 시각 확인 | 시험 항목 소개; 규범적 CTS 전체는 아님 |
| TI SLLA104A | PDF 1–9 텍스트, p.6 그림 시각 확인 | 일반 차동 연결의 EMI 설명; 해당 스마트폰의 원인 확정 자료는 아님 |
| Arasan CSI-2/D-PHY 문서 | **PDF 1–55 전체 추출 텍스트**, 선택한 18개 페이지 시각 확인 | 모든 페이지를 시각 전수검사한 것은 아님. CSI-2 패킷을 DSI와 혼동하지 않음 |
| Samsung A7(2018) 발표 | 제품 사양 표와 발표문 | DSI clock 없음 |
| A7 커널 공개 mirror | 패널 파일 전체, board include 및 DSI parser/PLL 관련 발췌 | 기기 펌웨어와 동일한지 미확인 |
| 사용자가 보유한 DSI v1.3 | **PDF 1–119 전체 추출 텍스트**, 선택한 18개 페이지 시각 확인 | 모든 페이지를 시각 전수검사한 것은 아님. 공식 배포본/정오표와의 대조는 미완료 |

첫 사이클의 DSI 36쪽 / Arasan 10쪽에 이어, 같은 날 추가 사이클에서 남은 83쪽 / 45쪽을 실제로 읽었다. 화면 복원 관련성이 낮은 명령, 오류 보고, 호환성, PPI/pad/DFT/BIST 표와 부록도 포함한다. 범위별 검토 내용과 문서 내부 불일치는 `reading_detail.md`에 기록했다. 이것은 **확보한 두 문서의 전체 텍스트 독해**이며 MIPI 또는 TEMPEST 문헌 분야 전체를 학습했다는 뜻이 아니다.

DSI v1.3 본문 인용에서 **인쇄 쪽수 = PDF 쪽수 − 12**이다. 사용자 로컬 문서는 Confidential / All rights reserved로 표시되어 있다. 원본을 이 저장소에 복제하지 않았으며, 위치는 Git에서 제외한 `local_source_paths.json`에만 둔다. 공개 PDF도 공개 다운로드가 재배포 허가를 뜻하지 않으므로 `cache/`, `extracted/` 전체를 Git에서 제외했다.

ST AN4860, AN4511, DSI training, ECMF02 datasheet는 공식 URL에서 다운로드 timeout이 발생했다. 검색 결과의 일부 문장은 자료 발견에만 사용했고 정독 증거로 사용하지 않았다.

## 2. 먼저 나누어야 하는 다섯 주파수

| 기호 | 의미 | 주의점 |
|---|---|---|
| \(R_{lane}\), bit/s | 한 data lane의 직렬 비트율 | 주파수 MHz와 데이터율 Mb/s를 관습적으로 섞지 않는다 |
| \(f_{DDR}\), Hz | forwarded clock lane의 주기 주파수 | 양쪽 edge당 1 bit이므로 \(R_{lane}=2f_{DDR}\) |
| \(f_p\), pixel/s | 일정한 raster를 가정한 pixel clock | lane rate와 다르며 command mode에는 한 가지 전역 값으로 설명하기 어려움 |
| \(f_h,f_v\), Hz | 행 반복, 화면 refresh / frame 반복 | 패널 주사와 host update cadence를 구분해야 함 |
| \(f_c\), Hz | 수신기가 관찰하는 RF 선 또는 대역 중심 | lane clock의 기본파, 고조파, payload 주기성, 다른 회로의 성분 중 무엇인지 검증 필요 |

Forwarded-clock D-PHY의 기본식은 \(R_{lane}=2f_{DDR}\), byte rate는 \(R_{lane}/8\)이다. 근거: [Arasan 공개 문서 §4.4, PDF 27 / 인쇄 21](https://www.arasan.com/wp-content/uploads/2019/08/Total-MIPI-Camera-IP-Solution_CSI-2-v1.3_Aug-2019.pdf). 최신 D-PHY의 embedded-clock 기능은 2018년 단말의 증거가 아니다. [MIPI D-PHY 공식 소개](https://www.mipi.org/specifications/d-phy)

따라서 “DDR과 fp가 Gbps 이상”은 변수를 분리해 재작성해야 한다. lane 데이터율은 Gbit/s 근처 또는 그 이상일 수 있지만 pixel clock은 pixel/s이다. A7 예시의 active pixel rate는 143.856 Mpixel/s이며, 이것을 3.45 Gpixel/s라고 읽으면 안 된다.

## 3. 프로토콜이 만드는 여러 시간축

### HS / LP, video / command, burst

HS는 종단된 차동 전송이고 LP는 종단되지 않은 single-ended 전송이다. 따라서 안테나 수신 신호는 동일한 물리선의 HS, LP 상태 변화와 주변 회로를 함께 포함할 수 있다. [Tektronix p.3](https://download.tek.com/datasheet/D-PHY-Datasheet_61W614877.pdf)

DSI video mode는 화면 timing에 맞춰 pixel stream을 보낸다. Burst video mode에서는 한 행의 데이터 전송을 더 짧게 압축하여 전송하고 나머지 구간을 LP 등으로 사용할 수 있다. Command mode에서는 display controller의 local frame buffer에 갱신 내용을 보내고, 패널 주사는 local timing으로 진행될 수 있다. 단순 raster reshape를 모든 모드에 그대로 적용하면 이 서로 다른 구간이 한 화면에 겹친다. [MIPI 발표 PDF 4,7–10](https://www.mipi.org/hubfs/Automotive-Workshop/How-Use-of-DSI-2-and-Video-Compression-Is-Essential-for-Next-Gen-Digital-Cockpits.pdf)

사용자 로컬 DSI v1.3의 관련 근거는 §4.2(인쇄 12), §5.6(16), §8.11(75–79), §8.12(80–81)이다. 연속 clock과 비연속 clock 지원, HS 구간 사이 LP-11, TE에 따른 update timing을 별도 조건으로 기록해야 한다. TE가 실제 단말에서 별도 pin을 쓰는지는 회로/소스 또는 측정으로 확인해야 하며, in-band TE 설명만으로 단정할 수 없다.

### 패킷과 lane 분배

DSI short packet은 4 byte, long packet은 4-byte header + payload + 2-byte footer이다. 여러 packet을 하나의 HS 전송에 묶을 수 있다. 따라서 packet 길이와 HS burst 길이는 같은 변수가 아니다. 근거: 로컬 DSI v1.3 §8.1–8.5, 인쇄 41–46.

RGB888의 3개 component byte는 lane들에 round-robin으로 배분된다. 4 lane이라고 R/G/B/다른 한 채널이 각각 고정 lane에 놓이지 않는다. 3-byte pixel과 4-lane 주기의 상대 위치, packet header, command byte까지 영향을 준다. 근거: §6 인쇄 19–21, §8.8.23 인쇄 65.

특히 **RGB888 video stream data type 0x3e**와 **DCS Long Write 0x39**를 구분한다. 후자는 command byte를 포함한다. A7 공개 설정이 command mode이므로 처음부터 “모든 이미지 packet은 0x3e”라고 해석하는 디코더는 타당하지 않다. 정확한 command/packet 구성을 추가 확인해야 한다. 근거: §8.8.9.3 인쇄 54, §8.8.23 인쇄 65.

## 4. Galaxy A7 (2018): 출처 설정과 가정 계산

제조사 확인값은 **6.0 inch, 1080×2220, Super AMOLED**이다. LCD가 아니므로 LCD column-driver 모델은 그대로 옮겨오지 않는다. AMOLED에도 주사/데이터 구동 회로는 있지만 구체적인 구동·보상·발광 제어가 다르다. [삼성 제품 사양](https://news.samsung.com/global/widen-your-world-with-the-galaxy-a7)

공개 Samsung-copyright 커널 mirror의 다음 commit을 고정했다.

`97e4fbcdb31efe88b91cd321dae7bbaece36c51a`

[패널 설정 파일](https://github.com/prashantpaddune/android_kernel_samsung_a7y18lte/blob/97e4fbcdb31efe88b91cd321dae7bbaece36c51a/arch/arm64/boot/dts/exynos/display-lcd_a7y18_common.dtsi) 50–68행, 78–81행:

| 설정 | 소스 값 | 해석 |
|---|---:|---|
| panel label | s6e3fa7 | 정확한 장착 부품/firmware 일치 여부는 별도 확인 |
| mode | 2 | 주석상 MIPI command mode |
| resolution | 1080 × 2220 | 삼성 공식 사양과 일치 |
| refresh | 60 | 설정값, 실측 refresh는 아님 |
| lanes | 4 | data lane 수 |
| dsi-hs-clk | 997 | MHz 단위 rate representation으로 처리되는 소스 필드 |
| P, M, S | 3, 230, 1 | PLL 설정 |
| escape clock | 16 | HS rate와 별도 clock |
| h porch | 2, 2, 2 | command transport에서 실제 pixel timing으로 바로 해석하지 않음 |
| v porch | 15, 3, 1 | 동일 주의 |
| MIC, DSC | 모두 0 | 해당 소스 설정에서 비활성 |
| update_min | 360 × 222 | 부분 갱신 granularity 관련 설정; 항상 full frame 전송한다는 뜻이 아님 |

[DSI register driver](https://github.com/prashantpaddune/android_kernel_samsung_a7y18lte/blob/97e4fbcdb31efe88b91cd321dae7bbaece36c51a/drivers/video/fbdev/exynos/dpu_7885/dsim_reg.c) 1240행은 RGB24, 1348행은 `fin=26`, 1371행은 PLL 계산, 1378행은 `/8`, 1381행은 `/16`을 사용한다. 1353–1360행에는 bootloader에서 PLL이 이미 안정화되면 설정을 건너뛰는 경로가 있다. 따라서 이 파일만으로 실제 수집 순간의 PLL을 확정할 수 없다.

이상적인 26 MHz 기준과 이 PMS를 사용하면:

\[
R_{lane}=26\times10^6\frac{230}{3\cdot2^1}
=996.6666667\ {\rm Mb/s}
\]

| 항목 | 계산값 | 분류 |
|---|---:|---|
| lane bit rate | 996.666667 Mb/s | 소스 기반 이상적 PLL 계산 |
| forwarded DDR clock | 498.333333 MHz | 위 값 / 2 |
| byte rate | 124.583333 MHz | 위 값 / 8 |
| full-frame 60 Hz active pixel rate | 143.856 Mpixel/s | 1080×2220×60 가정 |
| full-frame RGB888 payload | 3.452544 Gbit/s total | 24 bit/pixel, overhead 제외 |
| lane당 평균 payload 요구량 | 863.136 Mb/s | 위 값 / 4 |
| HS payload에서 평균 pixel 시간 | 6.02006689 ns | 24 / (4 Rlane) |
| 한 행 payload 최소 시간 | 6.50167224 µs | overhead, gap 제외 |
| 한 frame payload 최소 시간 | 14.4337124 ms | overhead, gap 제외 |
| 60 Hz에서 payload 점유율 | 86.6022742% | full-frame 연속 갱신 가정 |

**997, 996, 996.6667의 차이는 중요하다.** 요청 필드는 997, C 정수 계산의 `hs_clk`는 996, 이상적인 PLL 실수 계산은 996.6667이다. `byte_clk` 정수 변수는 124가 된다. 로그에 정수가 찍힌 것을 발진기 실측값으로 사용하면 안 된다. SSC, 기준 발진기 오차, bootloader 설정은 아직 측정되지 않았다.

참고로 porch를 raster count로 간주하면 Htotal=1086, Vtotal=2239, fh=134.340 kHz, fp=145.89324 MHz이다. **이 값은 조건부 예시**이며 command-mode 전송 행 간격을 증명하지 않는다. 실제 update cadence와 local panel scan은 따로 추정해야 한다.

## 5. 픽셀당 샘플 수와 resampling 해석

일정한 raster를 가정할 때:

\[
n_{s/p}=F_s/f_p,\qquad T_h=1/f_h,\quad T_v=1/f_v.
\]

N개 lane의 압축되지 않은 b-bit pixel payload에 대한 평균 transport 시간 예산은:

\[
T_{p,payload}=\frac{b}{N R_{lane}},\qquad
n_{s/p,payload}=F_s\frac{b}{N R_{lane}}.
\]

이는 여러 lane이 공간적으로 혼합되어 수신되는 상황에서 “독립적으로 관측한 한 pixel”의 시간이나 샘플 수를 보장하지 않는다. packet overhead, HS/LP 전환, 부분 갱신, RF 선택대역, 수신 필터의 impulse response도 반영해야 한다.

A7 계산에서 Fs=20 MHz를 **가정**하면 payload 평균 약 0.120401 sample/pixel이고, Fs=60 MHz를 **가정**하면 약 0.361204 sample/pixel이다. 이는 실제 A7 수집기의 Fs가 아니다. 분수 resampling으로 1 sample/pixel 격자를 만들 수는 있지만 수집 당시 존재하지 않은 독립 정보가 새로 생기는 것은 아니다. 반복 frame의 subpixel offset을 이용하려면 신호 반복성, timing drift, 위상 coherence를 함께 검증해야 한다.

복소 IQ의 Nyquist interval 폭은 Fs이지만, 실제 순간 수신 대역폭은 analog/IF/decimation 필터와 설정을 확인해야 한다. Fs만 보고 3개 device의 순간 대역폭을 단정하지 않는다.

행은 일반적인 raster에서 연속한 시간 구간이다. **한 column은 frame에 걸쳐 행마다 약 Th 간격으로 떨어진 표본들의 집합**이다. 따라서 column의 TF 분석에 row와 같은 연속 sample interval을 부여하면 주파수축이 틀어진다. 이 경우 sample interval을 Th로 둔 column sequence와 원래 IQ의 연속 STFT를 구분해서 출력해야 한다. Command mode에는 먼저 burst-to-pixel mapping이 필요하다.

## 6. fc가 modulation bandwidth보다 매우 클 때

\[
x_{RF}(t)=\Re\{u(t)e^{j2\pi f_ct}\},\quad
u(t)=A_0[1+a(t)]e^{j\phi(t)}.
\]

\(|a|\ll1\), \(|\phi|\ll1\), \(A_0\ne0\)이고 한 성분이 충분히 분리되면:

\[
u(t)\simeq A_0[1+a(t)+j\phi(t)].
\]

이는 검증할 **국소 AM/PM 모델**이다. D-PHY가 모든 수신 지점과 RF 대역에서 작은 AM/PM만 발생시킨다는 보장은 없다. 강한 간섭 성분, envelope zero, 여러 multipath 성분, HS gating 때문에 모델이 무너질 수 있다.

fc≫B인 경우 적절한 LO로 복소 하향변환하여 envelope를 분석한다. 이때 B는 남길 변조 정보의 bandwidth이다. **fh/fv가 낮다는 사실이 B도 낮다는 뜻은 아니다.** row/frame의 반복률은 낮아도 pixel 데이터 전이와 packet/burst edge가 만드는 envelope 성분은 더 빠르다. 좁은 대역만 수집하면 낮은 차원의 화면 특징을 복원할 수 있어도 원본 serial payload 전체를 디코딩할 수 있다는 뜻은 아니다.

처음부터 abs(IQ)로 변환하면 phase 정보가 사라진다. 원본 complex IQ를 보존하고, 독립적인 carrier/CFO 추정값, phase alignment, amplitude normalization을 기록해야 한다. 이 연구에서 HSV hue는 원본 화면 RGB 색상과 같지 않다. 보정 후 IQ phase를 색으로 표시한 진단량이며 global phase offset에 따라 전체 색상이 돌아갈 수 있다.

## 7. Common mode와 방사 가설의 범위

\[
V_{DM}=V_P-V_N,\qquad V_{CM}=(V_P+V_N)/2.
\]

차동 신호의 완전한 대칭이 깨지면 driver, trace, connector, flex, return path의 불균형과 skew가 DM→CM 변환을 만든다. TI 문서는 driver/interconnect imbalance와 time-varying common-mode current를 설명하고, connector skew와 EMI를 연결한다. [TI SLLA104A p.3,5,6](https://www.ti.com/lit/an/slla104a/slla104a.pdf)

단순한 유도 예시로 두 전압을 \(s(t)\), \(-s(t-\tau)\)로 두면 잔류 CM은 \([s(t)-s(t-\tau)]/2\approx(\tau/2)s'(t)\)이다. 작은 skew도 빠른 edge에서 크게 드러날 수 있다. 실제 방사는 전압 평균 하나뿐 아니라 공통 경로 전류, 구조, 주파수, 관측 위치에 의해 결정된다.

Tektronix D-PHY 시험 목록에도 HS static common-mode mismatch, dynamic common-mode variation(50–450 MHz 및 450 MHz 초과) 시험이 있다. 이는 해당 물리량을 측정한다는 근거이며 사용자 capture의 CM 크기나 dominant emitter를 알려주는 수치는 아니다. [Tektronix p.4 시험 1.3.7–1.3.10, p.5 대응 clock 시험](https://download.tek.com/datasheet/D-PHY-Datasheet_61W614877.pdf)

안테나의 단일 IQ 채널은 보통 \(h_{CM}*i_{CM}+h_{DM}*i_{DM}+기타 회로+잡음\)의 혼합이다. 수신 신호가 화면과 상관된다고 해서 “CM만 수집했다”고 확정할 수 없다. 가능한 검증은 probe 위치/방향, cable/connector 근접장 비교, display update와 TE/gating의 시간 상관, 동일 장면에서 밝기 변화, 정지/갱신 조건 변화 등이다. 물리적 driver 직접 측정이나 회로 근거가 있어야 column-driver 가설을 좁힐 수 있다.

## 8. Rank와 세로줄·위상 그라데이션

“MIPI common mode는 low rank이고 panel driver는 high rank”는 아직 분리 조건으로 사용할 수 없다. 행마다 동일한 세로줄 \(s[n]\)이 반복되면 행렬 \(X[m,n]=1[m]s[n]\)은 rank 1이다. 실제 영상도 frame을 열로 쌓으면 정지 화면에서는 낮은 rank가 될 수 있지만, 하나의 복잡한 2D 화면 행렬은 높은 rank일 수 있다. 먼저 행렬의 축과 window를 정해야 한다.

수신 IQ의 residual CFO가 Δf이면:

\[
\Delta\phi_{row}=2\pi\Delta fT_h,\qquad
\Delta\phi_{frame}=2\pi\Delta fT_v.
\]

이 위상 경사가 raster 위에 투영되면 HSV 색상이 행 또는 frame에 따라 순환한다. tone 성분을 \(t=mT_h+nT_p\)에서 관측하면 \(2\pi f(mT_h+nT_p)\)의 위상 평면이 만들어진다. \(fT_h\)가 정수에 가까우면 행 간 반복이 강해져 세로줄처럼 보일 수 있다. timing 오차가 있으면 이 구조가 기울거나 이동한다. 확대 표시와 interpolation은 원래 공간 주파수를 다르게 보이게 할 수 있다.

따라서 원 주변에서 나타나는 선/gradation의 후보는 (1) 패턴과 RF waveform의 데이터 의존성, (2) CFO 또는 시간축 오차, (3) 다른 tone/clutter와의 간섭, (4) 표시 interpolation/HSV mapping, (5) 실제 panel 구동 성분이다. 현재 문헌 조사만으로 어느 하나를 확정하지 않는다.

비교 산출물에는 원본 IQ와 처리 단계마다 amplitude/phase/HSV를 함께 보관한다. 같은 ROI에서 row·column phase gradient, frame별 global phase/CFO, timing shift, coherent power와 incoherent power, 보정 전후 잔차를 수치로 기록한다. envelope가 매우 작은 지점의 phase는 신뢰도가 낮으므로 amplitude 또는 coherence 기준 mask를 함께 표시한다.

## 9. 다음 조사 및 측정 연결

1. **기존 3개 기기 우선:** LG X2, iPhone 6s, Galaxy LTE S4의 실제 모델 번호, panel, host mode, capture metadata를 연결한다. A7는 다음 기기용 근거 예시다.
2. A7 공개 mirror를 Samsung release archive 또는 실제 펌웨어와 대조한다. 현재 commit의 설정은 강한 후보이지만 실측 확정값은 아니다.
3. 확보한 DSI v1.3와 Arasan 문서의 텍스트 독해는 완료했다. 사용자 보유본의 공식 원본/정오표 대조와 문서가 참조하는 D-PHY, DCS, VESA DSC 원문은 정당한 접근 범위 안에서 추가 확인한다.
4. ST common-mode filter 문서의 접근을 재시도하거나 다른 제조사 공개 자료로 CM 변환/필터 위치를 보강한다. 읽지 못한 문서의 내용은 DB 사실로 올리지 않는다.
5. IQ 단계에서 HS burst cadence, row/frame cadence, carrier/CFO를 독립 추정하여 source configuration과 비교한다. frame averaging의 위상 정렬은 target 성분과 clutter 성분을 별도로 점검한다.
6. 원/문자/선 패턴을 바꾸고 위치·밝기·갱신 방식도 통제하여 “패널 구동”과 “DSI payload/clock” 가설을 구분한다. 본 사이클에는 장비 제어 또는 신규 RF 측정을 수행하지 않았다.

## 재현과 검색

`build_knowledge_db.py`는 첫 사이클의 수동 검토 기록을 JSONL로 다시 쓰는 snapshot 생성기다. 현재 상태를 재생성하려면 그 뒤에 `extend_reading_cycle_002.py`도 실행한다. 뒤에 새 기록을 추가했다면 무작정 재실행하지 않는다. 로컬 PDF 경로는 ignored map 또는 `MIPI_DSI_V13_PDF` 환경변수로 읽는다. 모든 JSONL은 UTF-8이다.

예시 검색: `rg 'PLL|command|common_mode' claims.jsonl`.

PDF 원문을 자동 추출했다고 그 페이지를 읽은 것으로 기록하지 않는다. 신규 claim에는 출처, 정확한 locator, 사실/추정 구분, 조건, 읽은 날짜를 함께 추가한다.

## 10. 전체 텍스트 독해 후 추가된 해석 조건

- **Common Mode fault ≠ common-mode 방사.** DSI §7.2.2.2의 전자는 송신 LP / 수신 HS 등 상태 불일치이며, 안테나에서 연구하는 공통모드 전류와 용어가 다르다.
- **HS 길이 ≠ 영상 payload 길이.** Null packet은 HS를 유지할 수 있고 blanking packet payload도 임의 데이터일 수 있다. LP 역방향 제어 전송은 lane 0에서 일어난다. §8.8.11–12, §8.9.
- **18 bpp가 항상 전송 18 bit/pixel은 아니다.** RGB666 packed는 4 pixel / 9 byte, loosely packed는 1 pixel / 3 byte이다. 수신 샘플 수를 계산할 때 화면 색 심도와 wire packing을 나눈다. §8.8.21–22.
- **ECC와 payload 복원능력을 구분한다.** 24-bit header의 ECC와 payload CRC는 범위와 역할이 다르다. 대역 제한된 analog IQ의 누락 정보를 이 코드가 자동 복구해 주는 것은 아니다. §9.
- **HS/LP 전압 swing이 AM 변조도는 아니다.** Arasan의 on-wire 신호 사양으로 안테나 수신 carrier 대비 modulation index를 정할 수 없다. 실제 channel, 반송 성분과 gating을 측정해야 한다.
- **비영상 periodic burst도 후보로 둔다.** Arasan의 deskew calibration 제어 신호가 존재하지만 해당 스마트폰에서 실제로 발생했다는 증거는 아직 없다.

DSI 예시의 CRC polynomial 주석과 30/36-bit packet의 WC 필드에서 본문 규칙과 불일치를 발견했다. 원문 이미지에서도 확인했으므로, 향후 decoder test vector를 만들 때 예시를 무검증으로 복사하지 않는다. 정식 정오표로 확인된 수정이라고 주장하지 않으며 자세한 locator는 `MIPI-028`, `MIPI-029`와 `reading_detail.md`에 남겼다.
