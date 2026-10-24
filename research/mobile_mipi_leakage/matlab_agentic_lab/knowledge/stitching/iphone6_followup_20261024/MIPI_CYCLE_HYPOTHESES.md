# iPhone 6: MIPI lane 수와 RGB888 주기 후보

작성일: 2026-10-24. 범위: 문헌 검토와 byte-level 수학적 유도. 이 노트에서 IQ DSP, MATLAB 실행, 새 측정은 하지 않았다. 원본 화면은 알려진 실험 패턴이며, packet decode 결과가 아니다. 출처·열람 범위·접근 실패는 [MIPI_CYCLE_SOURCES.json](MIPI_CYCLE_SOURCES.json)에 기록했다.

## 1. iPhone 6는 몇 lane인가?

**현재 근거에서는 3 data lanes + 1 clock lane을 우선 가설로 삼는 것이 타당하다. 실제 측정 단말의 활성 lane 수를 확인한 상태는 아니다. 'iPhone 6는 확정적으로 4 data lanes'라는 전제는 사용하지 않는다.**

| 항목 | 확인 상태 | 분석에서의 사용 |
|---|---|---|
| iPhone 6 화면 1334×750, IPS | Apple 공식 사양 | active 화면 크기 근거 |
| 실제 DUT data lane 수 | 직접 측정·register 확인 없음 | 미확인 |
| 공개 N61 회로도에서 display DATA0/1/2와 CLK | 회로도 원문 텍스트에서 확인 | 3 data lane의 유력한 하드웨어 가설 |
| 4번째 lane | 회로도가 N56 예외로 따로 표시 | 다른 모델의 설정을 iPhone 6에 전용하지 않음 |
| iPhone 6의 실제 f_byte, f_DDR, R_lane, command/video mode | 확인되지 않음 | 절대 MHz 확정 금지 |

[Apple 공식 Display 항목](https://support.apple.com/en-ie/111954)은 해상도와 패널 종류를 확인해 주지만 DSI lane 수와 PLL을 공개하지 않는다.

[Apple 표기가 있는 공개 회로도 mirror](https://w.electrodragon.com/w/images/7/74/IPhone_6_SCH.pdf)의 PDF p20, DISPLAY:FLEX CONN에는 display DATA0/1/2 및 CLK, L2041-L2044 common-mode choke가 있고, N56의 추가 lane은 다른 페이지에 있다고 명시돼 있다. PDF p27에는 N61-specific 설정이 있다. 이는 원본 설계 도면 형태의 근거이나 **Apple의 공식 배포 경로가 아니며 진위·revision 및 사용자 DUT와의 일치를 독립 검증하지 못했다.** 여러 mirror는 같은 문서를 복제했을 수 있어 독립된 확인으로 세지 않는다. 본 검토는 관련 PDF 추출 텍스트를 읽었으며 이미지 렌더 결과를 직접 검증했다고 주장하지 않는다.

실무적으로 data lane 3개와 clock lane 1개를 합친 '4 differential pairs'를 '4 data lanes'와 혼동하지 않아야 한다. 회로도의 common-mode choke 존재는 방사 결합 경로 연구에 유용하지만, 단일 probe IQ가 CM만 포함한다는 증명은 아니다.

## 2. 속도·클록·주기 정의

이 노트의 f_b는 한 lane의 bit rate를 수치상 주파수로 쓰는 기호이고, 단위 표기에는 R_lane [bit/s]를 사용한다. 다른 문헌이 f_b를 기본 반복 주파수로 정의했다면 먼저 기호를 바꿔 읽는다.

- R_lane = f_b = 8 f_byte = 2 f_DDR.
- f_byte = 한 lane에서 초당 전달하는 byte 수, f_DDR = forwarded clock의 주기 주파수.
- N R_lane = 모든 data lane의 합계 raw bit throughput.
- 압축하지 않은 RGB888 payload 구간 평균 pixel throughput: f_p,payload = N R_lane/24 = N f_byte/3.
- RF 수신 중심 f_c, 수신 Fs, RF 순간 대역폭은 위 clock을 직접 결정하지 않는다.

[AMD PG202 Clocking Table1](https://docs.amd.com/r/en-US/pg202-mipi-dphy/Clocking) 및 [Arasan D-PHY clock 표](https://www.arasan.com/wp-content/uploads/2019/08/Total-MIPI-Camera-IP-Solution_CSI-2-v1.3_Aug-2019.pdf)는 byte clock과 lane rate/8의 관계를 교차 확인한다. Camera 프로토콜의 packet 규칙은 DSI로 옮겨 쓰지 않는다.

기존 forwarded-clock D-PHY의 RGB888 해석에 generic 8b/10b 배율 1.25를 추가하지 않는다. 사용자가 제시한 [Espressif 안내](https://docs.espressif.com/projects/esp-iot-solution/en/latest/display/lcd/mipi_dsi_lcd.html)의 해당 산식은 이 연구에 그대로 적용할 수 없다. Packet overhead와 HS/LP 시간은 실제 byte 수와 시간 점유율로 따로 계산한다. 최신 embedded-clock D-PHY의 coding 기능도 2014년 iPhone 6의 설정 근거가 아니다.

### 절대값의 조건부 하한

W×H 전체 화면을 f_update로 갱신하고 순수 RGB payload가 총 시간의 비율 eta를 점유하면:

    N R_lane eta = 24 W H f_update
    f_byte = 3 W H f_update / (N eta),  0 < eta <= 1

750×1334, f_update=60 Hz, eta=1을 둔 이론적 최소치:

| data lanes N | R_lane 최소 [Mbit/s] | f_byte 최소 [MHz] | f_DDR 최소 [MHz] |
|---:|---:|---:|---:|
| 1 | 1440.72 | 180.09 | 720.36 |
| 2 | 720.36 | 90.045 | 360.18 |
| 3 | 480.24 | 60.03 | 240.12 |
| 4 | 360.18 | 45.0225 | 180.09 |

실제 eta<1이면 더 빠른 lane rate가 필요하다. Full-frame update, 60 Hz, RGB888 모두 이 표의 조건이다. Command mode에서는 패널 refresh와 host update가 같지 않을 수 있다. 앞선 수신 중심 238 MHz가 240 MHz 근처라는 이유만으로 f_DDR이라고 확정할 수 없다. 재구성용 1100×1881 격자도 패널의 native pixel/blanking 수를 측정한 값으로 취급하지 않는다.

## 3. RGB888 byte round-robin 유도

사용자 보유 DSI v1.3 DRAFT §6(PDF31-33/인쇄19-21), §8.8.23(PDF77/인쇄65)을 다시 읽었다. 한 HS 전송의 protocol byte stream을 S[j]라 하면 lane l의 q번째 byte는 S[Nq+l]이다. SoT는 모든 활성 data lane에서 병렬로 발생하고, 그 이후 protocol byte를 분배한다. SoT sync를 한 개의 aggregate packet byte로 끼워 넣어 분배하지 않는다.

첫 payload R0가 aggregate index a에 있다면:

    j = Nq + l
    payload component = (j-a) mod 3       # 0:R, 1:G, 2:B
    pixel index       = floor((j-a)/3)

a에는 앞선 packet, 현재 header, DCS command가 포함된다. RGB888 video의 component 순서는 R,G,B이며 각 byte는 LSB-first이다. 아래 설명 표는 a=0에서 시작하는 payload-only 예다.

### 1 lane

    lane0: R0 G0 B0 R1 G1 B1 ...

### 2 lanes

| byte tick | lane0 | lane1 |
|---:|---|---|
| 0 | R0 | G0 |
| 1 | B0 | R1 |
| 2 | G1 | B1 |
| 3 | R2 | G2 |

### 3 lanes

| byte tick | lane0 | lane1 | lane2 |
|---:|---|---|---|
| 0 | R0 | G0 | B0 |
| 1 | R1 | G1 | B1 |
| 2 | R2 | G2 | B2 |

3 lanes일 때 각 lane의 component는 한 payload 안에서 고정될 수 있다. 그러나 a=4인 첫 video packet은 lane1=R, lane2=G, lane0=B로 회전한다. 첫 부분 tick의 lane0에는 아직 ECC가 있다. DCS command 1byte가 추가되면 a=5이므로 다시 회전한다. 따라서 RGB와 lane의 절대 대응을 packet offset 없이 지정하면 안 된다.

### 4 lanes

| byte tick | lane0 | lane1 | lane2 | lane3 |
|---:|---|---|---|---|
| 0 | R0 | G0 | B0 | R1 |
| 1 | G1 | B1 | R2 | G2 |
| 2 | B2 | R3 | G3 | B3 |
| 3 | R4 | G4 | B4 | R5 |

일반식은 다음과 같다.

    aggregate bytes per mapping cycle = lcm(3,N)
    byte-clock ticks per cycle P      = 3/gcd(3,N)
    bit intervals per lane per cycle  = 8P
    pixels per cycle                 = N/gcd(3,N)
    f_map                            = f_byte/P

| N | aggregate bytes | byte ticks P | 한 lane의 UI 수 | pixels/cycle | f_map |
|---:|---:|---:|---:|---:|---|
| 1 | 3 | 3 | 24 | 1 | f_byte/3 |
| 2 | 6 | 3 | 24 | 2 | f_byte/3 |
| 3 | 3 | 1 | 8 | 1 | f_byte |
| 4 | 12 | 3 | 24 | 4 | f_byte/3 |

**배치가 반복되는 것과 실제 비트 값이 반복되는 것은 다르다.** 임의 영상에서 이 f_map에 강한 선 스펙트럼이 반드시 생기지 않는다. 일정하지만 R/G/B가 서로 다른 단색 패턴은 이를 검사하는 데 도움이 된다. 반면 현재 black/white text에서는 넓은 내부 영역의 R=G=B와 00/FF 반복 때문에 lane 가설들이 퇴화할 수 있다. 00 또는 FF가 지속되면 data lane에는 내부 전이가 없을 수 있다.

같은 byte의 반복에서 55/AA는 2 UI, 33/CC는 4 UI, 0F/F0는 8 UI의 최소 디지털 주기를 가질 수 있다. 대응 후보는 f_b/2, f_b/4, f_b/8와 고조파이다. 가장 강한 RF 선은 결합·불균형·edge 응답에 따라 달라진다.

P_pixel개 pixel 패턴이 정확히 반복되는 합성 RGB888 입력의 경우 lane별 byte sequence는 3P_pixel/gcd(3P_pixel,N) ticks 후 반복한다. 이는 가능한 주기이며 데이터 값 대칭에 따라 최소 주기는 더 짧을 수 있다. 이런 여러 패턴을 쓰는 편이 단일 흑백 화면으로 lane 수를 역추정하는 것보다 식별 조건이 좋다.

## 4. 알려진 packet bits를 기준으로 삼는 후보

| 후보 | 알려진 부분 | 조건·제약 |
|---|---|---|
| D-PHY HS sync | 시간순 00011101 = LSB-first 0xB8 | lane마다 병렬. 한 HS당 발생하며 매 packet마다 반복하는 것은 아님 |
| EoTp | VC0 고정 codeword 08 0F 0F 01 | 기능 활성 여부를 확인. PHY HS trail/EoT와 구분 |
| Video RGB888 header | DT=0x3E, DI=(VC<<6) OR DT | VC/WC가 같을 때 ECC까지 반복. RGB888이라는 가정만으로 mode를 확정하지 않음 |
| DCS long write | DT=0x39, command0x2C 또는0x3C 후보 | command도 payload/WC에 포함. packet 경계와 chunk 크기 확인 |
| video sync short packets | DT와 일부 설정 | short packet 전체4bytes가 자동으로 고정되지는 않음 |
| Null/blanking | DT, 설정에 따른 WC | payload를 all-zero로 가정하지 않음 |
| CRC16 | payload의 결정적 함수 | 화면 bytes가 알려져야 예측 가능. 고정 training word로 일괄 사용 금지 |

HS sync는 [Keysight M8085A PDF68](https://www.keysight.com/ge/en/assets/9018-04458/user-manuals/9018-04458.pdf)에 확인된다. Packet 종류와 DCS command 구조는 [Microchip DS50003436A pp7,11-12](https://www.microchip.com/content/dam/mchp/documents/FPGA/ProductDocuments/UserGuides/Microchip_UG0948_PolarFire_MIPI_DSI_Transmitter_User_Guide_V1.pdf)로 교차 확인했다. EoTp/ECC 규칙의 상세 locator는 [이전 원문 검토 노트](../../mipi_dphy/packet_candidates_20261022.md)를 참조한다.

ECC는 첫24 header bits를 보호한다. Payload의 누락 정보를 복원해 주는 ECC로 해석하지 않는다. CRC도 analog 제한대역을 원상 복구하는 마법의 조건이 아니며, 여러 잘못된 waveform/template이 동일한 제한대역 관측을 만들 수 있다.

### 폭750에서의 정확한 조건부 header 후보

가정: VC0, packet 하나가 정확히750RGB888pixels를 운반하며 다른 payload byte가 없음. 실제 IQ에서 decode한 값이 아니다.

| 방식 | WC | header(DI WC_L WC_H ECC) | 총 길이 |
|---|---:|---|---:|
| video RGB888 | 2250=0x08CA | 3E CA 08 09 | 2256 bytes |
| DCS long write, command1byte 포함 | 2251=0x08CB | 39 CB 08 12, 다음 byte2C/3C | 2257 bytes |

ECC는 기존 DSI Table26 syndrome column을 XOR하여 JavaScript로 계산했다. 독립 규격 예제 08 0F 0F→01 및 37 F0 01→3F와 일치함을 먼저 확인했다. 이 작은 정수 검산은 실제 스마트폰 packet 검출을 검증한 것이 아니다.

같은 길이 L의 packet만 한 HS 안에서 연속한다면 시작 lane은 L mod N씩 전진하고 N/gcd(N,L) packets 후 돌아온다. 다른 packet 삽입, padding, chunk 크기, LP/SoT restart가 있으면 이 조건을 다시 써야 한다.

| 조건 | N=3 시작-lane 반복 | N=4 시작-lane 반복 |
|---|---:|---:|
| 750pixel video, L2256 | 1packet | 1packet |
| command1byte+750pixel, L2257 | 3packets | 4packets |
| 동일 short packet4bytes의 연속 | 3packets | 1packet |

따라서 N=3 가설의 검토에는 **3행/3packet 가족과 f_packet/3 후보**도 넣는다. 항상 packet cadence=화면 행 주사율이라고 놓지 않는다. HS마다 SoT로 재시작하면 시작 lane 누적 회전은 초기화된다.

## 5. 어떤 RF 대역을 우선 검사할 것인가?

수신11개 대역의 중심 100:60:700 MHz는 장비의 sweep grid이며 스마트폰의 주기 grid가 아니다. 사용자 보고 BW120MHz라면 명목상40-760MHz를 덮지만 filter transition과 실제 usable bandwidth는 따로 반영한다.

1. **N=3을 우선 모델로, N=4/2/1을 대조 모델로 유지한다.** N=3이면 RGB mapping 후보는 f_byte, N=4이면 f_byte/3이다. 둘을 같은 기본주파수로 강제 fitting하지 않는다.
2. 미지 R_lane에 대해 f_DDR=R_lane/2, f_byte=R_lane/8, f_map=R_lane*gcd(3,N)/24의 정수배와 sideband를 후보로 둔다. 750×1334×60의 계산치는 하한 검토에만 사용한다.
3. frame/row/HS가 반복하면 candidate carrier 주변에 k f_h 또는 l f_v 간격의 sideband/comb가 나타날 수 있다. 정지 프레임의 장기 반복 격자와 packet-burst envelope를 분리한다. 전역 영상 반복은 원칙적으로 f_v 격자를 만들 수 있어 모든 line을 별도 carrier로 세지 않는다.
4. 같은 RF line이 모든 화면 조건에서 남는지, payload/문자 경계에서 sideband가 변하는지 구분한다. 강한 선 하나는 clock·기타 clutter일 수 있다. 대역 선택은 peak power만이 아니라 독립 frame에서의 내용 의존성과 유효 spectral-bin 다양성으로 평가한다.
5. 인접 대역 overlap에서 phase/delay/CFO를 training packet 또는 선택 ROI로 추정한 뒤, untouched heldout payload에도 일관성이 개선되는지 확인한다. Header만 정렬되는 결과를 영상 stitch 성공으로 선언하지 않는다.
6. Packet template은 N, a mod N, polarity, bit order, VC/WC, video/DCS mode를 명시한다. lane별 RF transfer function이 다르므로 waveform들의 복소 가중합을 fit하되, heldout에 다시 fit하지 않는다.

이 노트만으로 특정100/160/...MHz pair를 좋은 대역으로 지정할 수 없다. 그 결정에는 실제 PSD, frame/packet coherence, clipping, band-edge 응답, 내용 의존성 및 이미 작성된 clutter audit이 필요하다.

## 6. 다음 확인을 위한 최소 증거

- DUT 모델/보드 identity와 display connector의 CLK,DATA0/1/2를 대조하거나 해당 firmware/driver의 활성-lane 설정을 확인.
- 실제 f_byte 또는 forwarded f_DDR를 별도 clock/probe 관측으로 확인. 그 다음 RGB888 식으로 f_b를 계산.
- R/G/B 단색과 동일 휘도 회색, byte 패턴55/33/0F,1pixel/2pixel stripes 등의 통제 입력을 비교해3-lane mapping 가설의 식별력을 확인.
- HS start, fixed-header candidate, payload, CRC/EoTp/HS end를 분리한 event notebook을 유지.

공식 주파수 설정이나 실제 packet decode가 확보되기 전까지는 **3-lane schematic hypothesis / RGB888 assumption / measured RF evidence**를 별도 필드로 보존한다.
