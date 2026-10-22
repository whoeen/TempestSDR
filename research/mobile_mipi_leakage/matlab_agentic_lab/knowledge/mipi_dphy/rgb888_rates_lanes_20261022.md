# RGB888 DSI의 속도·lane 분배·반복성 후보 — 2026-10-22

담당: mipi_rates_lanes · 범위: forwarded-clock D-PHY + 압축하지 않은 RGB888 · 상태: 문헌 재검토 및 수학적 유도. 신규 단말 측정이나 실제 lane-rate 추정은 수행하지 않았다.

## 1. 기호를 먼저 고정한다

이 문서의 `f_b`는 **한 data lane의 serial bit rate를 수치상 Hz로 쓴 bit-clock 변수**이다. 단위가 필요한 표에서는 `R_lane [bit/s]`를 쓴다. 다른 논문에서 `f_b`를 기본 반복 주파수로 쓴다면 아래 식에 그대로 대입하지 않는다.

| 기호 | 정의 | 관계 |
|---|---|---|
| R_lane = f_b | 한 data lane의 HS bit rate | 8 f_byte = 2 f_DDR |
| f_byte | 한 lane에서 한 byte를 내보내는 속도 / byte-interface clock | f_b / 8 |
| f_DDR | forwarded clock lane의 한 주기 주파수 | f_b / 2 = 4 f_byte |
| N R_lane | N개 data lane의 합계 raw bit throughput | aggregate 값이며 한 lane의 bit clock이 아님 |
| f_p,burst | 순수 RGB888 payload 구간의 평균 pixel throughput | N f_b / 24 = N f_byte / 3 |
| f_p,active,avg | 초당 갱신되는 active pixel 수 | 전체 프레임 갱신 가정이면 W H f_update |
| f_c | 수신 RF 중심 주파수 또는 특정 RF 선의 주파수 | 위 clock들과 동일하다고 놓지 않음 |

D-PHY는 clock 양 edge마다 data bit를 전달한다. 한 lane의 byte는 8 bit이므로 위 관계가 나온다. 여러 lane은 공통 clock을 공유한다. 근거: 사용자 보유 DSI v1.3 §6, PDF31–33 / 인쇄19–21; 공개 Arasan 문서 §4.4, PDF27 / 인쇄21 및 Table5, PDF30 / 인쇄24.

RGB888이라는 정보만으로 **절대적인 MHz 값은 정해지지 않는다.** N, 실제 PLL 설정, update cadence, HS duty, packet overhead와 LP 구간이 필요하다. 원하는 RGB throughput이 같을 때 N을 늘리면 필요한 per-lane rate를 낮출 수 있으나, 실제 host가 언제나 같은 비율로 PLL을 낮추는 것은 아니다.

순수 pixel payload가 관측 시간의 비율 eta를 차지한다면:

```text
N f_b eta = 24 W H f_update
f_byte = 3 W H f_update / (N eta)
f_DDR = 12 W H f_update / (N eta)
```

eta는 payload 점유 비율이므로 packet header/footer, HS 시작·끝, blanking/null, LP 및 idle 시간을 모두 제외한다. Command mode에서는 f_update와 패널 f_v가 다를 수 있다. 따라서 해상도와 60 Hz를 곱한 값만으로 lane clock을 확정하지 않는다.

### 공개 소스에 근거한 A7(2018) 예시

기존 데이터베이스에서 고정한 커널 mirror commit은 `97e4fbcdb31efe88b91cd321dae7bbaece36c51a`이다. 이번에 로컬 보관 원문 파일의 해당 행을 다시 읽었다.

- panel 파일 51행: MIPI command mode; 52행:1080×2220; 54행:60 Hz; 57–58행:요청 field997, PMS3/230/1; 68행:data lane4.
- dsim_reg.c 1348행:fin26 MHz; 1371행:PLL 계산; 1378행:byte clock은 hs_clk/8.
- 1353–1360행:bootloader가 PLL을 이미 안정화했다면 재설정을 건너뛸 수 있음.

이상적인 26 MHz 기준에 해당 PMS가 실제 적용되었다는 조건에서:

| 항목 | 값 | 증거 종류 |
|---|---:|---|
| f_b = R_lane | 996.666667 Mbit/s | 소스 기반 유도 |
| f_DDR | 498.333333 MHz | 위 값 / 2 |
| f_byte | 124.583333 MHz | 위 값 / 8 |
| N f_b | 3.986666667 Gbit/s | 4 lane 합계 raw rate |
| f_p,burst | 166.111111 Mpixel/s | RGB888 payload 중 평균 throughput |
| W H ×60 | 143.856 Mpixel/s | 매 refresh 전체 화면 갱신 가정 |
| RGB payload duty eta | 86.602274% | 위 가정, overhead 별도 |
| 4-lane 색 배치 주기율 f_byte/3 | 41.527778 MHz | 아래 §3의 조건부 구조 주기 |

997 요청값, C 정수 연산 결과996, 이상적인 PLL 실수값996.666667을 구분한다. 이 표는 **LG X2 또는 iPhone6의 clock 값이 아니며 A7 실측값도 아니다.** 기존 RF 중심344.8/238 MHz, 수신BW120 MHz, sweep폭150 MHz 중 어느 것도 이 식에 넣을 f_b를 직접 알려주지 않는다.

## 2. Round-robin은 byte 단위이며 HS transmission 전체의 위치를 보존해야 한다

DSI v1.3 §6은 N개의 packet byte를 N개 lane에 병렬 배분한다. 모든 lane은 병렬 SoT로 HS 전송을 시작한다. §8.1은 하나의 HS transmission에 여러 packet이 이어질 수 있다고 설명한다. 따라서 template은 각 packet을 독립적으로 lane0부터 시작한다고 가정하면 안 된다.

HS 전송에서 첫 protocol byte를 S[0]이라 하고, lane index l=0,...,N−1, byte-clock tick q=0,1,...로 두면:

```text
lane l의 q번째 byte = S[N q + l]
```

첫 R byte가 HS stream의 index a에 있고 이후 payload가 R0,G0,B0,R1,G1,B1,...이면:

```text
j = N q + l
payload 안에서 component index = (j-a) mod 3
pixel index = floor((j-a)/3)
component index 0,1,2 = R,G,B
```

a에는 **앞선 packet들 전체 길이, 현재 header4 byte, DCS command byte 등이 포함**된다. SoT sync는 PHY 각 lane에서 병렬로 이루어지는 동작이므로 protocol byte stream에 단일 byte로 삽입하여 round-robin하면 안 된다.

RGB888 video packet은 R,G,B의 순서이고 각 component byte 안에서는 LSB가 먼저 전송된다. 근거: §8.8.23, PDF77 / 인쇄65. DCS long write에서 color data를 전송하는 경우에는 DCS의 선택된 pixel format과 명령을 별도로 확인해야 한다.

## 3. Lane 수별 RGB888 배치

다음 표는 설명을 위해 첫 payload R0가 lane0의 byte 경계에 놓이는 경우이다. 실제 배치는 위 a offset으로 회전한다.

### 1 lane

| byte tick | lane0 |
|---:|---|
| 0 | R0 |
| 1 | G0 |
| 2 | B0 |
| 3 | R1 |

### 2 lanes

| byte tick | lane0 | lane1 |
|---:|---|---|
| 0 | R0 | G0 |
| 1 | B0 | R1 |
| 2 | G1 | B1 |
| 3 | R2 | G2 |

각 lane에 RGB가 고정되지 않는다. 3 byte tick마다 배치가 반복되며 이 동안 2 pixel이 전달된다.

### 3 lanes

| byte tick | lane0 | lane1 | lane2 |
|---:|---|---|---|
| 0 | R0 | G0 | B0 |
| 1 | R1 | G1 | B1 |
| 2 | R2 | G2 | B2 |

이 조건에서는 component가 lane에 고정된다. 하지만 SoT 바로 다음의 4-byte video header를 포함하면 payload R0의 index는 a=4이다. 따라서 실제 고정 대응은 lane1=R, lane2=G, lane0=B가 된다. 선행 packet 또는 command byte에 따라 또 회전한다.

### 4 lanes

| byte tick | lane0 | lane1 | lane2 | lane3 |
|---:|---|---|---|---|
| 0 | R0 | G0 | B0 | R1 |
| 1 | G1 | B1 | R2 | G2 |
| 2 | B2 | R3 | G3 | B3 |
| 3 | R4 | G4 | B4 | R5 |

즉 **12 aggregate bytes = 4 pixels = 3 byte-clock ticks**가 component/lane 배치의 한 주기이다. 네 lane이 RGB와 별도의 네 번째 채널에 각각 대응하는 구조가 아니다.

일반화하면:

```text
aggregate-byte 배치 주기 = lcm(3,N)
byte-clock tick 주기 P = 3/gcd(3,N)
pixel 수 M = N/gcd(3,N)
배치 주기율 f_map = f_byte/P
```

| N | aggregate bytes | byte ticks P | pixels M | f_map |
|---:|---:|---:|---:|---|
| 1 | 3 | 3 | 1 | f_byte/3 |
| 2 | 6 | 3 | 2 | f_byte/3 |
| 3 | 3 | 1 | 1 | f_byte |
| 4 | 12 | 3 | 4 | f_byte/3 |

**이것은 배치의 주기이며 임의 영상의 bit waveform이 반복된다는 뜻은 아니다.** R,G,B가 일정하지만 서로 다른 단색 영역에서는 같은 byte 배열이 반복될 수 있다. 회색처럼 R=G=B이면 더 짧은 byte 주기가 될 수 있고, 각 byte의 bit pattern에 따라서도 더 짧아질 수 있다. 0x00 또는0xFF의 지속 구간에는 데이터선 내부 전이가 없을 수 있다. Clock lane, 경계, edge의 DM→CM 변환과 채널 전달함수는 별도로 남는다.

예를 들어 동일 byte의 반복에서 0xAA/0x55는 2 UI, 0x33/0xCC는4 UI, 0xF0/0x0F는8 UI의 데이터 패턴 후보를 만든다. 따라서 각각 f_b/2, f_b/4, f_b/8 및 고조파 주변을 관찰할 근거가 생긴다. 이는 디지털 반복 패턴의 유도이며 실제 공통모드 RF가 그 기본파를 가장 강하게 갖는다고 보장하지 않는다. 통제된 RGB 패턴으로 변화를 확인해야 한다.

## 4. Packet 경계가 lane/color 위상과 저속 반복성에 주는 영향

Long packet은 header4 byte + WC payload + CRC2 byte이다. Short packet은4 byte이다. RGB888 video pixel packet은 DT0x3E이며 한 행 W개 pixel을 한 packet에 담는 경우 WC=3W, 길이 L=3W+6이다. DCS long write(DT0x39)는 command byte가 있으므로, 한 command와 W개 RGB888 pixel만 들어가는 경우 WC=1+3W, L=3W+7이다.

네 lane에서 같은 HS burst 내 다음 packet의 시작 lane은 현재 시작 lane에 L mod4를 더한 값이다. 실제로 한 행=한 packet인지는 아직 확인되지 않았다.

| 조건부 예시 | L [byte] | L mod4 | 이어진 동일 packet의 시작-lane 반복 횟수 |
|---|---:|---:|---:|
| W720, video RGB888 | 2166 | 2 | 2 packets |
| W750, video RGB888 | 2256 | 0 | 1 packet |
| W720, DCS command1 byte + RGB888 | 2167 | 3 | 4 packets |
| W750, DCS command1 byte + RGB888 | 2257 | 1 | 4 packets |

이 값은 예상 화면 폭을 사용한 **가정 예시**이다. Word Count는 active width만으로 확정되지 않으며 packet 분할, ROI, blanking, command packet 또는 padding 정책을 확인해야 한다.

각 packet마다 HS를 종료하고 새 SoT로 시작한다면 시작 lane은 재설정되고 위 누적 회전은 사라진다. 동일 HS 안에서 여러 packet을 묶으면 누적 회전을 고려한다. 마지막 전체 byte 수가 N의 배수가 아니면 일부 lane은 다른 lane보다 한 byte 일찍 종료할 수 있다. 근거: §6.1.3, PDF33–35 / 인쇄21–23.

따라서 반복되는 header가 있을 때 **2행 또는4행 단위의 복소 위상/진폭 가족**도 탐색할 가치가 있다. 다만 packet cadence와 행 cadence의 일치, 같은 packet 길이, lane별 전달함수 차이가 필요한 조건이다. f_h/2 또는f_h/4 근처 성분을 발견했다고 이 원인으로 확정하면 안 된다.

## 5. Stitching에 연결할 관측 모델

단일 antenna IQ는 각 lane의 digital stream을 그 순서대로 읽은 데이터가 아니다. 대략적인 선형 후보 모델은 다음과 같다.

```text
z_b(t) = exp(j theta_b(t)) ×
         [sum_l h_{b,l} * s_l(t - tau_b) + h_{b,clk} * s_clk(t - tau_b)]
         + other emitters + noise
```

b는 수신 subband, h는 주파수에 따른 복소 결합/전달함수, theta_b는 수신기 및 기준과의 위상 오차를 포함한다. 비선형/전이 민감 방사라면 s_l 대신 edge 기반 사전을 비교한다.

- 같은 known header라도 N과 a에 따라 각 lane의 시간 파형이 다르다.
- 같은 template을 모든 RF subband에서 동일한 amplitude/phase로 기대하지 않는다.
- 여러 lane이 같거나 유사한 training sequence를 동시에 내보내면 개별 h_l의 식별성이 낮아질 수 있다. 안정적인 **합성 기준 파형**으로 활용하는 것과 lane별 신호를 분리하는 것은 다른 목표이다.
- payload와 달리 길이/DI/WC가 고정된 packet 영역은 timing·phase reference 후보가 된다. 실제 PHY sync, header, EoTp, row/frame cadence는 서로 구분하여 bank를 만든다.
- header 또는 HS 시작 template만 맞고 영상 payload가 다른 상태일 수 있다. packet 기준 정렬을 적용한 뒤 independent payload/화면 영역에서 coherent consistency가 개선되는지 검증한다.
- 한 픽셀의 serial bit가 N개의 lane에 분산되고 시간상 겹치므로 Fs/f_p,burst는 **평균 시간 예산**이다. 이를 독립 pixel 관측 수로 읽지 않는다.

## 6. 현 시점에 등록할 후보와 구분

| 후보 | 실제로 정의하는 것 | 검증 방법 |
|---|---|---|
| f_DDR 및 고조파 | forwarded clock | 데이터 변화에 대한 독립성, HS gating, clock 지속 여부 비교 |
| f_byte 및 정수분주 | byte/bit 패턴 구조 | 통제된 균일 RGB, byte 반복 패턴, lane 수 후보 비교 |
| f_byte/3 (N1,2,4) | RGB component/lane 배치 주기 | 서로 다른 R,G,B 단색과 회색 대조, 데이터 전이 의존성 확인 |
| packet cadence | fixed DI/WC/ECC 등의 반복 | header 길이/순서와 HS 내 packet offset별 template 비교 |
| HS burst cadence | SoT→HS→EoT→LP 반복 | packet이 여러 개 포함되는지 구분 |
| packet cadence의 1/2,1/4 | lane-start 회전 가능성 | L modN과 HS restart 여부를 동시에 검증 |
| f_h, f_v | 패널 주사 또는 host transport cadence 후보 | video/command 모드와 update timing 분리 |

LG/iPhone6의 실제 f_byte, f_DDR, f_b는 **아직 미상**이다. 먼저 해당 기기의 설정/측정값과 candidate template 적합도를 사용한다. RF 선 하나에 정수배를 붙여 lane clock을 단정하지 않는다.

## 7. 재검토한 원문과 locator

1. 사용자 보유 *Specification for Display Serial Interface (DSI)* v1.3, 2015-03-23. 로컬 경로는 기존 ignored `local_source_paths.json` 참조. 이번 재독: PDF31–35(§6/그림5–9), PDF53–58(§8.1–8.5), PDF77(§8.8.23). 인쇄 쪽수는 PDF−12. 문서는 Confidential/DRAFT 표기를 가지며 공식 배포본 대조는 미완료이다. 여기에는 원문의 재배포 대신 유도식과 해석만 기록했다.
2. [Arasan Total MIPI Camera IP Solution CSI-2 v1.3 (2019)](https://www.arasan.com/wp-content/uploads/2019/08/Total-MIPI-Camera-IP-Solution_CSI-2-v1.3_Aug-2019.pdf): D-PHY 물리층만 참조. §4.4 PDF27, Table5 PDF30. Camera packet protocol을 DSI packet 규칙으로 전용하지 않음.
3. [Samsung-copyright A7 panel 설정의 고정 mirror](https://github.com/prashantpaddune/android_kernel_samsung_a7y18lte/blob/97e4fbcdb31efe88b91cd321dae7bbaece36c51a/arch/arm64/boot/dts/exynos/display-lcd_a7y18_common.dtsi): 50–68행. 실제 기기 firmware 동일성 미확인.
4. [동일 commit의 dsim_reg.c](https://github.com/prashantpaddune/android_kernel_samsung_a7y18lte/blob/97e4fbcdb31efe88b91cd321dae7bbaece36c51a/drivers/video/fbdev/exynos/dpu_7885/dsim_reg.c): 1341–1382행.
5. [MIPI D-PHY 공식 개요](https://www.mipi.org/specifications/d-phy): 현재 embedded-clock 옵션과 구형 forwarded-clock 대상 범위를 구분. 현재 세대의 최대 속도나 기능을 기존 스마트폰의 설정으로 읽지 않는다.

읽기 방식: 로컬 PDF 선택 페이지의 추출 텍스트를 직접 읽고 기존 수식/소스 행을 대조했다. 본 추가 노트는 전체 D-PHY 규격을 새로 읽었다는 주장이 아니다. 신규 실측, 실제 스마트폰 packet 디코딩, MATLAB 실행 또는 복원 성능 검증은 포함하지 않는다.
