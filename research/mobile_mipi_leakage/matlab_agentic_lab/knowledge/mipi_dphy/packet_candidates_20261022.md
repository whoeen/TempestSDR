# DSI/D-PHY의 반복 packet·HS 구조: stitching 및 복원 후보

작성: 2026-10-22, 담당 mipi_packet_candidates. 범위는 forwarded-clock D-PHY와 압축하지 않은 RGB888 가정이다. 실제 LG X2/iPhone 6의 lane 수·동작 모드·bit rate·packetization은 아직 측정으로 확인하지 않았다.

## 출처와 이번 독해 범위

- **S1** 사용자 로컬 MIPI Alliance *Specification for Display Serial Interface (DSI)* v1.3, 23 March 2015, **user-supplied DRAFT**. 파일 identity는 기존 sources.jsonl의 local_dsi_v13(SHA256 8252c82e49f093c21fced2d848d5e3cf391b2fe12a24feb18b921069c2f78dea). 이번에 PDF 28–36, 53–58, 60–70, 77, 86–102의 텍스트를 읽었다. 인쇄 본문 page = PDF page − 12. 일부 header가 DRAFT이며 사용자 보유본의 공식 배포본 대조는 미완료다. 원문 재배포 없이 해석·사실만 기록한다.
- **S2** Keysight *M8085A MIPI D-PHY Editor User Guide*, M8085-91040, Edition 6.2, June 2019. 공식 PDF의 pp.31–33, 87–88, 116–118 관련 절을 웹 텍스트로 확인했다. 전체 186쪽을 정독했다고 주장하지 않는다. https://www.keysight.com/ge/en/assets/9018-04458/user-manuals/9018-04458.pdf
- **S3** Linux upstream include/video/mipi_display.h, 2026-10-22 열람. DSI Data Type enum과 DCS command enum을 구분하여 확인. URL의 master는 이동 가능하므로 규범 버전 근거가 아니라 구현 교차검증이다. https://raw.githubusercontent.com/torvalds/linux/master/include/video/mipi_display.h
- **S4** Microchip UG0948 *PolarFire MIPI DSI Transmitter User Guide*, DS50003436A, 2022, pp.5–7 packet structure/table 4-1의 검색 추출 텍스트로 DT 값을 교차 확인했다. https://www.microchip.com/content/dam/mchp/documents/FPGA/ProductDocuments/UserGuides/Microchip_UG0948_PolarFire_MIPI_DSI_Transmitter_User_Guide_V1.pdf
- ST AN4860 영어 PDF는 web 도구 크기 제한, Lattice FPGA-IPUG-02321 PDF는 직접 열기 404로 전체 내용을 확보하지 못했다. 그 검색 발췌를 규범 원문 정독으로 집계하지 않는다. S2의 PDF screenshot 두 페이지 요청 중 하나는 cache miss였으며 이번 검토는 해당 부분의 텍스트를 근거로 한다.

## 1. 같은 '동기'여도 층이 다르다

### D-PHY SoT와 HS Sync

통상적인 HS 전송은 LP 상태에서 시작하여 HS-0 구간 및 HS sync를 거친다. HS sync의 **시간순 비트열은 00011101**이다. 이를 DSI의 LSB-first byte로 쓰면 **0xB8**이다. 0xB8의 일반적인 MSB-first 표기 10111000과 혼동하지 않는다. S2 p.116은 HS-0 뒤 leader pattern을 확인해 준다. DSI의 LSB-first 정책은 S1 §8.3, PDF55/인쇄43이다.

S1 §6, PDF32/인쇄20: **모든 활성 data lane이 SoT를 병렬 수행**한 후 packet byte stream을 round-robin으로 분배한다. 0xB8은 N lane에 순서대로 한 번씩 분배하는 DSI packet byte가 아니다. Clock lane은 source-synchronous clock 역할이며 이 data-lane sync byte를 같은 방식으로 보내는 것으로 모델링하지 않는다.

**SoT 한 번 = HS transmission 한 번의 시작**이다. S1 §8.1, PDF53–54/인쇄41–42는 하나의 HS transmission에 여러 short/long packet을 이어 붙일 수 있음을 명시한다. S1 §8.5.1.2, PDF58/인쇄46에는 모든 packet의 시작과 끝을 가리키는 별도 embedded sync code가 없다는 설명이 있다. 뒤따르는 packet은 DT와 WC로 길이를 세어 경계를 찾는다. 따라서 매 packet 앞에 B8을 삽입하는 합성 모델은 잘못된다.

### DSI H/V Sync Event

Video mode에서 VSS/VSE/HSS/HSE는 PHY HS sync와 별개인 **4-byte short packet**이다. 여기서 H는 horizontal이고, HS는 high speed를 뜻하는 경우도 있으므로 변수 이름을 분리한다.

| 사건 | DT | 고정되는 것 | 추가로 알아야 하는 것 |
|---|---:|---|---|
| V Sync Start | 0x01 | 6-bit DT | VC, Data0/Data1, ECC, 실제 video mode |
| V Sync End | 0x11 | 6-bit DT | 위와 같음 |
| H Sync Start | 0x21 | 6-bit DT | 위와 같음 |
| H Sync End | 0x31 | 6-bit DT | 위와 같음; sync-events mode에서는 생략 가능 |

S1 §8.8.1–8.8.1.2, PDF62–63/인쇄50–51. VSS는 첫 VSA line의 HSS도 암시하고 VSE도 지정된 수평 시작을 암시하므로 각각 옆에 HSS가 반드시 더 있는 것으로 세지 않는다. Sync-event payload를 언제나 00 00으로 가정하지 않는다. VSS payload에는 부가 정보를 실을 수 있다. 단말 설정 또는 실제 검증으로 해당 bytes가 일정함을 확인하면 그때 전체 32-bit packet을 template로 삼는다.

## 2. 후보군 우선순위

| 후보 | 고정/조건부 성질 | 활용 | 실패 조건과 근거 |
|---|---|---|---|
| HS 진입·HS-0·B8·초기 header의 결합 | B8 고정; 상태 순서 반복; timing과 header는 설정 의존 | burst 경계, subband별 경험적 template, delay/CFO 추적 | HS 한 번에 여러 packet; RF 결합 경로/필터가 waveform을 바꿈. S1 §6·8.1; S2 p.116 |
| **EoTp: 08 0F 0F 01** | **VC=0까지 포함한 고정 4-byte packet** | 존재하면 HS 끝의 좋은 알려진 codeword 후보 | EoTp 기능을 비활성할 수 있음; PHY EoT와 다름; byte들은 lane에 분배됨. S1 §8.8.2 PDF63–64/인쇄51–52; S2 p.33 |
| RGB888 video long-packet header | DI=(VC<<6) OR 0x3E; WC 및 ECC가 고정되면 4bytes 고정 | active packet/line 구간, 가능한 WC/lane mapping 검정 | RGB888이라고 command mode까지 DT3E가 되는 것은 아님. S1 §8.8.23 PDF77/인쇄65 |
| DCS long-write header + 2C/3C | DT0x39; command 0x2C write-memory-start, 0x3C continue | command mode의 update/chunk 구간 식별 | chunk 크기·partial update·command 순서 변동; command byte와 DT는 서로 다른 필드. S1 §8.8.9.3 PDF66; S3 DCS enum |
| H/V sync short packets | DT 및 event cadence가 구조화됨 | line/frame 기준, 서로 다른 event의 조합으로 주기 ambiguity 감소 | video mode 종류/생략/부가 payload 고려; command mode에 그대로 강제 불가. S1 §8.11 PDF87–91 |
| Null0x09 / blanking0x19 header | 고정 DT; 설정이 같으면 WC/ECC 반복 가능 | 비영상 구간/점유율 분류, header template 확장 | **payload는 임의값 가능. null/blanking을 all-zero training data로 취급 금지.** S1 §8.8.11–12 PDF67/인쇄55 |
| Clock lane의 연속/비연속 활동 | HS 중 공통 clock, gating은 모드 의존 | lane rate 후보, CFO/clock drift의 보조 기준 | clock emission에 정렬된 것이 pixel payload coherence를 보장하지 않음. S1 §5.6 PDF28 |
| PHY EoT/HS-trail | 끝 bit 반대 상태를 유지하는 구조 | burst 종료 시점의 상태 template | 마지막 bit가 data 의존이므로 항상 같은 0/1 sequence는 아님. S1 §8.8.2; S2 p.87 |
| TE, 초기·주기 deskew, optional preamble | 구현/버전 조건부 | 별도 cadence 및 상태 진단 | 기본 pilot으로 넣지 않음. In-band TE는 LP 역방향 제어이고 HS payload sync가 아님. D-PHY2.1의 고속 optional preamble을 구형 폰에 소급하지 않음. S1 §5.6.1·8.12; S2 pp.116–118 |

EoTp는 다른 packet과 달리 고정성이 강하지만 **가장 강하게 보일 것이라는 보장은 없다**. RF band에 따라 결합, 상쇄, impulse response가 달라진다. 먼저 존재와 반복성을 확인한 후 선택한다.

## 3. RGB888 header와 lane 배치의 구체적 예

Byte stream 형식:

- Video: DI, WC_L, WC_H, ECC, R0, G0, B0, R1, G1, B1, ..., CRC_L, CRC_H.
- Command long write: DI, WC_L, WC_H, ECC, DCS_command, RGB parameter bytes..., CRC_L, CRC_H. 이 경우 **WC에는 command byte 1개도 포함**한다.
- DI의 상위 2bits는 VC, 하위6bits는 DT. RGB888 DT3E의 전체 DI 후보는 3E/7E/BE/FE다.
- ECC는 먼저오는 24 header bits에 대한 결정적 값이다. Payload CRC는 payload 내용에 종속된다. 화면이 바뀌어도 header가 같을 수 있지만 CRC는 일반적으로 달라진다. ECC는 payload 오류수정코드가 아니다. S1 §9, PDF95–101.

**1080 pixels가 하나의 video packet에 들어가는 가정 예**:

WC=3×1080=3240=0x0CA8, VC=0일 때 header는 **3E A8 0C 22**다. ECC22는 S1 Table26의 D0–D23 syndrome columns를 XOR하여 파생했다. 같은 규칙의 검산은 S1 Figure46의 37 F0 01 → ECC3F 및 EoTp08 0F 0F → ECC01에 일치한다. 수치 계산은 JavaScript로 수행했으며 모바일 IQ decode 결과가 아니다.

ECC 재현 locator: **S1 §9.3 Table25–26, PDF96–98/인쇄84–86**, 최적화된 P0–P5 식은 PDF98–99/인쇄86–87, 독립 예제는 **§9.4 Figure46, PDF99/인쇄87**이다. Table26의 첫24 syndrome columns를 D0부터 쓰면:

`07 0B 0D 0E 13 15 16 19 1A 1C 23 25 26 29 2A 2C 31 32 34 38 1F 2F 37 3B`

24-bit header의 정수 표현을 DI + 256×WC_L + 65536×WC_H로 잡고, bit가1인 위치의 column들을 XOR하면 ECC이다. P6와 P7는0이다. 위 계산의 JavaScript 구현은 독립 행렬공식을 사용하였고 EoTp 고정값 및 Figure46에 대조했다. **EoTp08 0F 0F 01은 독립 ECC sanity vector로 사용할 수 있다.** 다만 그 일치가 모든 packet 생성 또는 analog 복원을 검증하는 것은 아니다.

4 lane, 해당 packet이 HS transmission의 첫 packet이라면:

| byte-clock slot | Lane0 | Lane1 | Lane2 | Lane3 |
|---|---|---|---|---|
| PHY sync | B8 | B8 | B8 | B8 |
| 첫 packet header | 3E | A8 | 0C | 22 |
| payload0 | R0 | G0 | B0 | R1 |
| payload1 | G1 | B1 | R2 | G2 |
| payload2 | B2 | R3 | G3 | B3 |

SoT 이후 첫 packet의 DI는 Lane0에서 시작한다. **같은 HS에 이어진 다음 packet의 첫 byte도 항상 Lane0라고 가정하면 안 된다.** 직전 packet·null·short packet들을 포함한 누적 byte 수 mod N을 관리한다. 시작 lane offset을 a, packet 내부 byte index를 k라 하면 lane=(a+k) mod N이다. 다음 packet의 a는 전체 packet 길이만큼 진전한다. 별도의 LP/SoT 재시작 시에는 첫 byte Lane0 정렬로 돌아간다.

새 주기성 후보도 여기서 나온다. 위 RGB888 packet 길이는3246bytes이고 3246 mod4=2다. 다른 packet/채움 없이 같은 길이의 packet을 계속 한 HS에 이어 붙이면 header 시작 lane이 0,2,0,2,...로 교대할 수 있다. 이 조건에서는 packet-level content와 별도로 **2-packet 주기의 lane 혼합 파형**이 생길 수 있다. DCS0x39에 command1byte+동일3240RGB bytes를 싣는 가정에서는 WC3241, 길이3247, mod4=3이고 시작 lane은4-packet 주기로 반복한다. 이 예의 header는39 A9 0C 39다. 실제 폰에서 이런 packetization이 쓰였다는 주장은 아니다. 한line당SoT 재시작, 다른 chunk크기, 간삽packet, padding정책이 있으면 주기가 달라진다.

## 4. '알려진 비트'가 RF에서 의미하는 것

최소 측정 모델은 다음과 같이 잡는다.

r_m(t) = exp(j[2πΔf_m t + φ_m]) × B_m{ Σ_l h_l * s_l(t−τ_m) + h_clock * c(t−τ_m) + other(t) } + n_m(t).

m은 sweep band, s_l은 packet bytes를 lane분배·LSB직렬화하고 PHY state까지 넣은 신호, h_l은 lane별 방사/전파/수신 응답, B_m은 실제 수신대역 필터이다. 이 식은 국소 선형 결합 후보모델이며 DM→CM변환과 상태 전환의 비선형성은 잔차로 검증한다.

따라서 알려진 logicalbytes를 안테나 IQ와 직접 bitwise matching하지 않는다. **예측한 multi-lane waveform을 동일한 수신 대역으로 제한하거나, 반복 event에서 RF template을 학습한 뒤 matching**해야 한다. 미지의 채널을 적절히 제한한 matched subspace/GLRT도 후보지만 채널 자유도를 지나치게 높이면 어느 clutter라도 맞춰진다.

### 짧은 pilot과 lane 혼합의 한계

- R_lane≈1Gb/s이면 B8의 길이는8ns이다. 4lane의32bit DSIheader는 **시간상8UI≈8ns**에 전달된다. 32ns의 serial single-lane header로 계산하면 틀린다.
- BW120MHz의 대략적 reciprocal scale은8.33ns다. 단일header가 시간상 한 resolution cell에 가까울 수 있어, 반복적이라고 해서 byte bits가 즉시 식별되는 것은 아니다. 정확한 delay 추정오차는 SNR, RMS bandwidth, 파형, 반복 수에 달려 있으며1/B는 절대적인 추정한계가 아니다.
- 모든 lane이 동일한 B8을 동시에 보내는 구간에서는 입력들이 선형적으로 종속된다. 여기서 관측한 template은 대체로 lane들의 **합성 응답**이다. SoT만으로 각 lane의 독립 h_l을 식별할 수 없고, 그 합성응답을 arbitrary RGB payload에 그대로 적용해 완전복원할 수 없다.
- EoTp/header는 lane별로 다른 bytes를 주므로 추가조건을 줄 수 있지만 짧고 대역 제한되어 있다. 여러 WC/command/known test-image 조건을 써서 관측행렬 rank와 condition number를 확인해야 한다.
- 임의의 narrow RF slice에서 물리적 channel 위상은 미지다. codeword를 안다는 사실만으로 서로 떨어진 band의 절대 RF위상을 정할 수 없다. overlap에서 동일 사건을 대조하거나 calibrated forwardmodel로 상대phase/delay를 검증한다.

## 5. stitching에서 후보를 쓰는 순서

1. **HS event 후보 검출**: magnitude 변화만으로 확정하지 않고 complexIQ의 반복성, event폭, clock gating관계를 함께 본다. 여러profile class를 유지한다.
2. **event 구조 비교**: SoT+초기header, 중간header, EoTp/HS종료를 분리한다. 화면을 바꿔도 유지되는 부분은 protocolpilot 후보, 함께변하는 부분은 payload후보다.
3. **정렬을2단계로 분리**: packet/HSburst sequence로 coarse delay 및 정수packet ambiguity를 줄이고, overlappingRF구간의 complexcoherence로 fractional delay, residual CFO, relativephase를 맞춘다.
4. **반복 간 timing slope 추정**: event time의 frame/packet별 drift로 fractional resampling을 추정한다. phase와delay를한개의상수로만맞춘후긴capture를합성하지 않는다.
5. **독립 검증**: template학습에쓴packet/frame을검증에서제외한다. 여러band의overlap에서 동일event의위상잔차·delay잔차·coherence를 보고, 같은보정이 held-out payload에도통하는지확인한다.
6. **화면 정보 평가**: header만선명해지거나세로선만증가하는것과 pixelROI가개선되는것을따로기록한다. headerpilot은동기원일수있지만그자체는화면정보가아니다.

유사한 packet이 매T마다반복되면 timing상관은정수T만큼모호하고, event간 phase는mod2π이다. 다른종류의event순서(VSS→HSS..., write-start→continue...), 길이변화, A–B–A기준대역재방문을조합한다. 연속clock이멈췄다재시작하거나 burst timing이흔들리는경우, 디지털word가같아도전band에걸친RFphase가같다고단정하지않는다.

## 6. 이번에확인한것과미확인사항

확인: 상위후보의protocol값과조건, knownheader/CRC의구분, HSburst/packet구분, round-robin으로인한lanephase추적필요, 조건부headerECC예.

미확인: LG와iPhone6의실제DT/VC/WC, lanecount, DCSchunking, EoTp설정, HS/LPcadence, clockcontinuous설정, 실제laneEMchannel, 제한대역에서각후보의검출가능성. 이문서는문헌·파생모형이며 실측packetdecode 또는coherentstitching성공보고가아니다.
