# LG / iPhone 6 stitching 측정: USRP-2940R 확인 노트

작성·문서 확인: 2026-10-22. 장비 조작 없이 공식 문헌을 검토한 측정 준비 자료다. 사용자는 USRP-2940R의 순시 대역폭을 120 MHz라고 밝혔다. 이를 작업 가정으로 채택한다. 실물의 제품 옵션, 현재 FPGA 이미지, 연결 경로와 실제 IQ 설정은 아직 읽지 않았다.

## 1. 모델과 대역폭

| 항목 | 확인 결과 | 근거 |
|---|---|---|
| USRP-2940 제품 옵션 | 40 MHz 및 120 MHz 모델이 존재 | [NI specifications, pp. 1–3](https://download.ni.com/support/manuals/374192d.pdf) |
| 120 MHz 모델 수신 | 최대 순시 실시간 대역폭 120 MHz; 최대 I/Q sample rate 200 MS/s; ADC 14 bit; 2 RX; 50 MHz–2.2 GHz | 같은 문서 p. 3의 Receiver 표 |
| Ettus 대응 | X310 + WBX; WBX-120은 120 MHz RF daughterboard | [NI USRP brochure, Table 1](https://www.ni.com/content/dam/web/pdfs/usrp-software-defined-radio.pdf), [Ettus AN-177, Analog Bandwidth](https://kb.ettus.com/About_USRP_Bandwidths_and_Sampling_Rates) |

`2940R`라는 모델명만으로 120 MHz 옵션을 식별하지 않는다. 측정 기록에 제품 라벨의 120 MHz 표기 또는 configuration/probe에서 읽은 daughterboard ID를 한 번 남기면 된다. ADC 14 bit와 저장 파일의 int16 I/Q 표현도 별도 항목이다.

다음 값은 서로 다르다.

- **B_inst**: 한 tuning에서 RF chain이 동시에 받아들이는 대역.
- **Fs_IQ**: 저장하는 복소 샘플 수/초. 복소 Nyquist 구간 전체 폭은 Fs_IQ이지만 usable passband는 아날로그·디지털 필터로 좁아진다.
- **B_use**: 정렬/합성에 실제 사용하는, 응답과 위상 품질을 검증한 내부 대역.
- **sweep span**: 여러 tuning의 중심 주파수 또는 측정 구간이 이동한 범위. 표현할 때 어느 정의인지 명시한다.
- **B_synth**: 정렬 후 합친 서로 다른 RF 주파수 구간의 폭.

따라서 “100 MHz를 sweep하면서 여러 중심 주파수에서 복원됨”은 여러 RF 구간에 화면 관련 정보가 있다는 유망한 관측이다. 그 관측만으로 구간 사이 complex phase/delay 정합 또는 새 공간 해상도 획득까지 확정되지는 않는다. 같은 narrow harmonic/클러터가 이동한 수신창마다 보인 경우도 구분해야 한다. 후자의 결론은 overlap와 held-out 복원으로 시험한다. 이 문단은 실험 설계상의 해석이다.

## 2. 120 MHz 수신과 호스트로의 저장

Ettus 문서는 RF, FPGA, host 경로 중 가장 좁은 구간이 시스템 대역폭을 제한한다고 설명한다. AN-177의 16-bit I/Q 인터페이스 표는 X300/X310의 10GbE 및 4-lane PCIe를 최대 200 MS/s로 제시하지만 실제 성능 보장은 아니다. [Ettus AN-177, Host Bandwidth](https://kb.ettus.com/About_USRP_Bandwidths_and_Sampling_Rates)

**유도값, 단일 RX·int16 I + int16 Q·헤더 제외:**

| Fs_IQ | 파일 기록률 | payload bit rate | 0.5 s 파일 |
|---:|---:|---:|---:|
| 100 MS/s | 400 MB/s | 3.20 Gb/s | 200 MB |
| 184.32 MS/s | 737.28 MB/s | 5.89824 Gb/s | 368.64 MB |
| 200 MS/s | 800 MB/s | 6.40 Gb/s | 400 MB |

이 경로에서 1GbE continuous raw IQ로 100 MHz 이상을 보존할 수 없다. FPGA 처리 또는 실제로 구현된 온보드 finite capture는 host streaming과 별도 평가한다. 1,024 MB DRAM이라는 하드웨어 사양만으로 현재 API가 전부 사용한다고 가정하지 않는다. 2 RX를 동시에 200 MS/s로 저장하면 위 표의 파일률과 payload가 2배가 된다.

X3x0 stock DDC의 IQ rate는 master clock의 허용 정수 분주값이다. 200 MHz master clock일 때 200, 100, 약 66.667, 50 MS/s 등이 가능하며 요청값은 coercion될 수 있다. 120 MHz IQ rate가 임의로 가능하다고 설정하지 않고 실제 반환값을 기록한다. 120 MHz RF passband를 보존하려면 200 MS/s 후보가 자연스럽다. NI의 `B ≈ 0.8 Fs`는 filter roll-off를 피하는 실무 지침이며 120 MHz RF 제한이나 측정 응답을 대체하지 않는다. [UHD 4.9 X3x0, Setup Clocking](https://files.ettus.com/manual_archive/v4.9.0.0/html/page_usrp_x3x0.html), [NI IQ rate 설명](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA00Z000000kIpTSAU)

## 3. 현재 선택 가능한 수집 경로

| 경로 | 공식 지원의 범위 | 이번 측정에서의 판단 |
|---|---|---|
| 기존 LabVIEW + NI-USRP / USRP RIO | NI guide는 2940R과 NI-USRP instrument driver, sample projects를 설명. NI-USRP 20.0 readme는 40/120 MHz 양쪽을 명시 | 이미 동작하는 측정 VI와 driver/FPGA 조합이 있으면 유지하고 IQ+metadata export 추가. readme 20.0은 역사적 근거이며 현재 설치 버전 호환성을 대신하지 않음 |
| MATLAB R2026b + Wireless Testbench Support Package + UHD | X310/WBX는 `comm.SDRuReceiver` 등의 **live data I/O** 지원. R2026b UHD는 4.9.0.0. X3xx PCIe는 이 MATLAB 경로에서 지원하지 않음 | 10GbE + 지원 FPGA/driver 조합 + 실제 throughput 검증을 전제로 후보. WBX에 `basebandReceiver`의 onboard capture workflow 지원을 가정하지 않음 |
| 새 NI LabVIEW UHD/Python 예제 | NI official repo는 LabVIEW 2025 Q3+, UHD/Python API 4.8+ 예제 제공 | README의 host streaming limitation은 몇 MS/s. 이 예제만으로 200 MS/s 저장 경로가 생겼다고 판단하지 않음 |

출처: [NI getting started, pp. 8–10, 15](https://download.ni.com/support/manuals/375717h.pdf), [NI-USRP 20.0 Readme](https://www.ni.com/pdf/manuals/374760x.html), [MathWorks R2026b Supported Radio Devices](https://www.mathworks.com/help/wireless-testbench/gs/supported-sdr-devices.html), [NI official LabVIEW UHD examples](https://github.com/ni/labview-usrp-examples).

MATLAB `comm.SDRuReceiver`에서 `len`과 `overrun`을 매 호출 기록해야 한다. burst buffering 옵션도 존재하지만 burst 사이 연속성이나 물리적 전체 DRAM 활용을 보장하는 것으로 해석하지 않는다. [MathWorks SDRuReceiver, Output Arguments / Burst Mode Buffering](https://www.mathworks.com/help/wireless-testbench/ref/comm.sdrureceiver-system-object.html)

## 4. retune, LO phase, clock

UHD 4.9 문서는 10 MHz를 공통 frequency reference, PPS를 device sample-time 기준으로 구별한다. timed stream start는 digital CORDIC 정렬에 쓰인다. LO의 deterministic retune 예외 항목은 SBX/UBX/OBX이며 WBX를 그 항목에 포함시키지 않는다. 다른 frontend는 tuning 후 임의 위상 offset이 생길 수 있고 retune마다 다시 정렬해야 한다. [UHD 4.9 Device Synchronization, Common Reference Signals / Align CORDICs / Align LOs](https://files.ettus.com/manual_archive/v4.9.0.0/html/page_sync.html)

**이번 stitching 설계에 대한 추론:**

- 공통 10 MHz/PPS가 있어도 스마트폰 DSI/panel clock이 USRP clock에 잠기는 것은 아니다. frame timing, fractional delay/rate, residual frequency offset는 별도로 추정한다.
- 각 band에 독립 LO phase offset을 허용한다. phase가 tuning 사이 보존된다고 전제하지 않는다.
- retune 완료·LO lock·transient discard·capture start를 분리해 기록한다. settle 시간은 임의 상수로 확정하지 않고 짧은 반복 수집에서 안정성을 검사한다.
- band마다 gain을 바꾸면 알려진 gain 값뿐 아니라 실제 complex transfer도 달라질 수 있다. 1차 비교는 fixed gain, 고정 probe/antenna 위치, 동일 화면/밝기/충전상태로 수행한다.
- overlap에서 상수 위상과 delay의 선형 phase slope로 설명되지 않는 잔차가 있으면 RF filter/group delay 또는 화면 비정상성을 검사한다. 낮은 진폭·간섭·DC 근처 bin은 신뢰도를 따로 둔다.

## 5. 현재 데이터에 연결한 첫 측정 후보

**측정 확정값이 아닌 설계 후보:** 이전 캡처의 중심은 LG X2 344.8 MHz, iPhone 6 238 MHz다. iPhone **6s**의 311 MHz를 이번 iPhone **6**에 대입하지 않는다. 기존 파일은 center/BW/타이밍 참고이며 연속된 stitching acquisition으로 취급하지 않는다.

1. 실제 120 MHz 옵션과 호스트 경로 확인 후, 기존 성공 중심에서 단일 band IQ를 보존한다.
2. 같은 원시 wideband capture를 software로 두 overlapping subband로 나눠 algorithm/in-band calibration을 먼저 검증한다. 이는 sequential retune drift를 시험하지 않으므로 다음 단계가 필요하다.
3. 실제 sequential band 측정은 처음에는 충분한 overlap을 둔다. 예: **B_use=100 MHz, center step=50 MHz**이면 인접 overlap=50 MHz. 이 예의 숫자는 passband와 신호가 실제로 충분한 구간에서만 채택한다.
4. 세 중심 `f0−50, f0, f0+50 MHz`의 합성 구간은 폭 200 MHz다. 후보 중심은 LG `[294.8,344.8,394.8] MHz`, iPhone6 `[188,238,288] MHz`; 유효 대역 가정하 총 구간은 각각 `[244.8,444.8]`, `[138,338] MHz`. 100 MHz center-span과 200 MHz synthesized width를 혼용하지 않는다.
5. 순서를 `center → lower → center → upper → center`로 두어 anchor drift와 화면 재현성을 확인한다. 각 band 0.5 s는 60 Hz가 실제 맞을 때 약 30 frame에 해당하는 시작 후보이며 고정 요구가 아니다.
6. overlap 일부로 추정한 정렬을 다른 시간/주파수 구간에서 검증한다. 단일 band, magnitude-only 합성, phase/delay-corrected 합성을 같은 화면·정규화로 비교한다.

## 6. 사용자에게 확인할 최소 항목

측정 설계는 위 가정으로 계속할 수 있다. 실제 수집 실행 전 필요한 미확인값은 세 가지다.

1. 2940R **120 MHz 옵션**을 보여주는 라벨 또는 configuration 정보.
2. 현재 PC 연결이 **10GbE / PCIe-MXI / 1GbE** 중 무엇이며, 기존 동작하는 LabVIEW VI·NI-USRP 버전이 있는지.
3. “100 MHz sweep”가 **중심 주파수 이동 폭**인지, **한 번의 IQ 수집 폭**인지 및 복원이 확인된 시작/끝 중심 주파수.

최소 메타데이터: phone/model, pattern ID/hash, capture order, requested/actual fc·Fs·BW, usable passband, master/reference clock, time source, receiver/daughterboard/FPGA/driver identity, gain, antenna/거리/방향, display state, tune/lock/discard/start/end time, dropped/late/overflow counts, scalar format/endian, raw SHA-256. 새 실측은 아직 수행하지 않았다.
